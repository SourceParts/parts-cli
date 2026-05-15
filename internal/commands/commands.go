package commands

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/templates"
	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/spf13/cobra"
)

// =============================================================================
// Part Operations
// =============================================================================

var Add = &cobra.Command{
	Use:   "add <part-number>",
	Short: "Add a part to the database",
	Args:  cobra.ExactArgs(1),
	Example: domain.BinaryName + ` add STM32F407VGT6
` + domain.BinaryName + ` add STM32F407VGT6 --manufacturer STMicroelectronics --category Microcontrollers
` + domain.BinaryName + ` add RC0603FR-0710KL --value 10k --package 0603`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		manufacturer, _ := cmd.Flags().GetString("manufacturer")
		description, _ := cmd.Flags().GetString("description")
		category, _ := cmd.Flags().GetString("category")
		pkg, _ := cmd.Flags().GetString("package")
		value, _ := cmd.Flags().GetString("value")
		opts := types.AddOptions{
			Manufacturer: manufacturer,
			Description:  description,
			Category:     category,
			Package:      pkg,
			Value:        value,
		}
		jsonOutput, _ := cmd.Flags().GetBool("json")
		var buf bytes.Buffer
		if err := Client.Add(ctx, args[0], opts, &buf); err != nil {
			return err
		}
		Render(buf.Bytes(), jsonOutput, "Added part")
		return nil
	},
}

func init() {
	Add.Flags().StringP("manufacturer", "m", "", "Manufacturer name")
	Add.Flags().StringP("description", "d", "", "Part description")
	Add.Flags().StringP("category", "c", "", "Part category")
	Add.Flags().String("package", "", "Package/footprint (e.g., 0603, LQFP100)")
	Add.Flags().String("value", "", "Component value (e.g., 10k, 100nF)")
	Add.Flags().Bool("json", false, "Output raw JSON")
}

var Search = &cobra.Command{
	Use:     "search <query>",
	Short:   "Search for parts",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` search "STM32F4" --in-stock --eu-only`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		inStock, _ := cmd.Flags().GetBool("in-stock")
		euOnly, _ := cmd.Flags().GetBool("eu-only")
		usOnly, _ := cmd.Flags().GetBool("us-only")
		cnOnly, _ := cmd.Flags().GetBool("cn-only")
		limit, _ := cmd.Flags().GetInt("limit")
		jsonOutput, _ := cmd.Flags().GetBool("json")
		opts := types.SearchOptions{
			InStock: inStock,
			EUOnly:  euOnly,
			USOnly:  usOnly,
			CNOnly:  cnOnly,
			Limit:   limit,
		}
		var buf bytes.Buffer
		if err := Client.Search(ctx, args[0], opts, &buf); err != nil {
			return err
		}
		data, err := io.ReadAll(&buf)
		if err != nil {
			return fmt.Errorf("error reading response: %w", err)
		}
		if jsonOutput {
			os.Stdout.Write(data)
			fmt.Println()
			return nil
		}
		printSearchResultsPublic(data)
		return nil
	},
}

func init() {
	Search.Flags().Bool("in-stock", false, "Only show parts that are in stock")
	Search.Flags().Bool("eu-only", false, "Only show parts from EU warehouses")
	Search.Flags().Bool("us-only", false, "Only show parts from US warehouses")
	Search.Flags().Bool("cn-only", false, "Only show parts from China warehouses")
	Search.Flags().IntP("limit", "l", 25, "Maximum number of results")
	Search.Flags().Bool("json", false, "Output raw JSON")
}

var Marking = &cobra.Command{
	Use:     "marking <part-number>",
	Short:   "Get marking information for a part",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` marking STM32F407VGT6`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		jsonOutput, _ := cmd.Flags().GetBool("json")
		var buf bytes.Buffer
		if err := Client.Marking(ctx, args[0], &buf); err != nil {
			return err
		}
		Render(buf.Bytes(), jsonOutput, "Marking")
		return nil
	},
}

