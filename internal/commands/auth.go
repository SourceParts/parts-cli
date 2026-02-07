package commands

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/SourceParts/parts-cli/internal/client"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// Auth is the authentication command group
var Auth = &cobra.Command{
	Use:   "auth",
	Short: "Authenticate with Source Parts API",
	Long: `Authenticate with Source Parts API using an API key.

The API key is stored securely in your system's keychain:
  - macOS: Keychain
  - Linux: Secret Service (GNOME Keyring, KWallet)
  - Windows: Credential Manager

To get an API key, visit: https://source.parts/settings/api-keys`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
	Example: domain.BinaryName + ` auth login
` + domain.BinaryName + ` auth status
` + domain.BinaryName + ` auth logout`,
}

var authLogin = &cobra.Command{
	Use:   "login [api-key]",
	Short: "Log in with an API key",
	Long: `Store your API key for authenticated requests.

You can provide the API key as an argument or enter it interactively.
The key is stored securely in your system's keychain.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		var apiKey string

		if len(args) == 1 {
			apiKey = args[0]
		} else {
			fmt.Print("Enter your API key: ")
			reader := bufio.NewReader(os.Stdin)
			input, err := reader.ReadString('\n')
			if err != nil {
				return fmt.Errorf("failed to read input: %w", err)
			}
			apiKey = strings.TrimSpace(input)
		}

		if apiKey == "" {
			return fmt.Errorf("API key cannot be empty")
		}

		fmt.Println("Validating API key...")
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		if err := Client.Auth(ctx, apiKey, os.Stdout); err != nil {
			return fmt.Errorf("failed to validate API key: %w", err)
		}

		if err := client.SaveAPIKey(apiKey); err != nil {
			return err
		}

		Client.SetAPIKey(apiKey)

		fmt.Println("\nAPI key saved to system keychain")
		fmt.Println("You are now authenticated with Source Parts API")
		return nil
	},
	Example: domain.BinaryName + ` auth login sk_live_xxxx`,
}

var authLogout = &cobra.Command{
	Use:   "logout",
	Short: "Log out and remove stored API key",
	Long:  `Remove the stored API key from your system's keychain.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := client.DeleteAPIKey(); err != nil {
			return err
		}

		Client.SetAPIKey("")

		fmt.Println("API key removed from system keychain")
		fmt.Println("You are now logged out")
		return nil
	},
}

var authStatus = &cobra.Command{
	Use:   "status",
	Short: "Check authentication status",
	Long:  `Check if you are currently authenticated with the Source Parts API.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if client.HasAPIKey() {
			fmt.Println("Authenticated")
			fmt.Println("API key is stored in system keychain")
			if Client.IsAuthenticated() {
				fmt.Println("Client is configured with API key")
			}
		} else {
			fmt.Println("Not authenticated")
			fmt.Println("Run 'parts auth login' to authenticate")
		}
		return nil
	},
}

var authWhoami = &cobra.Command{
	Use:   "whoami",
	Short: "Show current authenticated user",
	Long:  `Display information about the currently authenticated user.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if !Client.IsAuthenticated() {
			fmt.Println("Not authenticated. Run 'parts auth login' first.")
			return nil
		}

		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		if err := Client.Auth(ctx, Client.GetAPIKey(), os.Stdout); err != nil {
			return fmt.Errorf("failed to get user info: %w", err)
		}

		return nil
	},
}

func init() {
	Auth.AddCommand(authLogin)
	Auth.AddCommand(authLogout)
	Auth.AddCommand(authStatus)
	Auth.AddCommand(authWhoami)
}
