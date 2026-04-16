package commands

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/schollz/progressbar/v3"
	"github.com/spf13/cobra"
)

// =============================================================================
// Main Fabrication Command
// =============================================================================

var Fab = &cobra.Command{
	Use:     "fab",
	Aliases: []string{"fabricate"},
	Short:   "Fabrication and assembly operations",
	Long: `Submit fabrication orders, generate placement files, and manage manufacturing operations.

Subcommands:
  placement    Generate pick-and-place outputs from position file
  stackup      Generate PCB layer stackup PDF from gerbers
  diff         Compare two gerber revisions with layer-by-layer diff PDF
  testpoints   Generate test point report from position file
  quote        Get fabrication or assembly quotation
  release      Create a fabrication or assembly release package

Examples:
  parts fab placement positions.csv
  parts fab stackup gerbers.zip
  parts fab diff rev1.zip rev2.zip
  parts fab testpoints positions.csv
`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// =============================================================================
// Placement Generation
// =============================================================================

var (
	placementOutput      string
	placementBoard       string
	placementOutline     string
	placementGerbers     string
	placementBOM         string
	placementPrefix      string
	placementBoardWidth  float64
	placementBoardHeight float64
	placementRows        int
	placementCols        int
	placementAssemble    string
	placementSkip        string
	placementRotateTop   bool
	placementSide        string
	placementFormat      string
	placementSplitCSV    bool
	placementManualPlace string
	placementMachine     string
	placementFeederMap   string
)

var fabPlacement = &cobra.Command{
	Use:     "placement <positions.csv>",
	Aliases: []string{"pnp", "centroid"},
	Short:   "Generate pick-and-place outputs from component position file",
	Long: `Generate placement visualization and machine pick-and-place files from a
component position CSV file.

Supports KiCad, Altium, Eagle, and generic CSV position formats.
Outputs include:
  - placement_top.png (top side panel visualization with Edge.Cuts outline)
  - placement_bottom.png (bottom side panel visualization)
  - placement.pdf (2-page A4 landscape PDF with Parts Studio branding)
  - panelized.csv (Neoden-compatible machine format)
  - feeder_map.csv (when BOM provided — feeder assignment reference)
  - metadata.json (processing details including per-side component counts)

Panel positions are numbered 1-indexed, left-to-right, bottom-to-top:
  7 | 8 | 9    (top row, rotated 180 if --rotate-top)
  4 | 5 | 6
  1 | 2 | 3    (bottom row)`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` fab placement positions.csv
` + domain.BinaryName + ` fab placement positions.csv --outline board.gko --side both
` + domain.BinaryName + ` fab placement positions.csv --rows 3 --cols 3 --skip 5,6,7,8
` + domain.BinaryName + ` fab placement positions.csv --gerbers production.zip --rows 3 --cols 3
` + domain.BinaryName + ` fab placement positions.csv --machine yy1 --manual-place U,J,SW`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()

		positionFile := args[0]

		// Validate position file exists
		if _, err := os.Stat(positionFile); os.IsNotExist(err) {
			return fmt.Errorf("position file not found: %s", positionFile)
		}

		// Validate outline file if provided
		if placementOutline != "" {
			if _, err := os.Stat(placementOutline); os.IsNotExist(err) {
				return fmt.Errorf("outline file not found: %s", placementOutline)
			}
		}

		// Validate gerbers file if provided
		if placementGerbers != "" {
			if _, err := os.Stat(placementGerbers); os.IsNotExist(err) {
				return fmt.Errorf("gerbers file not found: %s", placementGerbers)
			}
		}

		// Validate BOM file if provided
		if placementBOM != "" {
			if _, err := os.Stat(placementBOM); os.IsNotExist(err) {
				return fmt.Errorf("BOM file not found: %s", placementBOM)
			}
		}

		// Validate feeder map if provided
		if placementFeederMap != "" {
			if _, err := os.Stat(placementFeederMap); os.IsNotExist(err) {
				return fmt.Errorf("feeder map file not found: %s", placementFeederMap)
			}
		}

		// Validate mutually exclusive flags
		if placementAssemble != "" && placementSkip != "" {
			return fmt.Errorf("cannot specify both --assemble and --skip; use one or the other")
		}

		fmt.Printf("Generating placement outputs for: %s\n", filepath.Base(positionFile))
		if placementRows > 1 || placementCols > 1 {
			fmt.Printf("Panel configuration: %dx%d (%d positions)\n", placementRows, placementCols, placementRows*placementCols)
		}

		// Create multipart form data
		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)

		// Add position file
		if err := addFileToMultipart(writer, "file", positionFile); err != nil {
			return fmt.Errorf("failed to add position file: %w", err)
		}

		// Add outline file if provided
		if placementOutline != "" {
			if err := addFileToMultipart(writer, "outline", placementOutline); err != nil {
				return fmt.Errorf("failed to add outline file: %w", err)
			}
		}

		// Add gerbers file if provided
		if placementGerbers != "" {
			if err := addFileToMultipart(writer, "gerbers", placementGerbers); err != nil {
				return fmt.Errorf("failed to add gerbers file: %w", err)
			}
		}

		// Add BOM file if provided
		if placementBOM != "" {
			if err := addFileToMultipart(writer, "bom", placementBOM); err != nil {
				return fmt.Errorf("failed to add BOM file: %w", err)
			}
		}

		// Add feeder map if provided
		if placementFeederMap != "" {
			if err := addFileToMultipart(writer, "feeder_map", placementFeederMap); err != nil {
				return fmt.Errorf("failed to add feeder map file: %w", err)
			}
		}

		// Add form fields
		if placementBoard != "" {
			writer.WriteField("board_name", placementBoard)
		}
		if placementPrefix != "" {
			writer.WriteField("prefix", placementPrefix)
		}
		if placementBoardWidth > 0 {
			writer.WriteField("board_width", fmt.Sprintf("%.2f", placementBoardWidth))
		}
		if placementBoardHeight > 0 {
			writer.WriteField("board_height", fmt.Sprintf("%.2f", placementBoardHeight))
		}
		if placementRows > 1 {
			writer.WriteField("rows", fmt.Sprintf("%d", placementRows))
		}
		if placementCols > 1 {
			writer.WriteField("cols", fmt.Sprintf("%d", placementCols))
		}
		if placementAssemble != "" {
			writer.WriteField("assemble", placementAssemble)
		}
		if placementSkip != "" {
			writer.WriteField("skip", placementSkip)
		}
		if placementRotateTop {
			writer.WriteField("rotate_top", "true")
		}
		if placementSide != "" {
			writer.WriteField("side", placementSide)
		}
		if placementFormat != "" {
			writer.WriteField("format", placementFormat)
		}
		if placementSplitCSV {
			writer.WriteField("split_csv", "true")
		}
		if placementManualPlace != "" {
			writer.WriteField("manual_place", placementManualPlace)
		}
		if placementMachine != "" {
			writer.WriteField("machine", placementMachine)
		}

		writer.Close()

		// Create request
		url := fmt.Sprintf("https://%s%s", domain.API, domain.Endpoint_ManufacturingPlacement)
		req, err := http.NewRequestWithContext(ctx, "POST", url, &requestBody)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)

		// Set API key if available
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		// Send request with progress bar for upload
		fmt.Println("\nUploading files...")
		uploadBar := progressbar.DefaultBytes(
			int64(requestBody.Len()),
			"Upload",
		)

		// Create a reader that updates the progress bar
		progressReader := &progressReader{
			reader: &requestBody,
			bar:    uploadBar,
		}

		req.Body = io.NopCloser(progressReader)
		req.ContentLength = int64(requestBody.Len())

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
		}

		fmt.Println("\n\nProcessing...")

		// Read response with progress bar
		var responseBuffer bytes.Buffer
		responseSize := resp.ContentLength
		if responseSize <= 0 {
			responseSize = 10 * 1024 * 1024 // Assume 10MB if unknown
		}

		downloadBar := progressbar.DefaultBytes(
			responseSize,
			"Download",
		)

		_, err = io.Copy(io.MultiWriter(&responseBuffer, downloadBar), resp.Body)
		if err != nil {
			return fmt.Errorf("failed to download response: %w", err)
		}

		fmt.Println()

		// Determine output path
		outputPath := placementOutput
		if outputPath == "" || outputPath == "." {
			baseName := placementPrefix
			if baseName == "" {
				baseName = strings.TrimSuffix(filepath.Base(positionFile), filepath.Ext(positionFile))
			}
			outputPath = baseName + "_placement.zip"
		}

		// Ensure output has .zip extension
		if !strings.HasSuffix(strings.ToLower(outputPath), ".zip") {
			outputPath += ".zip"
		}

		// Write ZIP file
		if err := os.WriteFile(outputPath, responseBuffer.Bytes(), 0644); err != nil {
			return fmt.Errorf("failed to write output file: %w", err)
		}

		// Extract and display metadata
		if err := displayPlacementResults(outputPath); err != nil {
			fmt.Printf("Warning: could not read metadata: %v\n", err)
		}

		fmt.Printf("\n✓ Placement files saved to: %s\n", outputPath)
		fmt.Printf("\nExtract the ZIP to view:\n")
		fmt.Printf("  - placement_top.png (top side visualization)\n")
		fmt.Printf("  - placement_bottom.png (bottom side visualization)\n")
		fmt.Printf("  - placement.pdf (2-page A4 PDF)\n")
		fmt.Printf("  - panelized.csv (pick-and-place file)\n")
		if placementBOM != "" {
			fmt.Printf("  - feeder_map.csv (feeder assignments)\n")
		}
		fmt.Printf("  - metadata.json (processing details)\n")

		return nil
	},
}

