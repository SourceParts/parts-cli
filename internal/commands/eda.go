package commands

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
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
	Short: "Convert Altium .SchDoc and scaffold a Parts Studio project",
	Long: `Upload an Altium Designer .SchDoc schematic file, convert it to KiCad
format, and scaffold a complete Parts Studio project directory.

The project directory includes the converted schematic, a minimal KiCad
project file, Parts Studio configuration, and the standard directory
structure (ECO, BOM, PCB, Datasheets, etc.).

If --output is set to a .kicad_sch path, falls back to legacy mode:
just convert and save the file without scaffolding.`,
	Args: cobra.ExactArgs(1),
	Example: `  ` + domain.BinaryName + ` eda import altium TopSheet.SchDoc
  ` + domain.BinaryName + ` eda import altium TopSheet.SchDoc --name "My Board" --revision DVT1
  ` + domain.BinaryName + ` eda import altium TopSheet.SchDoc -o output.kicad_sch`,
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
		name, _ := cmd.Flags().GetString("name")
		revision, _ := cmd.Flags().GetString("revision")
		noGit, _ := cmd.Flags().GetBool("no-git")

		// Legacy mode: if --output ends in .kicad_sch, just convert and save
		if strings.HasSuffix(strings.ToLower(output), ".kicad_sch") {
			return Client.ImportAltium(ctx, schDoc, output, os.Stdout)
		}

		// Derive project name from filename if not provided
		if name == "" {
			name = strings.TrimSuffix(filepath.Base(schDoc), filepath.Ext(schDoc))
		}

		// Convert
		schBytes, err := Client.ImportAltiumBytes(ctx, schDoc)
		if err != nil {
			return err
		}

		// Scaffold
		dir := name
		return scaffoldProject(dir, revision, schBytes, name, noGit, os.Stdout)
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
// Project Scaffolding
// =============================================================================

func scaffoldProject(dir, revision string, schBytes []byte, name string, noGit bool, w io.Writer) error {
	if _, err := os.Stat(dir); err == nil {
		return fmt.Errorf("directory already exists: %s", dir)
	}

	absPath, err := filepath.Abs(dir)
	if err != nil {
		return fmt.Errorf("resolving absolute path: %w", err)
	}

	// Create directory tree
	dirs := []string{
		".parts",
		"ECO",
		filepath.Join("BOM", revision),
		filepath.Join("PCB", revision),
		"Datasheets",
		"IQC",
		"DFT",
		"DRC",
		"ERC",
		"Reports",
	}
	for _, d := range dirs {
		if err := os.MkdirAll(filepath.Join(dir, d), 0755); err != nil {
			return fmt.Errorf("creating directory %s: %w", d, err)
		}
	}

	// Write converted schematic
	schPath := filepath.Join(dir, "PCB", revision, name+".kicad_sch")
	if err := os.WriteFile(schPath, schBytes, 0644); err != nil {
		return fmt.Errorf("writing schematic: %w", err)
	}

	// Write minimal KiCad project file
	if err := writeMinimalKicadPro(filepath.Join(dir, "PCB", revision), name); err != nil {
		return err
	}

	timestamp := time.Now().UTC().Format(time.RFC3339)

	// Write .parts/config.yaml
	if err := writeProjectConfig(filepath.Join(dir, ".parts"), name, timestamp); err != nil {
		return err
	}

	// Write PARTS.md
	if err := writePartsMD(dir, name, revision); err != nil {
		return err
	}

	// Update ~/.parts/config.yml
	if err := writeUserConfig(name, absPath, revision); err != nil {
		return err
	}

	// Git init
	if !noGit {
		gitCmd := exec.Command("git", "init", dir)
		if out, err := gitCmd.CombinedOutput(); err != nil {
			fmt.Fprintf(w, "Warning: git init failed: %s\n", strings.TrimSpace(string(out)))
		}
	}

	// Summary
	fmt.Fprintf(w, "Created project: %s\n", absPath)
	fmt.Fprintf(w, "  Schematic: PCB/%s/%s.kicad_sch\n", revision, name)
	fmt.Fprintf(w, "  Revision:  %s\n", revision)
	fmt.Fprintf(w, "  Config:    .parts/config.yaml\n")
	if !noGit {
		fmt.Fprintf(w, "  Git:       initialized\n")
	}
	return nil
}

func writeProjectConfig(partsDir, name, timestamp string) error {
	content := fmt.Sprintf(`version: "1.0"

project:
  name: %q
  type: "pcb"
  created_at: %q

fabrication:
  board_name: %q
  prefix: %q
`, name, timestamp, name, name)

	return os.WriteFile(filepath.Join(partsDir, "config.yaml"), []byte(content), 0644)
}

