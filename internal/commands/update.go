package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/client"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/update"
	"github.com/spf13/cobra"
)

// Update is the update command group
var Update = &cobra.Command{
	Use:   "update",
	Short: "Manage CLI updates",
	Long: `Check for and install updates to the parts CLI.

The update system respects your installation method:
  - Manual installations can self-update
  - Package manager installations (Homebrew, apt, yum) should use their respective update commands

Updates are downloaded from Source Parts API with fallback to GitHub Releases.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
	Example: domain.BinaryName + ` update check
` + domain.BinaryName + ` update apply
` + domain.BinaryName + ` update status
` + domain.BinaryName + ` update config --auto-check=true`,
}

var updateCheck = &cobra.Command{
	Use:   "check",
	Short: "Check for available updates",
	Long:  `Check if a new version of the CLI is available.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		fmt.Printf("Current version: %s\n", domain.Version)

		// Detect installation method
		installMethod, err := update.DetectInstallMethod()
		if err != nil {
			return fmt.Errorf("failed to detect install method: %w", err)
		}
		fmt.Printf("Install method:  %s\n\n", installMethod)

		fmt.Println("Checking for updates...")

		// Check for updates
		result, err := update.CheckForUpdate(ctx, domain.Version, http.DefaultClient)
		if err != nil {
			return fmt.Errorf("failed to check for updates: %w", err)
		}

		if !result.UpdateAvailable {
			fmt.Printf("✓ You're running the latest version (%s)\n", domain.Version)
			return nil
		}

		// Update available
		fmt.Printf("📦 Update available: %s → %s\n", result.CurrentVersion, result.LatestVersion)

		if result.Release.Changelog != "" {
			fmt.Printf("\nWhat's new:\n%s\n", formatChangelog(result.Release.Changelog))
		}

		// Show installation instructions based on method
		if result.CanSelfUpdate {
			fmt.Printf("\nTo install this update, run:\n  %s update apply\n", domain.BinaryName)
		} else {
			pkgCmd := update.GetPackageManagerCommand(installMethod)
			if pkgCmd != "" {
				fmt.Printf("\nTo update, run:\n  %s\n", pkgCmd)
			}
		}

		return nil
	},
}

var (
	applyYesFlag bool
)

var updateApply = &cobra.Command{
	Use:   "apply",
	Short: "Download and install an available update",
	Long:  `Download and install the latest version of the CLI.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()

		// Verify we can self-update
		installMethod, err := update.DetectInstallMethod()
		if err != nil {
			return fmt.Errorf("failed to detect install method: %w", err)
		}

		if !update.CanSelfUpdate(installMethod) {
			pkgCmd := update.GetPackageManagerCommand(installMethod)
			return fmt.Errorf("cannot self-update: installed via %s\nTo update, run: %s", installMethod, pkgCmd)
		}

		// Check for updates
		fmt.Println("Checking for updates...")
		result, err := update.CheckForUpdate(ctx, domain.Version, http.DefaultClient)
		if err != nil {
			return fmt.Errorf("failed to check for updates: %w", err)
		}

		if !result.UpdateAvailable {
			fmt.Printf("✓ Already running the latest version (%s)\n", domain.Version)
			return nil
		}

		// Find appropriate asset
		asset := update.FindAssetForPlatform(result.Release.Assets)
		if asset == nil {
			return fmt.Errorf("no compatible asset found for your platform")
		}

		// Show update details
		fmt.Printf("Update %s → %s\n", result.CurrentVersion, result.LatestVersion)
		fmt.Printf("Asset: %s (%.2f MB)\n", asset.Name, float64(asset.Size)/(1024*1024))

		// Confirm update unless --yes flag
		if !applyYesFlag {
			fmt.Printf("\nContinue? [y/N]: ")
			var response string
			fmt.Scanln(&response)
			response = strings.ToLower(strings.TrimSpace(response))
			if response != "y" && response != "yes" {
				fmt.Println("Update cancelled.")
				return nil
			}
		}

		// Download and install
		fmt.Printf("Downloading %s...\n", asset.Name)
		if err := update.DownloadAndInstall(ctx, asset, http.DefaultClient); err != nil {
			return fmt.Errorf("failed to install update: %w", err)
		}

		fmt.Printf("✓ Successfully updated to %s\n", result.LatestVersion)
		fmt.Println("Please restart the CLI for the changes to take effect")

		return nil
	},
}

var (
	configAutoCheck  *bool
	configInterval   int
	configPrerelease bool
)

var updateConfig = &cobra.Command{
	Use:   "config",
	Short: "Configure update settings",
	Long: `Configure automatic update checking and other update preferences.

Settings are stored securely in your system keychain.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// Load existing config or use defaults
		var config *update.UpdateConfig
		configData, err := client.LoadUpdateConfig()
		if err != nil {
			return fmt.Errorf("failed to load update config: %w", err)
		}

		if configData == nil {
			config = update.DefaultConfig()
		} else {
			// Unmarshal from map to struct
			jsonData, _ := json.Marshal(configData)
			config = &update.UpdateConfig{}
			if err := json.Unmarshal(jsonData, config); err != nil {
				config = update.DefaultConfig()
			}
		}

		// Update config from flags if provided
		modified := false
		if cmd.Flags().Changed("auto-check") {
			config.AutoCheck = *configAutoCheck
			modified = true
		}
		if cmd.Flags().Changed("interval") {
			config.Interval = configInterval
			modified = true
		}
		if cmd.Flags().Changed("prerelease") {
			config.Prerelease = configPrerelease
			modified = true
		}

		// Save if modified
		if modified {
			if err := client.SaveUpdateConfig(config); err != nil {
				return fmt.Errorf("failed to save update config: %w", err)
			}
			fmt.Println("✓ Update configuration saved")
		}

		// Display current configuration
		fmt.Println("\nCurrent update configuration:")
		fmt.Printf("  Auto-check:  %v\n", config.AutoCheck)
		fmt.Printf("  Interval:    %d hours\n", config.Interval)
		fmt.Printf("  Prerelease:  %v\n", config.Prerelease)
		if !config.LastCheckTime.IsZero() {
			fmt.Printf("  Last check:  %s\n", config.LastCheckTime.Format(time.RFC3339))
		}

		return nil
	},
}