// =============================================================================
// Stackup Generation
// =============================================================================

var (
	stackupOutput    string
	stackupBoardName string
	stackupPrefix    string
	stackupScale     int
)

var fabStackup = &cobra.Command{
	Use:   "stackup <gerber.zip>",
	Short: "Generate PCB layer stackup PDF from gerbers",
	Long: `Generate a multi-page PDF stackup visualization from gerber files.

Each page renders one PCB layer (copper, silkscreen, solder mask, etc.)
on A4 landscape with annotations. Default scale is 1:1; use --scale
for larger rendering (e.g., --scale 3 for 3:1 zoom on small boards).

The input must be a .zip archive containing gerber files.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` fab stackup gerbers.zip
` + domain.BinaryName + ` fab stackup gerbers.zip -o my_stackup.pdf
` + domain.BinaryName + ` fab stackup gerbers.zip -b "My Board v2.1"
` + domain.BinaryName + ` fab stackup gerbers.zip --scale 3
` + domain.BinaryName + ` fab stackup gerbers.zip --prefix "nRF54H20_V1.03"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()

		zipPath := args[0]

		// Validate file exists and is a zip
		info, err := os.Stat(zipPath)
		if err != nil {
			return fmt.Errorf("file not found: %s", zipPath)
		}
		if info.IsDir() {
			return fmt.Errorf("expected a zip file, got a directory: %s", zipPath)
		}
		if !strings.HasSuffix(strings.ToLower(zipPath), ".zip") {
			return fmt.Errorf("file must be a .zip archive: %s", zipPath)
		}

		fmt.Printf("Generating stackup PDF for: %s\n", filepath.Base(zipPath))

		// Build output filename
		outputPath := stackupOutput
		if outputPath == "" {
			baseName := stackupPrefix
			if baseName == "" {
				baseName = strings.TrimSuffix(filepath.Base(zipPath), filepath.Ext(zipPath))
			}
			outputPath = baseName + "_stackup.pdf"
		}

		return uploadAndDownloadFile(ctx, zipPath, outputPath, domain.Endpoint_ManufacturingStackup, map[string]string{
			"board_name": stackupBoardName,
			"scale":      fmt.Sprintf("%d", stackupScale),
		})
	},
}