var Gather = &cobra.Command{
	Use:     "gather <part-number>",
	Short:   "Gather comprehensive information about a part",
	Long: `Fetch all available data for a part in a single request: details,
datasheet, pricing, and alternatives.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` gather STM32F411CEU6
` + domain.BinaryName + ` gather STM32F411CEU6 --everything`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		jsonOutput, _ := cmd.Flags().GetBool("json")
		var buf bytes.Buffer
		if err := Client.Gather(ctx, args[0], &buf); err != nil {
			return err
		}
		Render(buf.Bytes(), jsonOutput, "")
		return nil
	},
}

func init() {
	Gather.Flags().Bool("everything", false, "Include all available data (default behavior)")
	Gather.Flags().Bool("json", false, "Output raw JSON")
	Marking.Flags().Bool("json", false, "Output raw JSON")
}

// =============================================================================
// BOM Operations
// =============================================================================

var BOM = &cobra.Command{
	Use:   "bom",
	Short: "BOM (Bill of Materials) operations",
	Long:  `Upload, validate, and manage Bills of Materials.`,
}

var bomUpload = &cobra.Command{
	Use:     "upload <file>",
	Short:   "Upload a BOM file for processing",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` bom upload assembly.xlsx --dfm-check`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		dfmCheck, _ := cmd.Flags().GetBool("dfm-check")
		opts := types.BOMUploadOptions{
			ProjectID:   projectID,
			ExtractLCSC: true,
			DFMCheck:    dfmCheck,
		}
		jsonOutput, _ := cmd.Flags().GetBool("json")

		var uploadBuf bytes.Buffer
		if err := Client.BOMUpload(ctx, args[0], opts, &uploadBuf); err != nil {
			return err
		}

		if !dfmCheck {
			Render(uploadBuf.Bytes(), jsonOutput, "BOM upload")
			return nil
		}

		// Upload BOM, poll for completion, then submit DFM
		Render(uploadBuf.Bytes(), jsonOutput, "BOM upload")

		var uploadResp types.BOMUploadResponse
		if err := json.Unmarshal(uploadBuf.Bytes(), &uploadResp); err != nil {
			return fmt.Errorf("failed to parse upload response: %w", err)
		}

		if uploadResp.JobID == "" {
			return fmt.Errorf("no job ID in upload response — cannot poll for completion")
		}

		fmt.Fprintf(os.Stdout, "\nPolling BOM job %s...\n", uploadResp.JobID)
		var statusBuf bytes.Buffer
		if err := Client.PollBOMStatus(ctx, uploadResp.JobID, &statusBuf); err != nil {
			return err
		}

		var statusResp types.BOMStatusResponse
		if err := json.Unmarshal(statusBuf.Bytes(), &statusResp); err != nil {
			return fmt.Errorf("failed to parse status response: %w", err)
		}

		bomID := statusResp.JobID
		fmt.Fprintf(os.Stdout, "\nSubmitting DFM analysis for BOM %s...\n", bomID)
		return Client.DFMSubmit(ctx, bomID, projectID, os.Stdout)
	},
}

var bomStatus = &cobra.Command{
	Use:     "status <job-id>",
	Short:   "Check BOM processing status",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` bom status job_abc123`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		jsonOutput, _ := cmd.Flags().GetBool("json")
		var buf bytes.Buffer
		if err := Client.BOMStatus(ctx, args[0], &buf); err != nil {
			return err
		}
		Render(buf.Bytes(), jsonOutput, "BOM status")
		return nil
	},
}

func init() {
	bomUpload.Flags().StringP("project", "p", "", "Project ID to associate BOM with")
	bomUpload.Flags().Bool("dfm-check", false, "Run DFM analysis after BOM processing completes")
	bomUpload.Flags().Bool("json", false, "Output raw JSON")
	bomStatus.Flags().Bool("json", false, "Output raw JSON")
	BOM.AddCommand(bomUpload)
	BOM.AddCommand(bomStatus)
}

// =============================================================================
// Project Operations
// =============================================================================

var Project = &cobra.Command{
	Use:   "project",
	Short: "Project management operations",
	Long:  `Create and manage hardware projects.`,
}

var projectCreate = &cobra.Command{
	Use:     "create <name>",
	Short:   "Create a new project",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` project create "My Project" --description "A new project"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		description, _ := cmd.Flags().GetString("description")
		jsonOutput, _ := cmd.Flags().GetBool("json")

		var buf bytes.Buffer
		if err := Client.ProjectCreate(ctx, args[0], description, &buf); err != nil {
			return err
		}
		data, err := io.ReadAll(&buf)
		if err != nil {
			return fmt.Errorf("error reading response: %w", err)
		}
		if jsonOutput {
			os.Stdout.Write(data)
			fmt.Println()
			return nil
		}
		printProjectCreateResultPublic(data)
		return nil
	},
}