func writeUserConfig(name, absPath, revision string) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("resolving home directory: %w", err)
	}

	partsHome := filepath.Join(homeDir, ".parts")
	if err := os.MkdirAll(partsHome, 0755); err != nil {
		return fmt.Errorf("creating ~/.parts: %w", err)
	}

	content := fmt.Sprintf(`project:
  name: %q
  path: %q
  revision: %q

directories:
  eco: "ECO"
  bom: "BOM"
  pcb: "PCB"
  iqc: "IQC"
  datasheets: "Datasheets"
  assembly: "PCB/%s/pdf_output"
  fab_release: "PCB/%s/fab_release"

api:
  url: "https://api.source.parts"
`, name, absPath, revision, revision, revision)

	return os.WriteFile(filepath.Join(partsHome, "config.yml"), []byte(content), 0644)
}

func writePartsMD(dir, name, revision string) error {
	content := fmt.Sprintf(`# PARTS.md

This file provides guidance to PARTS CLI when working with this repository.

## Project Overview

This is a **PCB hardware design repository** for **%s**.

## Repository Structure

- **PCB/%s/** — KiCad schematic and project files
- **BOM/%s/** — Bill of Materials
- **ECO/** — Engineering Change Orders
- **Datasheets/** — Component datasheets
- **IQC/** — Incoming Quality Control
- **DFT/** — Design for Test
- **DRC/** — Design Rule Check reports
- **ERC/** — Electrical Rule Check reports
- **Reports/** — Analysis and review reports
`, name, revision, revision)

	return os.WriteFile(filepath.Join(dir, "PARTS.md"), []byte(content), 0644)
}

func writeMinimalKicadPro(dir, name string) error {
	content := `{
  "meta": {
    "filename": "` + name + `.kicad_pro",
    "version": 1
  },
  "schematic": {
    "drawing": {},
    "meta": {
      "version": 1
    }
  }
}
`
	return os.WriteFile(filepath.Join(dir, name+".kicad_pro"), []byte(content), 0644)
}

// =============================================================================
// DXF — Board outline info
// =============================================================================