// =============================================================================
// Stackup Diff
// =============================================================================

var (
	stackupDiffOutput string
	stackupDiffNameA  string
	stackupDiffNameB  string
	stackupDiffDPI    int
)

var fabStackupDiff = &cobra.Command{
	Use:     "diff <gerbers-a.zip> <gerbers-b.zip>",
	Aliases: []string{"compare"},
	Short:   "Generate a layer-by-layer diff PDF comparing two gerber sets",
	Long: `Compare two PCB gerber revisions and generate an annotated diff PDF.

Each matched layer is rendered side-by-side at the same DPI and overlaid as a
4-colour XOR diff:

  Dark gray  — no copper in either revision
  Light gray — unchanged copper (present in both)
  Red        — removed (only in A / old revision)
  Green      — added   (only in B / new revision)

A Net Statistics Diff page is also included showing per-layer pad, trace, and
polygon counts plus connected copper region counts (a geometric proxy for nets).

Both inputs must be .zip archives containing gerber files.`,
	Args: cobra.ExactArgs(2),
	Example: domain.BinaryName + ` fab diff rev1.zip rev2.zip
` + domain.BinaryName + ` fab diff rev1.zip rev2.zip --name-a "v1.03" --name-b "v1.04"
` + domain.BinaryName + ` fab diff rev1.zip rev2.zip -o board_diff.pdf
` + domain.BinaryName + ` fab diff rev1.zip rev2.zip --dpi 300`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()

		zipA := args[0]
		zipB := args[1]

		// Validate both files
		for _, p := range []string{zipA, zipB} {
			info, err := os.Stat(p)
			if err != nil {
				return fmt.Errorf("file not found: %s", p)
			}
			if info.IsDir() {
				return fmt.Errorf("expected a zip file, got a directory: %s", p)
			}
			if !strings.HasSuffix(strings.ToLower(p), ".zip") {
				return fmt.Errorf("file must be a .zip archive: %s", p)
			}
		}

		// Default output: diff_<a>_vs_<b>.pdf
		outputPath := stackupDiffOutput
		if outputPath == "" {
			baseA := strings.TrimSuffix(filepath.Base(zipA), filepath.Ext(zipA))
			baseB := strings.TrimSuffix(filepath.Base(zipB), filepath.Ext(zipB))
			outputPath = "diff_" + baseA + "_vs_" + baseB + ".pdf"
		}

		fmt.Printf("Comparing gerber revisions:\n")
		fmt.Printf("  A: %s\n", filepath.Base(zipA))
		fmt.Printf("  B: %s\n", filepath.Base(zipB))

		// Upload both files
		return uploadTwoFilesAndDownload(ctx, zipA, zipB, outputPath, domain.Endpoint_ManufacturingStackupDiff, map[string]string{
			"name_a": stackupDiffNameA,
			"name_b": stackupDiffNameB,
			"dpi":    fmt.Sprintf("%d", stackupDiffDPI),
		})
	},
}

// =============================================================================
// Test Points
// =============================================================================

var (
	testpointsOutput   string
	testpointsBoard    string
	testpointsOutline  string
	testpointsGerbers  string
	testpointsBom      string
	testpointsPrefix   string
	testpointsRows     int
	testpointsCols     int
	testpointsAssemble string
	testpointsSide     string
	testpointsFormat   string
)