var projectList = &cobra.Command{
	Use:     "list",
	Aliases: []string{"ls"},
	Short:   "List your projects",
	Long:    `List all projects for the authenticated user.`,
	Args:    cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		limit, _ := cmd.Flags().GetInt("limit")
		offset, _ := cmd.Flags().GetInt("offset")
		status, _ := cmd.Flags().GetString("status")
		opts := types.ProjectListOptions{
			Limit:  limit,
			Offset: offset,
			Status: status,
		}
		return Client.ProjectList(ctx, opts, os.Stdout)
	},
	Example: domain.BinaryName + ` project list
` + domain.BinaryName + ` project ls --limit 10
` + domain.BinaryName + ` project list --status active`,
}

var projectGet = &cobra.Command{
	Use:     "get <project-id>",
	Aliases: []string{"show", "info"},
	Short:   "Get project details",
	Long:    `Get detailed information about a specific project by its ID.`,
	Args:    cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.ProjectGet(ctx, args[0], os.Stdout)
	},
	Example: domain.BinaryName + ` project get proj_abc123
` + domain.BinaryName + ` project show proj_abc123`,
}

var projectDelete = &cobra.Command{
	Use:   "delete <project-id>",
	Short: "Delete a project",
	Long: `Delete a project permanently. This cannot be undone.

You will be prompted for confirmation unless --yes is specified.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID := args[0]
		yes, _ := cmd.Flags().GetBool("yes")
		if !yes {
			fmt.Printf("Delete project %s? This cannot be undone. [y/N] ", projectID)
			var input string
			fmt.Scanln(&input)
			input = strings.TrimSpace(strings.ToLower(input))
			if input != "y" && input != "yes" {
				fmt.Println("Cancelled.")
				return nil
			}
		}
		return Client.ProjectDelete(ctx, projectID, os.Stdout)
	},
	Example: domain.BinaryName + ` project delete proj_abc123
` + domain.BinaryName + ` project delete proj_abc123 --yes`,
}

var projectECO = &cobra.Command{
	Use:   "eco <project-id>",
	Short: "Create an Engineering Change Order",
	Long: `Create an Engineering Change Order (ECO) for a project.

An ECO tracks changes to a project's design, such as part substitutions,
reference designator updates, or other modifications.

The --changes flag accepts a path to a JSON file containing an array of
change objects.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		title, _ := cmd.Flags().GetString("title")
		description, _ := cmd.Flags().GetString("description")
		changesFile, _ := cmd.Flags().GetString("changes")

		ecoData := types.ECORequest{
			Title:       title,
			Description: description,
		}

		if changesFile != "" {
			data, err := os.ReadFile(changesFile)
			if err != nil {
				return fmt.Errorf("failed to read changes file: %w", err)
			}
			var changes []any
			if err := json.Unmarshal(data, &changes); err != nil {
				return fmt.Errorf("invalid changes JSON: %w", err)
			}
			ecoData.Changes = changes
		}

		jsonOutput, _ := cmd.Flags().GetBool("json")
		var buf bytes.Buffer
		if err := Client.ProjectECO(ctx, args[0], ecoData, &buf); err != nil {
			return err
		}
		Render(buf.Bytes(), jsonOutput, "ECO created")
		return nil
	},
	Example: domain.BinaryName + ` project eco proj_abc123 --title "Update capacitors"
` + domain.BinaryName + ` project eco proj_abc123 --title "BOM revision" --changes changes.json`,
}