var edaDXF = &cobra.Command{
	Use:   "dxf <file.dxf>",
	Short: "Parse DXF board outline and report dimensions",
	Long: `Read a DXF file (board outline / mechanical drawing) and report
bounding box dimensions, entity count, and layer information.

Supports LINE, ARC, CIRCLE, LWPOLYLINE, and POLYLINE entities.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda dxf board_outline.dxf`,
	RunE: func(cmd *cobra.Command, args []string) error {
		dxfFile := args[0]
		data, err := os.ReadFile(dxfFile)
		if err != nil {
			return fmt.Errorf("cannot read file: %w", err)
		}

		result := parseDXF(string(data), filepath.Base(dxfFile))
		jsonOutput, _ := cmd.Flags().GetBool("json")

		if jsonOutput {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		// Human-readable output
		fmt.Printf("File:       %s\n", result.File)
		fmt.Printf("Size:       %.2f x %.2f mm\n", result.Width, result.Height)
		fmt.Printf("Bounds X:   [%.2f, %.2f]\n", result.MinX, result.MaxX)
		fmt.Printf("Bounds Y:   [%.2f, %.2f]\n", result.MinY, result.MaxY)
		fmt.Printf("Entities:   %d\n", result.Entities)
		if len(result.Layers) > 0 {
			fmt.Printf("Layers:     %s\n", strings.Join(result.Layers, ", "))
		}
		return nil
	},
}

type dxfResult struct {
	File     string   `json:"file"`
	Width    float64  `json:"width"`
	Height   float64  `json:"height"`
	MinX     float64  `json:"min_x"`
	MaxX     float64  `json:"max_x"`
	MinY     float64  `json:"min_y"`
	MaxY     float64  `json:"max_y"`
	Entities int      `json:"entities"`
	Layers   []string `json:"layers"`
}

func parseDXF(content, filename string) dxfResult {
	lines := strings.Split(content, "\n")
	var xs, ys []float64
	layerSet := make(map[string]bool)
	entities := 0

	geometryTypes := map[string]bool{
		"LINE": true, "ARC": true, "CIRCLE": true,
		"LWPOLYLINE": true, "POLYLINE": true, "ELLIPSE": true,
	}

	i := 0
	for i < len(lines) {
		code := strings.TrimSpace(lines[i])
		if geometryTypes[code] {
			entities++
			// Scan entity for coordinates and layer
			j := i + 1
			for j < len(lines) {
				gc := strings.TrimSpace(lines[j])
				if gc == "0" {
					break // next entity
				}
				if j+1 < len(lines) {
					val := strings.TrimSpace(lines[j+1])
					switch gc {
					case "8": // layer name
						layerSet[val] = true
					case "10", "11": // X coordinates
						if f, err := strconv.ParseFloat(val, 64); err == nil {
							xs = append(xs, f)
						}
					case "20", "21": // Y coordinates
						if f, err := strconv.ParseFloat(val, 64); err == nil {
							ys = append(ys, f)
						}
					}
				}
				j++
			}
			i = j
		} else {
			i++
		}
	}

	result := dxfResult{File: filename, Entities: entities}

	if len(xs) > 0 && len(ys) > 0 {
		result.MinX = xs[0]
		result.MaxX = xs[0]
		for _, x := range xs {
			if x < result.MinX {
				result.MinX = x
			}
			if x > result.MaxX {
				result.MaxX = x
			}
		}
		result.MinY = ys[0]
		result.MaxY = ys[0]
		for _, y := range ys {
			if y < result.MinY {
				result.MinY = y
			}
			if y > result.MaxY {
				result.MaxY = y
			}
		}
		result.Width = result.MaxX - result.MinX
		result.Height = result.MaxY - result.MinY
	}

	for layer := range layerSet {
		result.Layers = append(result.Layers, layer)
	}

	return result
}

// =============================================================================
// init — Register subcommands and flags
// =============================================================================

// =============================================================================
// Schematic Render — export schematic as PDF via API
// =============================================================================

var edaRender = &cobra.Command{
	Use:   "render <file.kicad_sch>",
	Short: "Render a schematic as PDF",
	Long:  `Upload a .kicad_sch file and render it as PDF via kicad-cli on the server.`,
	Args:  cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda render power.kicad_sch -o schematic.pdf`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		schFile := args[0]
		if _, err := os.Stat(schFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", schFile)
		}

		output, _ := cmd.Flags().GetString("output")
		if output == "" {
			base := strings.TrimSuffix(filepath.Base(schFile), filepath.Ext(schFile))
			output = base + ".pdf"
		}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.Endpoint_SchematicRender, schFile, nil, nil, &buf); err != nil {
			return err
		}

		var result struct {
			Status string `json:"status"`
			Data   struct {
				PDFBase64 string `json:"pdf_base64"`
				PDFSize   int    `json:"pdf_size_bytes"`
			} `json:"data"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}
		if result.Error != "" {
			return fmt.Errorf("render failed: %s", result.Error)
		}

		pdfData, err := base64.StdEncoding.DecodeString(result.Data.PDFBase64)
		if err != nil {
			return fmt.Errorf("failed to decode PDF: %w", err)
		}
		if err := os.WriteFile(output, pdfData, 0644); err != nil {
			return fmt.Errorf("failed to write PDF: %w", err)
		}

		fmt.Printf("Rendered schematic: %s (%d bytes)\n", output, len(pdfData))
		return nil
	},
}

// =============================================================================
// Schematic Remove — remove a component from a schematic
// =============================================================================

