package main

import (
	"fmt"
	"net/http"
	"os"

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

	// Load API key from system keychain
	apiKey, err := client.LoadAPIKey()
	if err != nil && Verbose {
		logger.New(&Verbose).Printf("Warning: Failed to load API key from keychain: %v", err)
	}

	commands.Client = &client.Client{
		API:    &API,
		APIKey: apiKey,
		Logger: logger.New(&Verbose),
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