var projectTransfer = &cobra.Command{
	Use:   "transfer <project-id>",
	Short: "Transfer project ownership",
	Long: `Transfer ownership of a project to another user by email address.

This is irreversible — the new owner will have full control of the project
and you will lose access. You will be prompted for confirmation unless
--yes is specified.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID := args[0]
		email, _ := cmd.Flags().GetString("email")
		if email == "" {
			return fmt.Errorf("--email is required")
		}
		yes, _ := cmd.Flags().GetBool("yes")

		if !yes {
			// Fetch project details to show what's being transferred
			var buf bytes.Buffer
			if err := Client.ProjectGet(ctx, projectID, &buf); err != nil {
				return fmt.Errorf("failed to look up project: %w", err)
			}
			fmt.Print(buf.String())
			fmt.Println()
			fmt.Printf("Transfer this project to %s?\n", email)
			fmt.Printf("This is irreversible — you will lose ownership. [y/N] ")
			var input string
			fmt.Scanln(&input)
			input = strings.TrimSpace(strings.ToLower(input))
			if input != "y" && input != "yes" {
				fmt.Println("Cancelled.")
				return nil
			}
		}

		jsonOutput, _ := cmd.Flags().GetBool("json")
		var buf bytes.Buffer
		if err := Client.ProjectTransfer(ctx, projectID, email, &buf); err != nil {
			return err
		}
		Render(buf.Bytes(), jsonOutput, "Transfer complete")
		return nil
	},
	Example: domain.BinaryName + ` project transfer proj_abc123 --email user@example.com
` + domain.BinaryName + ` project transfer proj_abc123 --email user@example.com --yes`,
}

func init() {
	projectCreate.Flags().StringP("description", "d", "", "Project description")
	projectCreate.Flags().Bool("json", false, "Output raw JSON")
	projectList.Flags().Int("limit", 20, "Maximum number of results")
	projectList.Flags().Int("offset", 0, "Number of results to skip")
	projectList.Flags().String("status", "", "Filter by status (active, archived)")
	projectDelete.Flags().BoolP("yes", "y", false, "Skip confirmation prompt")
	projectECO.Flags().String("title", "", "ECO title (required)")
	projectECO.Flags().String("description", "", "ECO description")
	projectECO.Flags().String("changes", "", "Path to JSON file with changes array")
	projectECO.Flags().Bool("json", false, "Output raw JSON")
	projectECO.MarkFlagRequired("title")
	projectTransfer.Flags().String("email", "", "Email of new owner (required)")
	projectTransfer.Flags().Bool("json", false, "Output raw JSON")
	projectTransfer.Flags().BoolP("yes", "y", false, "Skip confirmation prompt")
	projectTransfer.MarkFlagRequired("email")
	Project.AddCommand(projectCreate)
	Project.AddCommand(projectList)
	Project.AddCommand(projectGet)
	Project.AddCommand(projectDelete)
	Project.AddCommand(projectECO)
	Project.AddCommand(projectTransfer)
}

// =============================================================================
// Manufacturing Commands
// =============================================================================

var DFM = &cobra.Command{
	Use:     "dfm",
	Short:   "Run DFM (Design for Manufacturing) analysis",
	Example: domain.BinaryName + ` dfm --project proj_123`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		return Client.DFM(ctx, projectID, os.Stdout)
	},
}

var Fabricate = &cobra.Command{
	Use:     "fab",
	Aliases: []string{"fabricate"},
	Short:   "Submit a fabrication order",
	Example: domain.BinaryName + ` fab --project proj_123 --quantity 10`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		return Client.Fabricate(ctx, projectID, os.Stdout)
	},
}

var AOI = &cobra.Command{
	Use:     "aoi",
	Short:   "Submit AOI (Automated Optical Inspection) request",
	Example: domain.BinaryName + ` aoi --project proj_123`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		return Client.AOI(ctx, projectID, os.Stdout)
	},
}

var QC = &cobra.Command{
	Use:     "qc",
	Short:   "Submit QC (Quality Control) check",
	Example: domain.BinaryName + ` qc --project proj_123`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		return Client.QC(ctx, projectID, os.Stdout)
	},
}

var Publish = &cobra.Command{
	Use:     "publish",
	Short:   "Publish a manufacturing package",
	Example: domain.BinaryName + ` publish --project proj_123 --version 1.0.0`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		return Client.Publish(ctx, projectID, os.Stdout)
	},
}

// =============================================================================
// Stackup Commands
// =============================================================================

var Stackup = &cobra.Command{
	Use:   "stackup",
	Short: "PCB stackup operations (PDF generation, revision diff)",
	Long:  `Generate stackup PDFs from gerber files or compare revisions with layer-by-layer diffs.`,
}

var stackupGenerate = &cobra.Command{
	Use:     "generate <gerber.zip>",
	Aliases: []string{"gen"},
	Short:   "Generate stackup PDF from gerber files",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` stackup generate board_v2.zip --name "My Board" --output stackup.pdf`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		name, _ := cmd.Flags().GetString("name")
		scale, _ := cmd.Flags().GetInt("scale")
		output, _ := cmd.Flags().GetString("output")
		opts := types.StackupOptions{
			BoardName: name,
			Scale:     scale,
			Output:    output,
		}
		return Client.Stackup(ctx, args[0], opts, os.Stdout)
	},
}

var stackupDiff = &cobra.Command{
	Use:     "diff <old.zip> <new.zip>",
	Short:   "Generate layer-by-layer diff PDF between two gerber revisions",
	Args:    cobra.ExactArgs(2),
	Example: domain.BinaryName + ` stackup diff board_v1.zip board_v2.zip --name-a "v1.0" --name-b "v2.0"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		nameA, _ := cmd.Flags().GetString("name-a")
		nameB, _ := cmd.Flags().GetString("name-b")
		dpi, _ := cmd.Flags().GetInt("dpi")
		output, _ := cmd.Flags().GetString("output")
		opts := types.StackupDiffOptions{
			NameA:  nameA,
			NameB:  nameB,
			DPI:    dpi,
			Output: output,
		}
		return Client.StackupDiff(ctx, args[0], args[1], opts, os.Stdout)
	},
}