var fabTestpoints = &cobra.Command{
	Use:     "testpoints <positions.csv>",
	Aliases: []string{"tp"},
	Short:   "Generate test point report from position file",
	Long: `Generate test point report from a component position CSV file.

Filters to TP-prefix designators and produces:
- PNG visualization per side (test points on panel layout)
- Branded PDF with panel views and test point table
- CSV listing (Designator, Signal, X, Y, Side)

When a BOM file is provided, signal names are extracted from the Value column.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` fab testpoints positions.csv
` + domain.BinaryName + ` fab tp positions.csv --bom BOM/bom.csv
` + domain.BinaryName + ` fab testpoints positions.csv --rows 3 --cols 3 --gerbers production.zip`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()

		positionFile := args[0]

		if _, err := os.Stat(positionFile); os.IsNotExist(err) {
			return fmt.Errorf("position file not found: %s", positionFile)
		}
		if testpointsOutline != "" {
			if _, err := os.Stat(testpointsOutline); os.IsNotExist(err) {
				return fmt.Errorf("outline file not found: %s", testpointsOutline)
			}
		}
		if testpointsGerbers != "" {
			if _, err := os.Stat(testpointsGerbers); os.IsNotExist(err) {
				return fmt.Errorf("gerbers file not found: %s", testpointsGerbers)
			}
		}
		if testpointsBom != "" {
			if _, err := os.Stat(testpointsBom); os.IsNotExist(err) {
				return fmt.Errorf("BOM file not found: %s", testpointsBom)
			}
		}

		fmt.Printf("Generating test point report for: %s\n", filepath.Base(positionFile))
		if testpointsRows > 1 || testpointsCols > 1 {
			fmt.Printf("Panel configuration: %dx%d (%d positions)\n", testpointsRows, testpointsCols, testpointsRows*testpointsCols)
		}

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)

		if err := addFileToMultipart(writer, "file", positionFile); err != nil {
			return fmt.Errorf("failed to add position file: %w", err)
		}
		if testpointsOutline != "" {
			if err := addFileToMultipart(writer, "outline", testpointsOutline); err != nil {
				return fmt.Errorf("failed to add outline file: %w", err)
			}
		}
		if testpointsGerbers != "" {
			if err := addFileToMultipart(writer, "gerbers", testpointsGerbers); err != nil {
				return fmt.Errorf("failed to add gerbers file: %w", err)
			}
		}
		if testpointsBom != "" {
			if err := addFileToMultipart(writer, "bom", testpointsBom); err != nil {
				return fmt.Errorf("failed to add BOM file: %w", err)
			}
		}

		if testpointsBoard != "" {
			writer.WriteField("board_name", testpointsBoard)
		}
		if testpointsPrefix != "" {
			writer.WriteField("prefix", testpointsPrefix)
		}
		if testpointsRows > 1 {
			writer.WriteField("rows", fmt.Sprintf("%d", testpointsRows))
		}
		if testpointsCols > 1 {
			writer.WriteField("cols", fmt.Sprintf("%d", testpointsCols))
		}
		if testpointsAssemble != "" {
			writer.WriteField("assemble", testpointsAssemble)
		}
		if testpointsSide != "" {
			writer.WriteField("side", testpointsSide)
		}
		if testpointsFormat != "" {
			writer.WriteField("format", testpointsFormat)
		}

		writer.Close()

		url := fmt.Sprintf("https://%s%s", domain.API, domain.Endpoint_ManufacturingTestpoints)
		req, err := http.NewRequestWithContext(ctx, "POST", url, &requestBody)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		fmt.Println("\nUploading files...")
		uploadBar := progressbar.DefaultBytes(int64(requestBody.Len()), "Upload")
		progressRdr := &progressReader{reader: &requestBody, bar: uploadBar}
		req.Body = io.NopCloser(progressRdr)
		req.ContentLength = int64(requestBody.Len())

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
		}

		fmt.Println("\n\nProcessing...")

		responseSize := resp.ContentLength
		if responseSize <= 0 {
			responseSize = 10 * 1024 * 1024
		}
		downloadBar := progressbar.DefaultBytes(responseSize, "Download")

		var responseBuffer bytes.Buffer
		if _, err := io.Copy(io.MultiWriter(&responseBuffer, downloadBar), resp.Body); err != nil {
			return fmt.Errorf("failed to download response: %w", err)
		}
		fmt.Println()

		outputDir := testpointsOutput
		if outputDir == "" {
			outputDir = "."
		}
		if err := os.MkdirAll(outputDir, 0755); err != nil {
			return fmt.Errorf("failed to create output directory: %w", err)
		}

		extracted, err := extractZipToDir(responseBuffer.Bytes(), outputDir)
		if err != nil {
			return fmt.Errorf("failed to extract output: %w", err)
		}

		fmt.Println("\n✓ Test point report saved:")
		for _, name := range extracted {
			fmt.Printf("  %s\n", filepath.Join(outputDir, name))
		}

		return nil
	},
}

// =============================================================================
// Quote / RFQ
// =============================================================================

var (
	quoteQuantity      int
	quoteLayers        int
	quoteThickness     float64
	quoteSurfaceFinish string
	quoteColor         string
	quotePriority      string
	quoteBom           string
	quoteAssembly      bool
)

var fabQuote = &cobra.Command{
	Use:     "quote <gerber.zip>",
	Aliases: []string{"rfq"},
	Short:   "Get a fabrication or assembly quote",
	Long: `Get a fabrication or assembly quote from gerber files.

Upload a gerber zip to receive a fabrication quotation. Optionally include
a BOM file with --bom and --assembly to get a combined assembly quote
including COGS (Cost of Goods Sold).`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` fab quote gerbers.zip
` + domain.BinaryName + ` fab quote gerbers.zip --quantity 10 --layers 4
` + domain.BinaryName + ` fab quote gerbers.zip --assembly --bom bom.csv
` + domain.BinaryName + ` fab quote gerbers.zip --surface-finish ENIG --color black`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()

		gerberFile := args[0]

		if _, err := os.Stat(gerberFile); os.IsNotExist(err) {
			return fmt.Errorf("gerber file not found: %s", gerberFile)
		}
		if quoteAssembly && quoteBom == "" {
			return fmt.Errorf("--bom is required when --assembly is set")
		}
		if quoteBom != "" {
			if _, err := os.Stat(quoteBom); os.IsNotExist(err) {
				return fmt.Errorf("BOM file not found: %s", quoteBom)
			}
		}

		fmt.Printf("Requesting quote for: %s\n", filepath.Base(gerberFile))
		fmt.Printf("  Quantity: %d boards, %d layers, %.1fmm\n", quoteQuantity, quoteLayers, quoteThickness)
		if quoteAssembly {
			fmt.Printf("  Assembly: yes (BOM: %s)\n", filepath.Base(quoteBom))
		}

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)

		if err := addFileToMultipart(writer, "file", gerberFile); err != nil {
			return fmt.Errorf("failed to add gerber file: %w", err)
		}
		if quoteBom != "" {
			if err := addFileToMultipart(writer, "bom", quoteBom); err != nil {
				return fmt.Errorf("failed to add BOM file: %w", err)
			}
		}

		writer.WriteField("quantity", fmt.Sprintf("%d", quoteQuantity))
		writer.WriteField("layers", fmt.Sprintf("%d", quoteLayers))
		writer.WriteField("thickness", fmt.Sprintf("%.2f", quoteThickness))
		if quoteSurfaceFinish != "" {
			writer.WriteField("surface_finish", quoteSurfaceFinish)
		}
		if quoteColor != "" {
			writer.WriteField("color", quoteColor)
		}
		if quotePriority != "" {
			writer.WriteField("priority", quotePriority)
		}
		if quoteAssembly {
			writer.WriteField("assembly", "true")
		}

		writer.Close()

		url := fmt.Sprintf("https://%s%s", domain.API, domain.Endpoint_ManufacturingFab)
		req, err := http.NewRequestWithContext(ctx, "POST", url, &requestBody)
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		fmt.Println("\nUploading...")
		uploadBar := progressbar.DefaultBytes(int64(requestBody.Len()), "Upload")
		progressRdr := &progressReader{reader: &requestBody, bar: uploadBar}
		req.Body = io.NopCloser(progressRdr)
		req.ContentLength = int64(requestBody.Len())

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return fmt.Errorf("request failed: %w", err)
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			body, _ := io.ReadAll(resp.Body)
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
		}

		fmt.Println("\n")

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return fmt.Errorf("failed to read response: %w", err)
		}

		// Pretty-print JSON if possible, otherwise raw
		var parsed interface{}
		if json.Unmarshal(body, &parsed) == nil {
			pretty, _ := json.MarshalIndent(parsed, "", "  ")
			fmt.Println(string(pretty))
		} else {
			fmt.Println(string(body))
		}

		return nil
	},
}

// =============================================================================
// Fabrication Release
// =============================================================================

var (
	releaseVersion string
	releaseNotes   string
	releaseBOM     bool
	releaseAsm     bool
	releaseOutput  string
)

var fabRelease = &cobra.Command{
	Use:   "release <gerber-zip>",
	Short: "Create a fabrication/assembly release package",
	Long: `Upload gerbers and create a manufacturing-ready release package.
Validates gerbers, runs DRC checks, and packages all manufacturing files.

The input can be a .zip archive of gerber files or a directory containing them.
If a directory is given, it will be zipped automatically before upload.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` fab release board_v7.zip
` + domain.BinaryName + ` fab release gerbers/ --version 1.0.0 --bom --assembly`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()

		input := args[0]

		// Check input exists
		info, err := os.Stat(input)
		if err != nil {
			return fmt.Errorf("input not found: %s", input)
		}

		zipPath := input

		// If input is a directory, zip it first
		if info.IsDir() {
			fmt.Printf("Zipping directory: %s\n", input)
			tmpZip, err := zipDirectory(input)
			if err != nil {
				return fmt.Errorf("failed to zip directory: %w", err)
			}
			defer os.Remove(tmpZip)
			zipPath = tmpZip
		} else if !strings.HasSuffix(strings.ToLower(input), ".zip") {
			return fmt.Errorf("input must be a .zip file or a directory: %s", input)
		}

		fmt.Printf("Creating release package for: %s\n", filepath.Base(input))

		opts := types.ReleaseOptions{
			Version:    releaseVersion,
			Notes:      releaseNotes,
			IncludeBOM: releaseBOM,
			IncludeAsm: releaseAsm,
			Output:     releaseOutput,
		}

		return Client.Release(ctx, zipPath, opts, os.Stdout)
	},
}

