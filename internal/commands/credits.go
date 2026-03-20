package commands

import (
	"os"

	"github.com/spf13/cobra"
)

// Credits is the parent command for credit operations.
var Credits = &cobra.Command{
	Use:   "credits",
	Short: "Manage sourcing credits",
}

var creditsBalance = &cobra.Command{
	Use:   "balance",
	Short: "Show current credit balance",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		jsonOutput, _ := cmd.Flags().GetBool("json")
		return Client.CreditsBalance(ctx, jsonOutput, os.Stdout)
	},
}

func init() {
	creditsBalance.Flags().Bool("json", false, "Output raw JSON")
	Credits.AddCommand(creditsBalance)
}