func init() {
	DFM.Flags().StringP("project", "p", "", "Project ID")
	Fabricate.Flags().StringP("project", "p", "", "Project ID")
	Fabricate.Flags().IntP("quantity", "q", 5, "Quantity to order")
	Fabricate.AddCommand(Stackup)
	AOI.Flags().StringP("project", "p", "", "Project ID")
	QC.Flags().StringP("project", "p", "", "Project ID")
	Publish.Flags().StringP("project", "p", "", "Project ID")
	Publish.Flags().StringP("version", "V", "", "Version string")

	stackupGenerate.Flags().StringP("name", "n", "", "Board name for headers")
	stackupGenerate.Flags().IntP("scale", "s", 0, "Scale factor")
	stackupGenerate.Flags().StringP("output", "o", "", "Output PDF path")
	stackupDiff.Flags().String("name-a", "", "Label for first revision")
	stackupDiff.Flags().String("name-b", "", "Label for second revision")
	stackupDiff.Flags().Int("dpi", 0, "Rasterization DPI (100-600)")
	stackupDiff.Flags().StringP("output", "o", "", "Output PDF path")
	Stackup.AddCommand(stackupGenerate, stackupDiff)
}

// =============================================================================
// Supply Chain Commands
// =============================================================================

var Inventory = &cobra.Command{
	Use:   "inventory [part-number]",
	Short: "Check inventory levels",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		partNumber := ""
		if len(args) > 0 {
			partNumber = args[0]
		}
		return Client.Inventory(ctx, partNumber, os.Stdout)
	},
}

var Cart = &cobra.Command{
	Use:   "cart",
	Short: "View shopping cart",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Cart(ctx, os.Stdout)
	},
}

