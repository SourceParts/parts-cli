package commands

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/spf13/cobra"
)

// =============================================================================
// EDA Parent Command
// =============================================================================

var EDA = &cobra.Command{
	Use:   "eda",
	Short: "EDA design checks and file conversion",
	Long: `Run electrical and design rule checks, and convert between EDA formats.

Subcommands:
  erc       Run Electrical Rules Check on a KiCad schematic
  drc       Run Design Rules Check on a KiCad PCB
  import    Convert foreign EDA files to KiCad format`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// =============================================================================
// ERC — Electrical Rules Check
// =============================================================================

var edaERC = &cobra.Command{
	Use:   "erc <file.kicad_sch>",
	Short: "Run Electrical Rules Check on a KiCad schematic",
	Long: `Upload a .kicad_sch file and run KiCad's Electrical Rules Check.
Returns a JSON report with violations grouped by severity.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda erc power.kicad_sch`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		schFile := args[0]
		if _, err := os.Stat(schFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", schFile)
		}
		if !strings.HasSuffix(strings.ToLower(schFile), ".kicad_sch") {
			return fmt.Errorf("expected .kicad_sch file, got: %s", filepath.Base(schFile))
		}

		severity, _ := cmd.Flags().GetString("severity")
		rulesFile, _ := cmd.Flags().GetString("rules")
		jsonOutput, _ := cmd.Flags().GetBool("json")

		opts := types.ERCOptions{
			Severity:  severity,
			RulesFile: rulesFile,
		}

		var buf bytes.Buffer
		if err := Client.ERC(ctx, schFile, opts, &buf); err != nil {
			return err
		}

		if jsonOutput {
			os.Stdout.Write(buf.Bytes())
			fmt.Println()
			return nil
		}

		printERCReport(buf.Bytes())
		return nil
	},
}

// =============================================================================
// DRC — Design Rules Check
// =============================================================================

var edaDRC = &cobra.Command{
	Use:   "drc <file.kicad_pcb>",
	Short: "Run Design Rules Check on a KiCad PCB",
	Long: `Upload a .kicad_pcb file and run KiCad's Design Rules Check.
Returns a JSON report with violations grouped by severity.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda drc board.kicad_pcb`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		pcbFile := args[0]
		if _, err := os.Stat(pcbFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", pcbFile)
		}
		if !strings.HasSuffix(strings.ToLower(pcbFile), ".kicad_pcb") {
			return fmt.Errorf("expected .kicad_pcb file, got: %s", filepath.Base(pcbFile))
		}

		severity, _ := cmd.Flags().GetString("severity")
		rulesFile, _ := cmd.Flags().GetString("rules")
		jsonOutput, _ := cmd.Flags().GetBool("json")

		opts := types.DRCOptions{
			Severity:  severity,
			RulesFile: rulesFile,
		}

		var buf bytes.Buffer
		if err := Client.DRC(ctx, pcbFile, opts, &buf); err != nil {
			return err
		}

		if jsonOutput {
			os.Stdout.Write(buf.Bytes())
			fmt.Println()
			return nil
		}

		printDRCReport(buf.Bytes())
		return nil
	},
}

// =============================================================================
// Import — Foreign EDA file conversion
// =============================================================================

var edaImport = &cobra.Command{
	Use:   "import",
	Short: "Convert foreign EDA files to KiCad format",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var edaImportAltium = &cobra.Command{
	Use:   "altium <file.SchDoc>",
	Short: "Convert Altium .SchDoc to KiCad .kicad_sch",
	Long: `Upload an Altium Designer .SchDoc schematic file and convert it to
KiCad .kicad_sch format. The converted file is saved alongside the
original or to the path specified by --output.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda import altium TopSheet.SchDoc`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		schDoc := args[0]
		if _, err := os.Stat(schDoc); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", schDoc)
		}
		if !strings.HasSuffix(strings.ToLower(schDoc), ".schdoc") {
			return fmt.Errorf("expected .SchDoc file, got: %s", filepath.Base(schDoc))
		}

		output, _ := cmd.Flags().GetString("output")
		if output == "" {
			base := strings.TrimSuffix(filepath.Base(schDoc), filepath.Ext(schDoc))
			output = filepath.Join(filepath.Dir(schDoc), base+".kicad_sch")
		}

		return Client.ImportAltium(ctx, schDoc, output, os.Stdout)
	},
}

// =============================================================================
// Output Formatting
// =============================================================================