var edaSchRemove = &cobra.Command{
	Use:   "remove <file.kicad_sch> <ref>",
	Short: "Remove a component from a schematic",
	Long:  `Remove a symbol by reference designator. Returns a unified diff.`,
	Args:  cobra.ExactArgs(2),
	Example: domain.BinaryName + ` eda remove audio.kicad_sch R47`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		schFile, ref := args[0], args[1]
		if _, err := os.Stat(schFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", schFile)
		}

		params := fmt.Sprintf(`{"ref":"%s"}`, ref)
		fields := map[string]string{"params": params}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.Endpoint_SchematicRemove, schFile, fields, nil, &buf); err != nil {
			return err
		}

		var result struct {
			Status string `json:"status"`
			Data   struct {
				Diff      string `json:"diff"`
				DiffLines int    `json:"diff_lines"`
				Modified  string `json:"modified_content"`
			} `json:"data"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}
		if result.Error != "" {
			return fmt.Errorf("remove failed: %s", result.Error)
		}

		apply, _ := cmd.Flags().GetBool("apply")
		fmt.Printf("Removed %s (%d diff lines)\n", ref, result.Data.DiffLines)
		fmt.Println(result.Data.Diff)

		if apply && result.Data.Modified != "" {
			if err := os.WriteFile(schFile, []byte(result.Data.Modified), 0644); err != nil {
				return fmt.Errorf("failed to apply changes: %w", err)
			}
			fmt.Printf("Applied changes to %s\n", schFile)
		}

		return nil
	},
}

// =============================================================================
// Schematic Annotate — update a component value
// =============================================================================

var edaSchAnnotate = &cobra.Command{
	Use:   "annotate <file.kicad_sch> <ref> <property> <new_value>",
	Short: "Update a component property value",
	Long:  `Change a property (e.g., Value, Footprint) on a symbol.`,
	Args:  cobra.ExactArgs(4),
	Example: domain.BinaryName + ` eda annotate audio.kicad_sch R47 Value 0R`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		schFile, ref, prop, newVal := args[0], args[1], args[2], args[3]
		if _, err := os.Stat(schFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", schFile)
		}

		params := fmt.Sprintf(`{"ref":"%s","property":"%s","new_value":"%s"}`, ref, prop, newVal)
		fields := map[string]string{"params": params}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.Endpoint_SchematicAnnotate, schFile, fields, nil, &buf); err != nil {
			return err
		}

		var result struct {
			Status string `json:"status"`
			Data   struct {
				Diff      string `json:"diff"`
				DiffLines int    `json:"diff_lines"`
				Modified  string `json:"modified_content"`
			} `json:"data"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}
		if result.Error != "" {
			return fmt.Errorf("annotate failed: %s", result.Error)
		}

		apply, _ := cmd.Flags().GetBool("apply")
		fmt.Printf("Updated %s.%s = %s (%d diff lines)\n", ref, prop, newVal, result.Data.DiffLines)
		fmt.Println(result.Data.Diff)

		if apply && result.Data.Modified != "" {
			if err := os.WriteFile(schFile, []byte(result.Data.Modified), 0644); err != nil {
				return fmt.Errorf("failed to apply changes: %w", err)
			}
			fmt.Printf("Applied changes to %s\n", schFile)
		}

		return nil
	},
}

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
	edaImportAltium.Flags().StringP("output", "o", "", "Output .kicad_sch path (legacy: just convert and save)")
	edaImportAltium.Flags().String("name", "", "Project name (default: derived from filename)")
	edaImportAltium.Flags().String("revision", "EVT1", "Revision label for directory structure")
	edaImportAltium.Flags().Bool("no-git", false, "Skip git init")

	edaDXF.Flags().Bool("json", false, "Output as JSON")

	// Wire up subcommands
	edaImport.AddCommand(edaImportAltium)

	// Render flags
	edaRender.Flags().StringP("output", "o", "", "Output PDF path (default: <basename>.pdf)")

	// Sch-remove flags
	edaSchRemove.Flags().Bool("apply", false, "Apply changes to the file (default: show diff only)")

	// Sch-annotate flags
	edaSchAnnotate.Flags().Bool("apply", false, "Apply changes to the file (default: show diff only)")

	EDA.AddCommand(edaERC)
	EDA.AddCommand(edaDRC)
	EDA.AddCommand(edaImport)
	EDA.AddCommand(edaDXF)
	EDA.AddCommand(edaCtrl)
	edaSVG.Flags().StringP("output", "o", "", "Output SVG path")
	EDA.AddCommand(edaSVG)
	EDA.AddCommand(edaRender)
	EDA.AddCommand(edaSchRemove)
	EDA.AddCommand(edaSchAnnotate)
}

// =============================================================================
// Schematic SVG Export
// =============================================================================

var edaSVG = &cobra.Command{
	Use:   "svg <file.kicad_sch>",
	Short: "Export a schematic as SVG",
	Long:  `Upload a .kicad_sch file and export it as SVG via kicad-cli on the server.`,
	Args:  cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda svg power.kicad_sch -o schematic.svg`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		schFile := args[0]
		if _, err := os.Stat(schFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", schFile)
		}

		output, _ := cmd.Flags().GetString("output")
		if output == "" {
			base := strings.TrimSuffix(filepath.Base(schFile), filepath.Ext(schFile))
			output = base + ".svg"
		}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.V1Prefix+"/eda/schematic/svg", schFile, nil, nil, &buf); err != nil {
			return err
		}

		var result struct {
			Status string `json:"status"`
			Data   struct {
				SVGs      map[string]string `json:"svgs"`
				SVGCount  int               `json:"svg_count"`
				TotalSize int               `json:"total_size_bytes"`
			} `json:"data"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}
		if result.Error != "" {
			return fmt.Errorf("SVG export failed: %s", result.Error)
		}

		for name, svgB64 := range result.Data.SVGs {
			svgData, err := base64.StdEncoding.DecodeString(svgB64)
			if err != nil {
				return fmt.Errorf("failed to decode SVG %s: %w", name, err)
			}
			outPath := output
			if len(result.Data.SVGs) > 1 {
				outPath = strings.TrimSuffix(output, ".svg") + "_" + name
			}
			if err := os.WriteFile(outPath, svgData, 0644); err != nil {
				return fmt.Errorf("failed to write SVG: %w", err)
			}
			fmt.Printf("Exported SVG: %s (%d bytes)\n", outPath, len(svgData))
		}

		return nil
	},
}