var Buy = &cobra.Command{
	Use:   "buy <part-number>",
	Short: "Purchase a part",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Buy(ctx, args[0], os.Stdout)
	},
}

var RFQ = &cobra.Command{
	Use:   "rfq <part-number>",
	Short: "Request for Quote",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.RFQ(ctx, args[0], os.Stdout)
	},
}

var Wishlist = &cobra.Command{
	Use:   "wishlist [part-number]",
	Short: "Manage wishlist",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		partNumber := ""
		if len(args) > 0 {
			partNumber = args[0]
		}
		return Client.Wishlist(ctx, partNumber, os.Stdout)
	},
}

var Tracker = &cobra.Command{
	Use:   "tracker <part-number>",
	Short: "Track price changes for a part",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Tracker(ctx, args[0], os.Stdout)
	},
}

var Box = &cobra.Command{
	Use:   "box <box-id>",
	Short: "Get box/order information",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Box(ctx, args[0], os.Stdout)
	},
}

// =============================================================================
// Cost Management Commands
// =============================================================================

var Balance = &cobra.Command{
	Use:   "balance",
	Short: "Check account balance",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Balance(ctx, os.Stdout)
	},
}

var COGs = &cobra.Command{
	Use:   "cogs <part-number>",
	Short: "Calculate Cost of Goods Sold",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.COGs(ctx, args[0], os.Stdout)
	},
}

var Expense = &cobra.Command{
	Use:   "expense",
	Short: "Record an expense",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Expense(ctx, "", os.Stdout)
	},
}

var Price = &cobra.Command{
	Use:     "price <part-number>",
	Short:   "Estimate pricing for a part",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` price "ESP32-S3" --quantity 100`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		quantity, _ := cmd.Flags().GetInt("quantity")
		currency, _ := cmd.Flags().GetString("currency")
		jsonOutput, _ := cmd.Flags().GetBool("json")
		opts := types.PriceOptions{
			Quantity: quantity,
			Currency: currency,
		}
		var buf bytes.Buffer
		if err := Client.Price(ctx, args[0], opts, &buf); err != nil {
			return err
		}
		data, err := io.ReadAll(&buf)
		if err != nil {
			return fmt.Errorf("error reading response: %w", err)
		}
		if jsonOutput {
			os.Stdout.Write(data)
			fmt.Println()
			return nil
		}
		printPriceResultsPublic(data)
		return nil
	},
}

func init() {
	Price.Flags().IntP("quantity", "n", 1, "Quantity to price")
	Price.Flags().StringP("currency", "c", "USD", "Currency code (USD, EUR, etc.)")
	Price.Flags().Bool("json", false, "Output raw JSON")
}

// =============================================================================
// Workflow Commands
// =============================================================================

var Note = &cobra.Command{
	Use:   "note <text>",
	Short: "Add a note",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Note(ctx, args[0], os.Stdout)
	},
}

var Todo = &cobra.Command{
	Use:   "todo <text>",
	Short: "Add a todo item",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Todo(ctx, args[0], os.Stdout)
	},
}

var Report = &cobra.Command{
	Use:   "report [type]",
	Short: "Generate a report",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		reportType := ""
		if len(args) > 0 {
			reportType = args[0]
		}
		return Client.Report(ctx, reportType, os.Stdout)
	},
}

// =============================================================================
// Local Commands
// =============================================================================

var (
	initRevision   string
	initNoGit      bool
	initKicad      bool
	initClientName string
)

var Init = &cobra.Command{
	Use:   "init [name]",
	Short: "Initialize a new parts project",
	Long: `Create a new hardware project with the standard Source Parts directory
structure, configuration files, and optional KiCad project scaffolding.

If [name] is omitted, the current directory name is used and the project
is initialized in place. If [name] is provided, a new directory is created.

Directory structure created:
  .parts/config.yaml   Project configuration
  PARTS.md             Project documentation
  LICENSE.md           License and copyright
  .gitignore           Git ignore rules
  ECO/                 Engineering Change Orders
  BOM/<rev>/           Bill of Materials
  PCB/<rev>/           PCB design files
  Datasheets/          Component datasheets
  IQC/                 Incoming Quality Control
  DFT/                 Design for Test
  DRC/                 Design Rule Check reports
  ERC/                 Electrical Rule Check reports
  SOP/                 Standard Operating Procedures
  Reports/             Analysis and review reports`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		return runInit(args, os.Stdout)
	},
	Example: domain.BinaryName + ` init
` + domain.BinaryName + ` init my-board
` + domain.BinaryName + ` init my-board --revision A --kicad`,
}

