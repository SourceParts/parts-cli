package commands

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// =============================================================================
// QuarterMaster Commands
// =============================================================================

// Q is the smart query command -- auto-detects what the input is
var Q = &cobra.Command{
	Use:   "q <input>",
	Short: "Smart query -- search, URL ingest, SMD codes, and more",
	Long: `QuarterMaster smart query endpoint. Automatically detects what your
input is and dispatches accordingly:

  - Part search:     parts q "STM32F4"
  - URL ingest:      parts q "https://lcsc.com/product/C12345.html"
  - SMD code:        parts q "103"
  - Color bands:     parts q "brown black red gold"
  - GitHub repo:     parts q "https://github.com/user/repo"
  - Special:         parts q help

Unlike 'parts search' which only searches parts, 'parts q' figures out
what you mean and routes to the right handler.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` q "STM32F4"
` + domain.BinaryName + ` q "https://lcsc.com/product/C12345.html"
` + domain.BinaryName + ` q "103"
` + domain.BinaryName + ` q "brown black red gold"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		queryType, _ := cmd.Flags().GetString("type")
		return Client.Q(ctx, args[0], queryType, os.Stdout)
	},
}

// History is the search history command group
var History = &cobra.Command{
	Use:   "history",
	Short: "View and manage search history",
	Long:  `View recent searches and manage your search history.`,
	Example: domain.BinaryName + ` history
` + domain.BinaryName + ` history --limit 20
` + domain.BinaryName + ` history clear`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		limit, _ := cmd.Flags().GetInt("limit")
		return Client.QHistory(ctx, limit, os.Stdout)
	},
}

var historyClear = &cobra.Command{
	Use:   "clear",
	Short: "Clear search history",
	Long:  `Remove all entries from your search history.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.QHistoryClear(ctx, os.Stdout)
	},
}

// SMD is the SMD resistor code tool
var SMD = &cobra.Command{
	Use:   "smd <code>",
	Short: "Convert SMD resistor code to value",
	Long: `Convert an SMD resistor marking code to its resistance value.

Supports 3-digit, 4-digit, EIA-96, and R-notation formats:
  - 3-digit: 103 = 10 kΩ
  - 4-digit: 4702 = 47 kΩ
  - EIA-96:  01C = 100 Ω
  - R-notation: 4R7 = 4.7 Ω`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` smd 103
` + domain.BinaryName + ` smd 4702
` + domain.BinaryName + ` smd 4R7`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.QSMD(ctx, args[0], os.Stdout)
	},
}

// Resistor is the resistor color band tool
var Resistor = &cobra.Command{
	Use:   "resistor <colors>",
	Short: "Calculate resistance from color bands",
	Long: `Calculate resistance and tolerance from resistor color bands.

Provide 3-6 space-separated color names. Common colors:
  black, brown, red, orange, yellow, green, blue,
  violet, grey/gray, white, gold, silver`,
	Args: cobra.MinimumNArgs(1),
	Example: domain.BinaryName + ` resistor "brown black red gold"
` + domain.BinaryName + ` resistor brown black red gold`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		// Join all args into a single bands string (supports both quoted and unquoted)
		bands := strings.Join(args, " ")
		return Client.QResistorColors(ctx, bands, os.Stdout)
	},
}

func init() {
	// Q command flags
	Q.Flags().StringP("type", "t", "process", "Query type: process, search")

	// History command flags and subcommands
	History.Flags().IntP("limit", "n", 10, "Number of history entries to show")
	History.AddCommand(historyClear)

	// Print a hint when using 'parts resistor' without args
	Resistor.SetUsageTemplate(fmt.Sprintf(`Usage:
  %s resistor <color1> <color2> <color3> [color4] [color5] [color6]

%s`, domain.BinaryName, Resistor.UsageString()))
}
