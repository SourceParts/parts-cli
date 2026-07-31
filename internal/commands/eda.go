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
	Long: `Run electrical and design rule checks, export, and convert EDA files.

Subcommands:
  erc       Run Electrical Rules Check on a KiCad schematic
  drc       Run Design Rules Check on a KiCad PCB
  netlist   Export KiCad XML netlist from a schematic
  export    Export PCB/schematic in various formats (STEP, IPC-2581, BOM, etc.)
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
// Netlist Export
// =============================================================================

var edaNetlist = &cobra.Command{
	Use:   "netlist <file.kicad_sch>",
	Short: "Export a KiCad XML netlist from a schematic",
	Long: `Upload a .kicad_sch file and export a netlist via the server.
Returns XML (raw KiCad netlist) or JSON (parsed nets and components).`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda netlist board.kicad_sch --format json`,
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

		format, _ := cmd.Flags().GetString("format")
		output, _ := cmd.Flags().GetString("output")

		opts := types.NetlistExportOptions{
			Format: format,
		}

		var buf bytes.Buffer
		if err := Client.SchNetlist(ctx, schFile, opts, &buf); err != nil {
			return err
		}

		if output != "" {
			if err := os.WriteFile(output, buf.Bytes(), 0644); err != nil {
				return fmt.Errorf("failed to write output: %w", err)
			}
			fmt.Printf("Saved: %s\n", output)
			return nil
		}

		os.Stdout.Write(buf.Bytes())
		fmt.Println()
		return nil
	},
}

// =============================================================================
// Export — kicad-cli format exports
// =============================================================================