func init() {
	Init.Flags().StringVar(&initRevision, "revision", "A", "Initial revision letter")
	Init.Flags().BoolVar(&initNoGit, "no-git", false, "Skip git init")
	Init.Flags().BoolVar(&initKicad, "kicad", false, "Create KiCad project files")
	Init.Flags().StringVar(&initClientName, "client-name", "", "Client name for LICENSE.md copyright")
}

func runInit(args []string, w io.Writer) error {
	var dir string
	var name string
	inPlace := len(args) == 0

	if inPlace {
		cwd, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("failed to get working directory: %w", err)
		}
		dir = cwd
		name = filepath.Base(cwd)

		if _, err := os.Stat(filepath.Join(dir, ".parts")); err == nil {
			return fmt.Errorf("already a parts project (.parts/ exists)")
		}
	} else {
		name = args[0]
		dir = name

		if _, err := os.Stat(dir); err == nil {
			return fmt.Errorf("directory already exists: %s", dir)
		}
	}

	absPath, err := filepath.Abs(dir)
	if err != nil {
		return fmt.Errorf("resolving path: %w", err)
	}

	// Build metadata
	meta := templates.NewMetadata(name)
	meta.Revision = initRevision
	meta.KiCad = initKicad
	meta.ClientName = initClientName

	// Get the PCB template
	tmpl, err := templates.GetTemplate("pcb")
	if err != nil {
		return fmt.Errorf("failed to get template: %w", err)
	}

	// Generate project structure
	gen := templates.NewGenerator(tmpl, meta, dir)
	if err := gen.Generate(); err != nil {
		return fmt.Errorf("failed to generate project: %w", err)
	}

	// Git init
	if !initNoGit {
		gitCmd := exec.Command("git", "init", dir)
		if out, err := gitCmd.CombinedOutput(); err != nil {
			fmt.Fprintf(w, "Warning: git init failed: %s\n", strings.TrimSpace(string(out)))
		}
	}

	// Summary
	if inPlace {
		fmt.Fprintf(w, "Initialized parts project in %s\n", absPath)
	} else {
		fmt.Fprintf(w, "Created parts project: %s\n", absPath)
	}
	fmt.Fprintf(w, "  Revision:  %s\n", initRevision)
	fmt.Fprintf(w, "  Config:    .parts/config.yaml\n")
	if initKicad {
		fmt.Fprintf(w, "  KiCad:     PCB/%s/%s.kicad_pro\n", initRevision, name)
	}
	if !initNoGit {
		fmt.Fprintf(w, "  Git:       initialized\n")
	}

	return nil
}

var Log = &cobra.Command{
	Use:   "log",
	Short: "Show project history",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Log(ctx, "", os.Stdout)
	},
}

var Status = &cobra.Command{
	Use:   "status",
	Short: "Show project status",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Status(ctx, "", os.Stdout)
	},
}

var Clean = &cobra.Command{
	Use:   "clean",
	Short: "Clean project files",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Clean(ctx, os.Stdout)
	},
}

var Scan = &cobra.Command{
	Use:   "scan",
	Short: "Scan barcode or device",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Scan(ctx, os.Stdout)
	},
}

var Label = &cobra.Command{
	Use:   "label <part-number>",
	Short: "Generate label for a part",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Label(ctx, args[0], os.Stdout)
	},
}

var Detect = &cobra.Command{
	Use:   "detect <input>",
	Short: "Detect file type or part information",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Detect(ctx, args[0], os.Stdout)
	},
}

// =============================================================================
// Documentation Commands
// =============================================================================

