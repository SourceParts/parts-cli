package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/SourceParts/parts-cli/internal/auth"
	"github.com/SourceParts/parts-cli/internal/client"
	"github.com/SourceParts/parts-cli/internal/commands"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/logger"
	"github.com/spf13/cobra"
)

var (
	Verbose            = false
	API                = domain.API
	Endpoint_Add       = domain.Endpoint_Add
	Endpoint_Search    = domain.Endpoint_Search
	Endpoint_Datasheet = domain.Endpoint_Datasheet
	Endpoint_Marking   = domain.Endpoint_Marking
)

var rootCmd = &cobra.Command{
	Use:   domain.BinaryName,
	Short: domain.BinaryName + " - Source Parts CLI (https://source.parts)",
	Long: `parts is the official command-line interface for Source Parts.

Source Parts is an Electronic Component Intelligence Platform that helps
hardware engineers find, manage, and procure electronic components.

Get started:
  parts auth login     Authenticate with your API key
  parts search <query> Search for components
  parts --help         Show all available commands

Documentation: https://source.parts/docs/cli`,
	Run: func(cmd *cobra.Command, args []string) {
		if err := cmd.Help(); err != nil {
			_, _ = fmt.Fprint(os.Stderr, err.Error())
		}
	},
	Version: domain.Version,
}

func main() {
	rootCmd.PersistentFlags().BoolVarP(&Verbose, "verbose", "v", false, "verbose output")

	// Add all commands
	rootCmd.AddCommand(
		// Authentication
		commands.Auth,
		// Part operations
		commands.Add,
		commands.Search,
		commands.Datasheet,
		commands.Marking,
		commands.Gather,
		// BOM operations
		commands.BOM,
		// Project operations
		commands.Project,
		// Manufacturing
		commands.DFM,
		commands.Fabricate,
		commands.AOI,
		commands.QC,
		commands.Publish,
		// QuarterMaster (smart query)
		commands.Q,
		commands.History,
		commands.SMD,
		commands.Resistor,
		// Inventory & Supply Chain
		commands.Inventory,
		commands.Cart,
		commands.Buy,
		commands.RFQ,
		commands.Wishlist,
		commands.Tracker,
		commands.Box,
		// Cost Management
		commands.Balance,
		commands.COGs,
		commands.Expense,
		// Workflow
		commands.Note,
		commands.Todo,
		commands.Report,
		// Local operations
		commands.Init,
		commands.Log,
		commands.Status,
		commands.Clean,
		commands.Scan,
		commands.Label,
		commands.Detect,
		// Documentation
		commands.Guide,
		commands.Docs,
		// GitHub Actions integration
		commands.Github,
		// Version Control
		commands.Pull,
		commands.Push,
		commands.Tag,
		commands.Release,
		commands.Test,
	)

	// Resolve credentials: OAuth tokens take priority over API keys.
	var activeKey string
	log := logger.New(&Verbose)

	if client.HasOAuthTokens() {
		tokens, err := client.LoadOAuthTokens()
		if err == nil && tokens != nil {
			// Proactively refresh if within 60 seconds of expiry.
			if time.Until(tokens.ExpiresAt) < 60*time.Second && tokens.RefreshToken != "" {
				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
				if refreshed, err := auth.Refresh(ctx, tokens.RefreshToken); err == nil {
					_ = client.SaveOAuthTokens(refreshed)
					tokens = refreshed
				} else if Verbose {
					log.Printf("Warning: token refresh failed: %v", err)
				}
				cancel()
			}
			activeKey = tokens.AccessToken
		} else if Verbose {
			log.Printf("Warning: failed to load OAuth tokens: %v", err)
		}
	}

	// Fall back to stored API key if no OAuth tokens available.
	if activeKey == "" {
		apiKey, err := client.LoadAPIKey()
		if err != nil && Verbose {
			log.Printf("Warning: Failed to load API key from keychain: %v", err)
		}
		activeKey = apiKey
	}

	commands.Client = &client.Client{
		API:    &API,
		APIKey: activeKey,
		Logger: log,
		Client: http.DefaultClient,

		Endpoint_Add:       &Endpoint_Add,
		Endpoint_Search:    &Endpoint_Search,
		Endpoint_Datasheet: &Endpoint_Datasheet,
		Endpoint_Marking:   &Endpoint_Marking,
	}

	if err := rootCmd.Execute(); err != nil {
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
