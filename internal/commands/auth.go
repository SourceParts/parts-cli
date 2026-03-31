package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/SourceParts/parts-cli/internal/auth"
	"github.com/SourceParts/parts-cli/internal/client"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// Auth is the authentication command group
var Auth = &cobra.Command{
	Use:   "auth",
	Short: "Authenticate with Source Parts API",
	Long: `Authenticate with Source Parts API.

By default, 'auth login' opens your browser for a secure OAuth login (no manual
API key required). To use an API key instead, pass it via --api-key or as a
positional argument.

Credentials are stored securely in your system's keychain:
  - macOS: Keychain
  - Linux: Secret Service (GNOME Keyring, KWallet)
  - Windows: Credential Manager`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
	Example: domain.BinaryName + ` auth login
` + domain.BinaryName + ` auth login --api-key sp_xxxx
` + domain.BinaryName + ` auth status
` + domain.BinaryName + ` auth logout`,
}

var loginAPIKeyFlag string

var authLogin = &cobra.Command{
	Use:   "login [api-key]",
	Short: "Log in to Source Parts",
	Long: `Log in to Source Parts.

Without arguments, opens your browser for an OAuth login (recommended).
Pass an API key via --api-key or as a positional argument to use the
legacy key-based login instead.`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		// Determine if user supplied an API key
		apiKey := loginAPIKeyFlag
		if len(args) > 0 {
			apiKey = args[0]
		}

		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		if apiKey != "" {
			return handleAPIKeyLogin(ctx, apiKey)
		}

		// Browser-based OAuth flow
		tokens, err := auth.Login(ctx, os.Stdout)
		if err != nil {
			return fmt.Errorf("browser login failed: %w", err)
		}

		if err := client.SaveOAuthTokens(tokens); err != nil {
			return fmt.Errorf("failed to save tokens: %w", err)
		}

		Client.SetAPIKey(tokens.AccessToken)

		fmt.Printf("\n✓ Logged in as %s\n", tokens.Email)
		fmt.Printf("Storage: %s\n", client.StorageBackend())
		return nil
	},
	Example: domain.BinaryName + ` auth login
` + domain.BinaryName + ` auth login --api-key sp_xxxx`,
}

func handleAPIKeyLogin(ctx context.Context, apiKey string) error {
	fmt.Println("Validating API key...")
	if err := Client.Auth(ctx, apiKey, os.Stdout); err != nil {
		return fmt.Errorf("failed to validate API key: %w", err)
	}

	if err := client.SaveAPIKey(apiKey); err != nil {
		return err
	}

	Client.SetAPIKey(apiKey)

	fmt.Println("\n✓ API key saved")
	fmt.Printf("Storage: %s\n", client.StorageBackend())
	return nil
}

var authLogout = &cobra.Command{
	Use:   "logout",
	Short: "Log out and remove stored credentials",
	Long:  `Remove all stored credentials (OAuth tokens and API key) from your system's keychain.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := client.DeleteOAuthTokens(); err != nil {
			return err
		}
		if err := client.DeleteAPIKey(); err != nil {
			return err
		}
		Client.SetAPIKey("")
		fmt.Println("Credentials removed")
		fmt.Println("You are now logged out")
		return nil
	},
}

var authStatus = &cobra.Command{
	Use:   "status",
	Short: "Check authentication status",
	Long:  `Show which credentials are stored and whether the client is authenticated.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		storage := client.StorageBackend()

		// PARTS_TOKEN env var takes precedence
		if os.Getenv("PARTS_TOKEN") != "" {
			fmt.Println("Auth method: PARTS_TOKEN (environment variable)")
			fmt.Printf("Storage:     %s\n", storage)
			return nil
		}

		if client.HasOAuthTokens() {
			tokens, err := client.LoadOAuthTokens()
			if err != nil || tokens == nil {
				fmt.Println("OAuth tokens found but could not be loaded")
			} else {
				remaining := time.Until(tokens.ExpiresAt)
				if remaining < 0 {
					fmt.Println("Auth method: OAuth (access token expired)")
				} else {
					fmt.Printf("Auth method: OAuth\n")
				}
				if tokens.Email != "" {
					fmt.Printf("User:        %s\n", tokens.Email)
				}
				fmt.Printf("Expires in:  %s\n", remaining.Round(time.Second))
				fmt.Printf("Storage:     %s\n", storage)
			}
			return nil
		}

		if client.HasAPIKey() {
			fmt.Println("Auth method: API Key")
			fmt.Printf("Storage:     %s\n", storage)
			if Client.IsAuthenticated() {
				fmt.Println("Client is configured and ready")
			}
			return nil
		}

		fmt.Println("Not authenticated")
		fmt.Printf("Run '%s auth login' to authenticate\n", domain.BinaryName)
		fmt.Printf("Or set PARTS_TOKEN environment variable for CI/CD\n")
		return nil
	},
}

var authWhoami = &cobra.Command{
	Use:   "whoami",
	Short: "Show current authenticated user",
	Long:  `Display information about the currently authenticated user.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// Check OAuth tokens first
		if client.HasOAuthTokens() {
			tokens, err := client.LoadOAuthTokens()
			if err == nil && tokens != nil {
				fmt.Printf("User:  %s\n", tokens.Email)
				fmt.Printf("Plan:  %s\n", fetchPlan(tokens.AccessToken))
				return nil
			}
		}

		if !Client.IsAuthenticated() {
			fmt.Printf("Not authenticated. Run '%s auth login' first.\n", domain.BinaryName)
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

	authLogin.Flags().StringVar(&loginAPIKeyFlag, "api-key", "", "API key to use for authentication (skips browser login)")
}

// fetchPlan queries the credits API for the user's plan tier.
// Returns "Trial", "Pro", etc. or "Contact Support" on failure.
func fetchPlan(accessToken string) string {
	req, err := http.NewRequest("GET", "https://"+domain.API+"/v1/credits/balance", nil)
	if err != nil {
		return "Contact Support"
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("User-Agent", domain.BinaryName+"/1.0")

	httpClient := &http.Client{Timeout: 5 * time.Second}
	resp, err := httpClient.Do(req)
	if err != nil {
		return "Contact Support"
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil || resp.StatusCode != 200 {
		return "Contact Support"
	}

	var result struct {
		Success bool `json:"success"`
		Data    struct {
			Tier string `json:"tier"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &result); err != nil || !result.Success {
		return "Contact Support"
	}

	tier := result.Data.Tier
	if tier == "" {
		return "Contact Support"
	}
	return tier
}