var updateStatus = &cobra.Command{
	Use:   "status",
	Short: "Show version and update configuration",
	Long:  `Display the current CLI version, installation method, and update settings.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("Version:          %s\n", domain.Version)

		installMethod, err := update.DetectInstallMethod()
		if err != nil {
			return fmt.Errorf("failed to detect install method: %w", err)
		}

		fmt.Printf("Install method:   %s\n", installMethod)
		fmt.Printf("Self-update:      %v\n", update.CanSelfUpdate(installMethod))

		// Load and display update config
		configData, err := client.LoadUpdateConfig()
		if err != nil {
			fmt.Printf("Update config:    failed to load: %v\n", err)
			return nil
		}

		if configData == nil {
			fmt.Println("Update config:    not configured (using defaults)")
			return nil
		}

		var config update.UpdateConfig
		jsonData, _ := json.Marshal(configData)
		if err := json.Unmarshal(jsonData, &config); err != nil {
			fmt.Printf("Update config:    failed to parse: %v\n", err)
			return nil
		}

		fmt.Printf("Auto-check:       %v\n", config.AutoCheck)
		fmt.Printf("Check interval:   %d hours\n", config.Interval)
		if !config.LastCheckTime.IsZero() {
			fmt.Printf("Last check:       %s\n", config.LastCheckTime.Format(time.RFC3339))
		}

		return nil
	},
}

// formatChangelog formats the changelog for display
func formatChangelog(changelog string) string {
	// Simple formatting: indent each line
	lines := strings.Split(changelog, "\n")
	var formatted []string
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			formatted = append(formatted, "  "+strings.TrimSpace(line))
		}
	}
	return strings.Join(formatted, "\n")
}

func init() {
	// Add subcommands
	Update.AddCommand(updateCheck)
	Update.AddCommand(updateApply)
	Update.AddCommand(updateConfig)
	Update.AddCommand(updateStatus)

	// Flags for apply command
	updateApply.Flags().BoolVarP(&applyYesFlag, "yes", "y", false, "Skip confirmation prompt")

	// Flags for config command
	configAutoCheck = updateConfig.Flags().Bool("auto-check", false, "Enable automatic update checking")
	updateConfig.Flags().IntVar(&configInterval, "interval", 24, "Hours between automatic checks")
	updateConfig.Flags().BoolVar(&configPrerelease, "prerelease", false, "Include prerelease versions")
}