func printERCReport(data []byte) {
	var resp struct {
		Success      bool            `json:"success"`
		KicadVersion string          `json:"kicad_version"`
		Report       json.RawMessage `json:"report"`
	}
	if err := json.Unmarshal(data, &resp); err != nil {
		os.Stdout.Write(data)
		fmt.Println()
		return
	}

	var report struct {
		Violations []struct {
			Severity    string `json:"severity"`
			Description string `json:"description"`
			Items       []struct {
				Description string `json:"description"`
				Pos         struct {
					X float64 `json:"x"`
					Y float64 `json:"y"`
				} `json:"pos"`
			} `json:"items"`
		} `json:"violations"`
	}
	if err := json.Unmarshal(resp.Report, &report); err != nil {
		// Fallback: pretty-print raw
		var pretty bytes.Buffer
		json.Indent(&pretty, data, "", "  ")
		os.Stdout.Write(pretty.Bytes())
		fmt.Println()
		return
	}

	errors, warnings := 0, 0
	for _, v := range report.Violations {
		switch v.Severity {
		case "error":
			errors++
		case "warning":
			warnings++
		}
	}

	fmt.Printf("ERC Report (KiCad %s)\n\n", resp.KicadVersion)

	if len(report.Violations) == 0 {
		fmt.Println("  No violations found.")
		return
	}

	fmt.Printf("  %d error(s), %d warning(s)\n\n", errors, warnings)

	for _, v := range report.Violations {
		marker := "W"
		if v.Severity == "error" {
			marker = "E"
		}
		fmt.Printf("  [%s] %s\n", marker, v.Description)
		for _, item := range v.Items {
			fmt.Printf("      %s (%.1f, %.1f)\n", item.Description, item.Pos.X, item.Pos.Y)
		}
	}
}

func printDRCReport(data []byte) {
	var resp struct {
		Success      bool            `json:"success"`
		KicadVersion string          `json:"kicad_version"`
		Report       json.RawMessage `json:"report"`
	}
	if err := json.Unmarshal(data, &resp); err != nil {
		os.Stdout.Write(data)
		fmt.Println()
		return
	}

	var report struct {
		Violations []struct {
			Severity    string `json:"severity"`
			Description string `json:"description"`
			Items       []struct {
				Description string `json:"description"`
				Pos         struct {
					X float64 `json:"x"`
					Y float64 `json:"y"`
				} `json:"pos"`
			} `json:"items"`
		} `json:"violations"`
		UnconnectedItems []struct {
			Description string `json:"description"`
		} `json:"unconnected_items"`
	}
	if err := json.Unmarshal(resp.Report, &report); err != nil {
		var pretty bytes.Buffer
		json.Indent(&pretty, data, "", "  ")
		os.Stdout.Write(pretty.Bytes())
		fmt.Println()
		return
	}

	errors, warnings := 0, 0
	for _, v := range report.Violations {
		switch v.Severity {
		case "error":
			errors++
		case "warning":
			warnings++
		}
	}

	fmt.Printf("DRC Report (KiCad %s)\n\n", resp.KicadVersion)

	if len(report.Violations) == 0 && len(report.UnconnectedItems) == 0 {
		fmt.Println("  No violations found.")
		return
	}

	fmt.Printf("  %d error(s), %d warning(s), %d unconnected\n\n", errors, warnings, len(report.UnconnectedItems))

	for _, v := range report.Violations {
		marker := "W"
		if v.Severity == "error" {
			marker = "E"
		}
		fmt.Printf("  [%s] %s\n", marker, v.Description)
		for _, item := range v.Items {
			fmt.Printf("      %s (%.1f, %.1f)\n", item.Description, item.Pos.X, item.Pos.Y)
		}
	}

	for _, u := range report.UnconnectedItems {
		fmt.Printf("  [U] %s\n", u.Description)
	}
}

// =============================================================================
// init — Register subcommands and flags
// =============================================================================

func init() {
	// ERC flags
	edaERC.Flags().StringP("severity", "s", "all", "Filter severity: all, error, warning, exclusion")
	edaERC.Flags().String("rules", "", "Custom ERC rules file")
	edaERC.Flags().BoolP("json", "j", false, "Output raw JSON")

	// DRC flags
	edaDRC.Flags().StringP("severity", "s", "all", "Filter severity: all, error, warning, exclusion")
	edaDRC.Flags().String("rules", "", "Custom DRC rules file (.kicad_dru)")
	edaDRC.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Import altium flags
	edaImportAltium.Flags().StringP("output", "o", "", "Output .kicad_sch path (default: alongside input)")

	// Wire up subcommands
	edaImport.AddCommand(edaImportAltium)

	EDA.AddCommand(edaERC)
	EDA.AddCommand(edaDRC)
	EDA.AddCommand(edaImport)
}
