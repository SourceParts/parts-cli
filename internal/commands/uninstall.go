package commands

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/SourceParts/parts-cli/internal/client"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/update"
	"github.com/spf13/cobra"
)

var uninstallYesFlag bool

// Uninstall removes all parts CLI data and the binary itself.
var Uninstall = &cobra.Command{
	Use:   "uninstall",
	Short: "Remove the parts CLI and all stored data",
	Long: `Remove the parts CLI binary, stored credentials, cached datasheets,
staged updates, and backup binaries.

For Homebrew installations, use 'brew uninstall parts-cli' instead.

Removes:
  - Stored credentials (keychain entries + ~/.config/parts/)
  - Cached datasheets (~/.cache/parts/)
  - Staged updates (~/.config/parts/staged/)
  - Backup binaries (<binary>.backup.*)
  - The CLI binary itself`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// Detect install method
		method, _ := update.DetectInstallMethod()
		if method == update.InstallHomebrew {
			fmt.Println("Installed via Homebrew. Run:")
			fmt.Println("  brew uninstall parts-cli")
			return nil
		}
		if method == update.InstallApt {
			fmt.Println("Installed via apt. Run:")
			fmt.Println("  sudo apt remove parts-cli")
			return nil
		}
		if method == update.InstallYum {
			fmt.Println("Installed via yum. Run:")
			fmt.Println("  sudo yum remove parts-cli")
			return nil
		}

		// Get binary path
		exePath, err := os.Executable()
		if err != nil {
			return fmt.Errorf("failed to locate binary: %w", err)
		}
		realPath, err := filepath.EvalSymlinks(exePath)
		if err != nil {
			realPath = exePath
		}

		// Build list of things to remove
		home, _ := os.UserHomeDir()
		configDir, _ := os.UserConfigDir()
		if configDir == "" {
			configDir = filepath.Join(home, ".config")
		}

		partsConfig := filepath.Join(configDir, "parts")
		partsCache := filepath.Join(home, ".cache", "parts")

		// Find backup binaries
		backups, _ := update.ListBackups(realPath)

		// Show what will be removed
		fmt.Println("This will remove:")
		fmt.Printf("  Binary:      %s\n", realPath)
		if len(backups) > 0 {
			fmt.Printf("  Backups:     %d backup file(s)\n", len(backups))
		}
		fmt.Println("  Credentials: keychain entries for 'parts-cli'")
		if dirExists(partsConfig) {
			fmt.Printf("  Config:      %s\n", partsConfig)
		}
		if dirExists(partsCache) {
			fmt.Printf("  Cache:       %s\n", partsCache)
		}
		fmt.Println()

		// Confirm
		if !uninstallYesFlag {
			fmt.Printf("Continue? [y/N]: ")
			var response string
			fmt.Scanln(&response)
			if strings.ToLower(strings.TrimSpace(response)) != "y" {
				fmt.Println("Uninstall cancelled.")
				return nil
			}
		}

		var errors []string

		// 1. Remove keychain credentials
		if err := client.DeleteOAuthTokens(); err != nil {
			errors = append(errors, fmt.Sprintf("keychain OAuth tokens: %v", err))
		}
		if err := client.DeleteAPIKey(); err != nil {
			errors = append(errors, fmt.Sprintf("keychain API key: %v", err))
		}

		// 2. Remove config dir (~/.config/parts/)
		if dirExists(partsConfig) {
			if err := os.RemoveAll(partsConfig); err != nil {
				errors = append(errors, fmt.Sprintf("config dir: %v", err))
			}
		}

		// 3. Remove cache dir (~/.cache/parts/)
		if dirExists(partsCache) {
			if err := os.RemoveAll(partsCache); err != nil {
				errors = append(errors, fmt.Sprintf("cache dir: %v", err))
			}
		}

		// 4. Remove backup binaries
		for _, backup := range backups {
			os.Remove(backup)
		}

		// 5. Remove the binary itself (last, since we're running it)
		// On Linux/macOS the running process keeps its fd to the old inode,
		// so removing the file is safe — the process continues until exit.
		if err := os.Remove(realPath); err != nil {
			errors = append(errors, fmt.Sprintf("binary: %v", err))
		}

		if len(errors) > 0 {
			fmt.Println("Uninstalled with warnings:")
			for _, e := range errors {
				fmt.Printf("  - %s\n", e)
			}
		} else {
			fmt.Printf("✓ %s has been uninstalled\n", domain.BinaryName)
		}

		return nil
	},
	Example: domain.BinaryName + ` uninstall
` + domain.BinaryName + ` uninstall --yes`,
}

func init() {
	Uninstall.Flags().BoolVarP(&uninstallYesFlag, "yes", "y", false, "Skip confirmation prompt")
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