// zipDirectory creates a temporary zip file from a directory's contents
func zipDirectory(dir string) (string, error) {
	tmpFile, err := os.CreateTemp("", "parts-release-*.zip")
	if err != nil {
		return "", err
	}
	defer tmpFile.Close()

	zipWriter := zip.NewWriter(tmpFile)
	defer zipWriter.Close()

	return tmpFile.Name(), filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}

		relPath, err := filepath.Rel(dir, path)
		if err != nil {
			return err
		}

		w, err := zipWriter.Create(relPath)
		if err != nil {
			return err
		}

		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()

		_, err = io.Copy(w, f)
		return err
	})
}

// =============================================================================
// Helper Functions
// =============================================================================

// progressReader wraps an io.Reader to update a progress bar
type progressReader struct {
	reader io.Reader
	bar    *progressbar.ProgressBar
}

func (pr *progressReader) Read(p []byte) (int, error) {
	n, err := pr.reader.Read(p)
	if n > 0 {
		pr.bar.Add(n)
	}
	return n, err
}

// addFileToMultipart adds a file to a multipart writer
func addFileToMultipart(writer *multipart.Writer, fieldName, filePath string) error {
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	part, err := writer.CreateFormFile(fieldName, filepath.Base(filePath))
	if err != nil {
		return err
	}

	_, err = io.Copy(part, file)
	return err
}