var edaExport = &cobra.Command{
	Use:   "export",
	Short: "Export PCB or schematic in various formats",
	Long: `Export PCB or schematic files via kicad-cli on the server.

Subcommands:
  pcb   Export a .kicad_pcb file (step, glb, vrml, ipc2581, dxf, pdf, pos, odb, gencad, brep, stl, ply, xao)
  sch   Export a .kicad_sch file (bom, pdf, dxf, hpgl, ps)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var edaExportPCB = &cobra.Command{
	Use:   "pcb <file.kicad_pcb>",
	Short: "Export a PCB file in the specified format",
	Long: `Export a .kicad_pcb file via kicad-cli on the server.

Supported formats:
  step      STEP 3D model
  glb       glTF Binary 3D model
  vrml      VRML 3D model
  ipc2581   IPC-2581B XML
  dxf       DXF drawing
  pdf       PDF document
  pos       Pick-and-place position file
  odb       ODB++ archive
  gencad    GenCAD
  brep      OpenCascade BREP
  stl       STL 3D mesh
  ply       PLY 3D mesh
  xao       XAO (SALOME geometry)`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda export pcb board.kicad_pcb --format step -o board.step`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()

		pcbFile := args[0]
		if _, err := os.Stat(pcbFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", pcbFile)
		}
		if !strings.HasSuffix(strings.ToLower(pcbFile), ".kicad_pcb") {
			return fmt.Errorf("expected .kicad_pcb file, got: %s", filepath.Base(pcbFile))
		}

		format, _ := cmd.Flags().GetString("format")
		output, _ := cmd.Flags().GetString("output")

		fields := make(map[string]string)
		// Pass through format-specific flags as form fields
		if v, _ := cmd.Flags().GetString("layers"); v != "" {
			fields["layers"] = v
		}
		if v, _ := cmd.Flags().GetString("side"); v != "" {
			fields["side"] = v
		}
		if v, _ := cmd.Flags().GetString("units"); v != "" {
			fields["units"] = v
		}
		if v, _ := cmd.Flags().GetString("precision"); v != "" {
			fields["precision"] = v
		}
		if v, _ := cmd.Flags().GetBool("board-only"); v {
			fields["board_only"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("no-dnp"); v {
			fields["no_dnp"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("include-tracks"); v {
			fields["include_tracks"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("include-zones"); v {
			fields["include_zones"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("compress"); v {
			fields["compress"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("smd-only"); v {
			fields["smd_only"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("exclude-dnp"); v {
			fields["exclude_dnp"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("black-and-white"); v {
			fields["black_and_white"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("mirror"); v {
			fields["mirror"] = "true"
		}

		opts := types.ExportOptions{
			Format:     format,
			FormFields: fields,
		}

		var buf bytes.Buffer
		if err := Client.PCBExport(ctx, pcbFile, opts, &buf); err != nil {
			return err
		}

		return writeExportResult(buf.Bytes(), output, format)
	},
}

var edaExportSch = &cobra.Command{
	Use:   "sch <file.kicad_sch>",
	Short: "Export a schematic file in the specified format",
	Long: `Export a .kicad_sch file via kicad-cli on the server.

Supported formats:
  bom    Bill of Materials (CSV/TSV)
  pdf    PDF document
  dxf    DXF drawing
  hpgl   HPGL plotter format
  ps     PostScript`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda export sch main.kicad_sch --format bom -o bom.csv`,
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

		format, _ := cmd.Flags().GetString("format")
		output, _ := cmd.Flags().GetString("output")

		fields := make(map[string]string)
		if v, _ := cmd.Flags().GetString("pages"); v != "" {
			fields["pages"] = v
		}
		if v, _ := cmd.Flags().GetString("fields"); v != "" {
			fields["fields"] = v
		}
		if v, _ := cmd.Flags().GetString("group-by"); v != "" {
			fields["group_by"] = v
		}
		if v, _ := cmd.Flags().GetString("sort-field"); v != "" {
			fields["sort_field"] = v
		}
		// Only sent when descending; the API defaults to ascending.
		if v, _ := cmd.Flags().GetBool("sort-desc"); v {
			fields["sort_asc"] = "false"
		}
		if v, _ := cmd.Flags().GetString("format-preset"); v != "" {
			fields["format_preset"] = v
		}
		if v, _ := cmd.Flags().GetBool("black-and-white"); v {
			fields["black_and_white"] = "true"
		}
		if v, _ := cmd.Flags().GetBool("exclude-dnp"); v {
			fields["exclude_dnp"] = "true"
		}

		opts := types.ExportOptions{
			Format:     format,
			FormFields: fields,
		}

		var buf bytes.Buffer
		if err := Client.SchExport(ctx, schFile, opts, &buf); err != nil {
			return err
		}

		return writeExportResult(buf.Bytes(), output, format)
	},
}

// writeExportResult decodes the API response and saves or prints the export.
func writeExportResult(data []byte, output, format string) error {
	var result struct {
		Status string `json:"status"`
		Error  string `json:"error"`
		Data   struct {
			FileBase64 string `json:"file_base64"`
			Content    string `json:"content"`
			Filename   string `json:"filename"`
			SizeBytes  int    `json:"size_bytes"`
		} `json:"data"`
	}

	if err := json.Unmarshal(data, &result); err != nil {
		// Not JSON — might be raw content
		if output != "" {
			if err := os.WriteFile(output, data, 0644); err != nil {
				return fmt.Errorf("failed to write output: %w", err)
			}
			fmt.Printf("Saved: %s (%d bytes)\n", output, len(data))
			return nil
		}
		os.Stdout.Write(data)
		return nil
	}

	if result.Error != "" {
		return fmt.Errorf("export failed: %s", result.Error)
	}

	var fileData []byte
	if result.Data.FileBase64 != "" {
		decoded, err := base64.StdEncoding.DecodeString(result.Data.FileBase64)
		if err != nil {
			return fmt.Errorf("failed to decode response: %w", err)
		}
		fileData = decoded
	} else if result.Data.Content != "" {
		fileData = []byte(result.Data.Content)
	} else {
		return fmt.Errorf("empty response from server")
	}

	if output == "" {
		output = result.Data.Filename
	}
	if output == "" {
		output = "export." + format
	}

	if err := os.WriteFile(output, fileData, 0644); err != nil {
		return fmt.Errorf("failed to write output: %w", err)
	}
	fmt.Printf("Saved: %s (%d bytes)\n", output, len(fileData))
	return nil
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
// Footprint Render — render a .kicad_mod as PNG/SVG via convert-service
// =============================================================================

var edaFootprintRender = &cobra.Command{
	Use:   "footprint render <file.kicad_mod>",
	Short: "Render a KiCad footprint as PNG or SVG",
	Long:  `Upload a .kicad_mod file and render it via kicad-cli on the server. Returns a PNG or SVG image.`,
	Args:  cobra.ExactArgs(1),
	Example: domain.BinaryName + ` eda footprint render SW_Jixing_2x4x3.5_180gf.kicad_mod -o footprint.png`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		fpFile := args[0]
		if _, err := os.Stat(fpFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", fpFile)
		}

		format, _ := cmd.Flags().GetString("format")
		layers, _ := cmd.Flags().GetString("layers")
		scale, _ := cmd.Flags().GetInt("scale")
		output, _ := cmd.Flags().GetString("output")

		if output == "" {
			base := strings.TrimSuffix(filepath.Base(fpFile), filepath.Ext(fpFile))
			output = base + "." + format
		}

		fields := map[string]string{
			"format": format,
			"layers": layers,
			"scale":  fmt.Sprintf("%d", scale),
		}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.Endpoint_FootprintRender, fpFile, fields, nil, &buf); err != nil {
			return err
		}

		// The response is the raw image bytes (not JSON)
		if err := os.WriteFile(output, buf.Bytes(), 0644); err != nil {
			return fmt.Errorf("failed to write output: %w", err)
		}

		fmt.Printf("Rendered footprint: %s (%d bytes)\n", output, buf.Len())
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

	// Netlist flags
	edaNetlist.Flags().String("format", "xml", "Output format: xml or json")
	edaNetlist.Flags().StringP("output", "o", "", "Output file path (default: stdout)")

	// Export PCB flags
	edaExportPCB.Flags().String("format", "step", "Export format: step, glb, vrml, ipc2581, dxf, pdf, pos, odb, gencad, brep, stl, ply, xao")
	edaExportPCB.Flags().StringP("output", "o", "", "Output file path")
	edaExportPCB.Flags().String("layers", "", "Comma-separated layer names (dxf, pdf)")
	edaExportPCB.Flags().String("side", "", "Side: front, back, both (pos)")
	edaExportPCB.Flags().String("units", "", "Units: mm, in, mil (dxf, pos, vrml)")
	edaExportPCB.Flags().String("precision", "", "Precision 3-6 (ipc2581, odb)")
	edaExportPCB.Flags().Bool("board-only", false, "Board only, no components (step, glb, stl, ply)")
	edaExportPCB.Flags().Bool("no-dnp", false, "Exclude DNP components (step, glb, pos, gencad, stl, ply)")
	edaExportPCB.Flags().Bool("include-tracks", false, "Include tracks in 3D export (step, glb, stl, ply)")
	edaExportPCB.Flags().Bool("include-zones", false, "Include zones in 3D export (step, glb, stl, ply)")
	edaExportPCB.Flags().Bool("compress", false, "Compress output (ipc2581)")
	edaExportPCB.Flags().Bool("smd-only", false, "SMD components only (pos)")
	edaExportPCB.Flags().Bool("exclude-dnp", false, "Exclude DNP from position file (pos)")
	edaExportPCB.Flags().Bool("black-and-white", false, "Black and white output (pdf)")
	edaExportPCB.Flags().Bool("mirror", false, "Mirror output (pdf)")

	// Export Sch flags
	edaExportSch.Flags().String("format", "pdf", "Export format: bom, pdf, dxf, hpgl, ps")
	edaExportSch.Flags().StringP("output", "o", "", "Output file path")
	edaExportSch.Flags().String("pages", "", "Page numbers (comma-separated)")
	edaExportSch.Flags().String("fields", "", "BOM fields (comma-separated)")
	edaExportSch.Flags().String("group-by", "", "BOM group-by fields (comma-separated)")
	edaExportSch.Flags().String("sort-field", "", "BOM sort field")
	edaExportSch.Flags().Bool("sort-desc", false, "Sort BOM descending (bom)")
	edaExportSch.Flags().String("format-preset", "CSV", "BOM format: CSV or TSV")
	edaExportSch.Flags().Bool("black-and-white", false, "Black and white output")
	edaExportSch.Flags().Bool("exclude-dnp", false, "Exclude DNP components (bom)")

	edaExport.AddCommand(edaExportPCB)
	edaExport.AddCommand(edaExportSch)

	EDA.AddCommand(edaERC)
	EDA.AddCommand(edaDRC)
	EDA.AddCommand(edaNetlist)
	EDA.AddCommand(edaExport)
	EDA.AddCommand(edaImport)
	EDA.AddCommand(edaDXF)
	EDA.AddCommand(edaCtrl)
	edaSVG.Flags().StringP("output", "o", "", "Output SVG path")
	EDA.AddCommand(edaSVG)
	edaPCBSVG.Flags().StringP("output", "o", "", "Output SVG path")
	edaPCBSVG.Flags().String("layers", "F.Cu,B.Cu,Edge.Cuts,F.SilkS", "Layers to include")
	EDA.AddCommand(edaPCBSVG)
	edaPCBHighlight.Flags().String("nets", "", "Comma-separated net names to highlight")
	edaPCBHighlight.Flags().StringP("output", "o", "highlight.svg", "Output SVG path")
	EDA.AddCommand(edaPCBHighlight)
	EDA.AddCommand(edaRender)
	EDA.AddCommand(edaSchRemove)
	EDA.AddCommand(edaSchAnnotate)

	// Footprint render flags
	edaFootprintRender.Flags().StringP("output", "o", "", "Output image path (default: <basename>.png)")
	edaFootprintRender.Flags().String("format", "png", "Output format: png or svg")
	edaFootprintRender.Flags().String("layers", "F.Cu,F.SilkS,F.CrtYd,F.Fab,F.Mask", "Layers to render")
	edaFootprintRender.Flags().Int("scale", 10, "Scale factor for PNG output")
	EDA.AddCommand(edaFootprintRender)
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

var edaPCBSVG = &cobra.Command{
	Use:   "pcbsvg <file.kicad_pcb>",
	Short: "Export PCB as SVG",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()

		pcbFile := args[0]
		if _, err := os.Stat(pcbFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", pcbFile)
		}

		output, _ := cmd.Flags().GetString("output")
		if output == "" {
			base := strings.TrimSuffix(filepath.Base(pcbFile), filepath.Ext(pcbFile))
			output = base + ".svg"
		}

		layers, _ := cmd.Flags().GetString("layers")
		fields := map[string]string{}
		if layers != "" {
			fields["params"] = fmt.Sprintf(`{"layers":"%s"}`, layers)
		}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.V1Prefix+"/eda/pcb/svg", pcbFile, fields, nil, &buf); err != nil {
			return err
		}

		var result struct {
			Status string `json:"status"`
			Data   struct {
				SVGBase64 string `json:"svg_base64"`
				SVGSize   int    `json:"svg_size_bytes"`
			} `json:"data"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}
		if result.Error != "" {
			return fmt.Errorf("export failed: %s", result.Error)
		}

		svgData, err := base64.StdEncoding.DecodeString(result.Data.SVGBase64)
		if err != nil {
			return fmt.Errorf("failed to decode SVG: %w", err)
		}
		if err := os.WriteFile(output, svgData, 0644); err != nil {
			return fmt.Errorf("failed to write SVG: %w", err)
		}

		fmt.Printf("Exported PCB SVG: %s (%d bytes)\n", output, len(svgData))
		return nil
	},
}

var edaPCBHighlight = &cobra.Command{
	Use:   "highlight <file.kicad_pcb> --nets <net1,net2,...>",
	Short: "Export PCB SVG with highlighted nets",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()

		pcbFile := args[0]
		if _, err := os.Stat(pcbFile); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", pcbFile)
		}

		nets, _ := cmd.Flags().GetString("nets")
		output, _ := cmd.Flags().GetString("output")
		if output == "" {
			output = "highlight.svg"
		}

		params := fmt.Sprintf(`{"nets":"%s"}`, nets)
		fields := map[string]string{"params": params}

		var buf bytes.Buffer
		if err := Client.EDAUpload(ctx, domain.V1Prefix+"/eda/pcb/highlight", pcbFile, fields, nil, &buf); err != nil {
			return err
		}

		var result struct {
			Status string `json:"status"`
			Data   struct {
				SVGBase64       string   `json:"svg_base64"`
				HighlightedNets []string `json:"highlighted_nets"`
				TotalTracks     int      `json:"total_tracks"`
				TotalVias       int      `json:"total_vias"`
				OverlayElements int      `json:"overlay_elements"`
			} `json:"data"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
			return fmt.Errorf("failed to parse response: %w", err)
		}
		if result.Error != "" {
			return fmt.Errorf("highlight failed: %s", result.Error)
		}

		svgData, err := base64.StdEncoding.DecodeString(result.Data.SVGBase64)
		if err != nil {
			return fmt.Errorf("failed to decode SVG: %w", err)
		}
		if err := os.WriteFile(output, svgData, 0644); err != nil {
			return fmt.Errorf("failed to write SVG: %w", err)
		}

		fmt.Printf("Highlight SVG: %s (%d bytes)\n", output, len(svgData))
		fmt.Printf("Nets: %v\n", result.Data.HighlightedNets)
		fmt.Printf("Tracks: %d, Vias: %d, Overlay: %d elements\n",
			result.Data.TotalTracks, result.Data.TotalVias, result.Data.OverlayElements)
		return nil
	},
}