var Guide = &cobra.Command{
	Use:   "guide [topic]",
	Short: "Show application guides",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		topic := ""
		if len(args) > 0 {
			topic = args[0]
		}
		return Client.Guide(ctx, topic, os.Stdout)
	},
}

var Docs = &cobra.Command{
	Use:   "docs [topic]",
	Short: "Show documentation",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		topic := ""
		if len(args) > 0 {
			topic = args[0]
		}
		return Client.Docs(ctx, topic, os.Stdout)
	},
}

// =============================================================================
// Version Control Commands
// =============================================================================

var Pull = &cobra.Command{
	Use:   "pull",
	Short: "Pull changes from remote",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Pull(ctx, "", os.Stdout)
	},
}

var Push = &cobra.Command{
	Use:   "push",
	Short: "Push changes to remote",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Push(ctx, "", os.Stdout)
	},
}

var Tag = &cobra.Command{
	Use:   "tag <name>",
	Short: "Create a tag",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Tag(ctx, args[0], os.Stdout)
	},
}

var Release = &cobra.Command{
	Use:   "release <version>",
	Short: "Create a release",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Release(ctx, args[0], types.ReleaseOptions{}, os.Stdout)
	},
}

var Test = &cobra.Command{
	Use:   "test",
	Short: "Run tests",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Test(ctx, "", os.Stdout)
	},
}

// =============================================================================
// Output Formatting
// =============================================================================

func printSearchResultsPublic(data []byte) {
	var resp types.SearchResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		os.Stdout.Write(data)
		fmt.Println()
		return
	}

	fmt.Printf("Search: %q (%d results)\n", resp.Data.Query, resp.Data.Total)

	if len(resp.Data.Parts) == 0 {
		fmt.Println("\n  No parts found.")
		return
	}

	fmt.Println()
	for _, p := range resp.Data.Parts {
		price := "—"
		if p.Price != nil && *p.Price != "" {
			price = "$" + *p.Price
		}
		fmt.Printf("  %-28s %s\n", p.Name, p.Manufacturer)
		fmt.Printf("    %s  %s  %s  Stock: %s\n\n", p.SKU, p.Category, price, fmtNumber(p.StockQuantity))
	}
}

func printProjectCreateResultPublic(data []byte) {
	var resp types.ProjectCreateResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		// Could not parse; surface the raw payload to stderr and stay silent
		// on stdout so callers piping output don't get malformed text.
		fmt.Fprintf(os.Stderr, "Warning: could not parse API response: %v\n%s\n", err, string(data))
		return
	}

	if resp.Error != "" {
		fmt.Fprintf(os.Stderr, "API error: %s\n", resp.Error)
		return
	}

	if resp.Data.ID != "" {
		fmt.Printf("Project created: %s (id: %s)\n", resp.Data.Name, resp.Data.ID)
	} else {
		fmt.Println("Project created")
	}
	if resp.Data.Message != "" {
		fmt.Println(resp.Data.Message)
	}
}

func printPriceResultsPublic(data []byte) {
	var resp types.PriceResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		os.Stdout.Write(data)
		fmt.Println()
		return
	}

	currency := resp.Data.Currency
	if currency == "" {
		currency = "USD"
	}

	fmt.Printf("Price Estimate (%s)\n\n", currency)

	for _, p := range resp.Data.Parts {
		avail := "unavailable"
		if p.Available {
			avail = "available"
		}
		fmt.Printf("  %-14s qty: %-6d $%.4f/ea    $%.2f    %s\n", p.PartNumber, p.Quantity, p.UnitPrice, p.Total, avail)
	}

	fmt.Printf("\nTotal: $%.2f\n", resp.Data.TotalEstimate)
}

func fmtNumber(n int) string {
	s := strconv.Itoa(n)
	if len(s) <= 3 {
		return s
	}
	var parts []string
	for len(s) > 3 {
		parts = append([]string{s[len(s)-3:]}, parts...)
		s = s[:len(s)-3]
	}
	parts = append([]string{s}, parts...)
	return strings.Join(parts, ",")
}