// uploadAndDownloadFile uploads a single file with progress tracking
func uploadAndDownloadFile(ctx context.Context, inputPath, outputPath, endpoint string, formFields map[string]string) error {
	// Create multipart form
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	// Add file
	if err := addFileToMultipart(writer, "file", inputPath); err != nil {
		return fmt.Errorf("failed to add file: %w", err)
	}

	// Add form fields
	for key, value := range formFields {
		if value != "" && value != "0" {
			writer.WriteField(key, value)
		}
	}

	writer.Close()

	// Create request
	url := fmt.Sprintf("https://%s%s", domain.API, endpoint)
	req, err := http.NewRequestWithContext(ctx, "POST", url, &requestBody)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)

	// Set API key if available
	if apiKey := Client.GetAPIKey(); apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// Upload with progress bar
	fmt.Println("\nUploading...")
	uploadBar := progressbar.DefaultBytes(int64(requestBody.Len()), "Upload")

	progressReader := &progressReader{reader: &requestBody, bar: uploadBar}
	req.Body = io.NopCloser(progressReader)
	req.ContentLength = int64(requestBody.Len())

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	fmt.Println("\n\nProcessing...")

	// Download with progress bar
	responseSize := resp.ContentLength
	if responseSize <= 0 {
		responseSize = 10 * 1024 * 1024 // Default 10MB
	}

	downloadBar := progressbar.DefaultBytes(responseSize, "Download")

	outFile, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create output file: %w", err)
	}
	defer outFile.Close()

	_, err = io.Copy(io.MultiWriter(outFile, downloadBar), resp.Body)
	if err != nil {
		return fmt.Errorf("failed to download response: %w", err)
	}

	fmt.Printf("\n\n✓ Output saved to: %s\n", outputPath)
	return nil
}

// uploadTwoFilesAndDownload uploads two files with progress tracking
func uploadTwoFilesAndDownload(ctx context.Context, fileA, fileB, outputPath, endpoint string, formFields map[string]string) error {
	// Create multipart form
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	// Add both files
	if err := addFileToMultipart(writer, "file_a", fileA); err != nil {
		return fmt.Errorf("failed to add file A: %w", err)
	}
	if err := addFileToMultipart(writer, "file_b", fileB); err != nil {
		return fmt.Errorf("failed to add file B: %w", err)
	}

	// Add form fields
	for key, value := range formFields {
		if value != "" && value != "0" {
			writer.WriteField(key, value)
		}
	}

	writer.Close()

	// Create request
	url := fmt.Sprintf("https://%s%s", domain.API, endpoint)
	req, err := http.NewRequestWithContext(ctx, "POST", url, &requestBody)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)

	// Set API key if available
	if apiKey := Client.GetAPIKey(); apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

	// Upload with progress bar
	fmt.Println("\nUploading...")
	uploadBar := progressbar.DefaultBytes(int64(requestBody.Len()), "Upload")

	progressReader := &progressReader{reader: &requestBody, bar: uploadBar}
	req.Body = io.NopCloser(progressReader)
	req.ContentLength = int64(requestBody.Len())

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	fmt.Println("\n\nProcessing...")

	// Download with progress bar
	responseSize := resp.ContentLength
	if responseSize <= 0 {
		responseSize = 20 * 1024 * 1024 // Default 20MB for diffs
	}

	downloadBar := progressbar.DefaultBytes(responseSize, "Download")

	outFile, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create output file: %w", err)
	}
	defer outFile.Close()

	_, err = io.Copy(io.MultiWriter(outFile, downloadBar), resp.Body)
	if err != nil {
		return fmt.Errorf("failed to download response: %w", err)
	}

	fmt.Printf("\n\n✓ Output saved to: %s\n", outputPath)
	return nil
}

// displayPlacementResults extracts and displays metadata from the placement ZIP
func displayPlacementResults(zipPath string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()

	// Find and read metadata.json
	for _, f := range r.File {
		if f.Name == "metadata.json" {
			rc, err := f.Open()
			if err != nil {
				return err
			}
			defer rc.Close()

			var metadata struct {
				BoardName       string `json:"board_name"`
				Rows            int    `json:"rows"`
				Cols            int    `json:"cols"`
				TopComponents   int    `json:"top_components"`
				BotComponents   int    `json:"bot_components"`
				TotalPlacements int    `json:"total_placements"`
			}

			if err := json.NewDecoder(rc).Decode(&metadata); err != nil {
				return err
			}

			fmt.Println("\nPlacement Summary:")
			if metadata.BoardName != "" {
				fmt.Printf("  Board: %s\n", metadata.BoardName)
			}
			if metadata.Rows > 1 || metadata.Cols > 1 {
				fmt.Printf("  Panel: %dx%d = %d boards\n", metadata.Rows, metadata.Cols, metadata.Rows*metadata.Cols)
			}
			fmt.Printf("  Top components: %d\n", metadata.TopComponents)
			fmt.Printf("  Bottom components: %d\n", metadata.BotComponents)
			if metadata.TotalPlacements > 0 {
				fmt.Printf("  Total placements: %d\n", metadata.TotalPlacements)
			}

			return nil
		}
	}

	return fmt.Errorf("metadata.json not found in output ZIP")
}

// extractZipToDir extracts a ZIP archive (given as raw bytes) into destDir.
// Returns the list of filenames extracted. Rejects path traversal entries.
func extractZipToDir(data []byte, destDir string) ([]string, error) {
	r, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, fmt.Errorf("invalid zip: %w", err)
	}

	var names []string
	for _, f := range r.File {
		name := f.Name

		// Reject absolute paths and path traversal
		if filepath.IsAbs(name) || strings.Contains(name, "..") {
			return nil, fmt.Errorf("unsafe path in zip: %s", name)
		}

		destPath := filepath.Join(destDir, name)

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(destPath, 0755); err != nil {
				return nil, err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
			return nil, err
		}

		rc, err := f.Open()
		if err != nil {
			return nil, err
		}

		out, err := os.Create(destPath)
		if err != nil {
			rc.Close()
			return nil, err
		}

		if _, err := io.Copy(out, rc); err != nil {
			out.Close()
			rc.Close()
			return nil, err
		}
		out.Close()
		rc.Close()

		names = append(names, name)
	}

	return names, nil
}

// =============================================================================
// Initialization
// =============================================================================

func init() {
	// Placement command flags
	fabPlacement.Flags().StringVarP(&placementOutput, "output", "o", "", "Output ZIP path (default: <input>_placement.zip)")
	fabPlacement.Flags().StringVarP(&placementBoard, "board", "b", "", "Board name for labels")
	fabPlacement.Flags().StringVar(&placementPrefix, "prefix", "", "Prefix for output filenames (e.g., \"nRF54H20_V1.03\")")
	fabPlacement.Flags().StringVar(&placementOutline, "outline", "", "Gerber board outline file (.gko, .gm1, .gm, .gbr)")
	fabPlacement.Flags().StringVar(&placementGerbers, "gerbers", "", "Production gerbers zip (extracts panel outline from .gko)")
	fabPlacement.Flags().StringVar(&placementBOM, "bom", "", "BOM file for feeder assignment (.csv, .xlsx)")
	fabPlacement.Flags().Float64Var(&placementBoardWidth, "width", 0, "Board width in mm")
	fabPlacement.Flags().Float64Var(&placementBoardHeight, "height", 0, "Board height in mm")
	fabPlacement.Flags().IntVar(&placementRows, "rows", 1, "Panel rows")
	fabPlacement.Flags().IntVar(&placementCols, "cols", 1, "Panel columns")
	fabPlacement.Flags().StringVar(&placementAssemble, "assemble", "", "Panel positions to assemble (e.g., \"1,2,3,4,5\")")
	fabPlacement.Flags().StringVar(&placementSkip, "skip", "", "Panel positions to skip (e.g., \"6,7,8,9\")")
	fabPlacement.Flags().BoolVar(&placementRotateTop, "rotate-top", false, "Rotate top row 180 degrees")
	fabPlacement.Flags().StringVar(&placementSide, "side", "top", "Side to process: top, bottom, both")
	fabPlacement.Flags().StringVar(&placementFormat, "format", "", "Force format: kicad, altium, eagle, csv")
	fabPlacement.Flags().BoolVar(&placementSplitCSV, "split-csv", false, "Generate separate top/bottom CSV files")
	fabPlacement.Flags().StringVar(&placementManualPlace, "manual-place", "", "Comma-separated designator prefixes for manual placement (e.g., U,J,SW,MIC)")
	fabPlacement.Flags().StringVar(&placementMachine, "machine", "", "Machine format: yy1 for Neoden YY1")
	fabPlacement.Flags().StringVar(&placementFeederMap, "feeder-map", "", "Feeder map CSV to override auto-assigned feeder numbers")

	// Stackup command flags
	fabStackup.Flags().StringVarP(&stackupOutput, "output", "o", "", "Output PDF path (default: <prefix>_stackup.pdf or <input>_stackup.pdf)")
	fabStackup.Flags().StringVarP(&stackupBoardName, "board-name", "b", "", "Board name for page headers")
	fabStackup.Flags().StringVar(&stackupPrefix, "prefix", "", "Prefix for output filename")
	fabStackup.Flags().IntVar(&stackupScale, "scale", 1, "Scale ratio N:1 (e.g., 2 for 2:1, 3 for 3:1)")

	// Stackup diff command flags
	fabStackupDiff.Flags().StringVarP(&stackupDiffOutput, "output", "o", "", "Output PDF path (default: diff_<a>_vs_<b>.pdf)")
	fabStackupDiff.Flags().StringVar(&stackupDiffNameA, "name-a", "", "Label for revision A")
	fabStackupDiff.Flags().StringVar(&stackupDiffNameB, "name-b", "", "Label for revision B")
	fabStackupDiff.Flags().IntVar(&stackupDiffDPI, "dpi", 0, "Rasterisation DPI, 100–600 (default: 200)")

	// Testpoints command flags
	fabTestpoints.Flags().StringVarP(&testpointsOutput, "output", "o", ".", "Output directory")
	fabTestpoints.Flags().StringVarP(&testpointsBoard, "board", "b", "", "Board name for labels")
	fabTestpoints.Flags().StringVar(&testpointsPrefix, "prefix", "", "Prefix for output filenames")
	fabTestpoints.Flags().StringVar(&testpointsOutline, "outline", "", "Gerber board outline file")
	fabTestpoints.Flags().StringVar(&testpointsGerbers, "gerbers", "", "Production gerbers zip")
	fabTestpoints.Flags().StringVar(&testpointsBom, "bom", "", "BOM file for signal names")
	fabTestpoints.Flags().IntVar(&testpointsRows, "rows", 1, "Panel rows")
	fabTestpoints.Flags().IntVar(&testpointsCols, "cols", 1, "Panel columns")
	fabTestpoints.Flags().StringVar(&testpointsAssemble, "assemble", "", "Panel positions to assemble")
	fabTestpoints.Flags().StringVar(&testpointsSide, "side", "both", "Side: top, bottom, both")
	fabTestpoints.Flags().StringVar(&testpointsFormat, "format", "", "Force format: kicad, altium, eagle, csv")

	// Quote command flags
	fabQuote.Flags().IntVarP(&quoteQuantity, "quantity", "n", 5, "Number of boards")
	fabQuote.Flags().IntVar(&quoteLayers, "layers", 2, "Number of PCB layers")
	fabQuote.Flags().Float64Var(&quoteThickness, "thickness", 1.6, "Board thickness in mm")
	fabQuote.Flags().StringVar(&quoteSurfaceFinish, "surface-finish", "HASL", "Surface finish (HASL, ENIG, OSP)")
	fabQuote.Flags().StringVar(&quoteColor, "color", "green", "Solder mask color")
	fabQuote.Flags().StringVar(&quotePriority, "priority", "normal", "Priority level (low, normal, high)")
	fabQuote.Flags().StringVar(&quoteBom, "bom", "", "BOM file path for assembly quote")
	fabQuote.Flags().BoolVar(&quoteAssembly, "assembly", false, "Include assembly cost (requires --bom)")

	// Release command flags
	fabRelease.Flags().StringVar(&releaseVersion, "version", "", "Version tag for the release")
	fabRelease.Flags().StringVar(&releaseNotes, "notes", "", "Release notes")
	fabRelease.Flags().BoolVar(&releaseBOM, "bom", false, "Include BOM in release package")
	fabRelease.Flags().BoolVar(&releaseAsm, "assembly", false, "Include assembly files in release package")
	fabRelease.Flags().StringVarP(&releaseOutput, "output", "o", "", "Output directory for downloaded package")

	// Add all subcommands to Fab
	Fab.AddCommand(fabPlacement)
	Fab.AddCommand(fabStackup)
	Fab.AddCommand(fabStackupDiff)
	Fab.AddCommand(fabTestpoints)
	Fab.AddCommand(fabQuote)
	Fab.AddCommand(fabRelease)
}
