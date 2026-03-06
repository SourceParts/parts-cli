package commands

import (
	"context"
	"os"

	"github.com/SourceParts/parts-cli/internal/api"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// =============================================================================
// Part Operations
// =============================================================================

var Add = &cobra.Command{
	Use:     "add <part-number>",
	Short:   "Add a part to the database",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` add STM32F407VGT6`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Add(ctx, args[0], os.Stdout)
	},
}

var Search = &cobra.Command{
	Use:     "search <query>",
	Short:   "Search for parts",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` search "STM32F4"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Search(ctx, args[0], os.Stdout)
	},
}

var Datasheet = &cobra.Command{
	Use:     "datasheet <part-number>",
	Short:   "Get datasheet for a part",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` datasheet STM32F407VGT6`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Datasheet(ctx, args[0], os.Stdout)
	},
}

var Marking = &cobra.Command{
	Use:     "marking <part-number>",
	Short:   "Get marking information for a part",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` marking STM32F407VGT6`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Marking(ctx, args[0], os.Stdout)
	},
}

var Gather = &cobra.Command{
	Use:     "gather <part-number>",
	Short:   "Gather comprehensive information about a part",
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` gather STM32F407VGT6`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Gather(ctx, args[0], os.Stdout)
	},
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
	Example: domain.BinaryName + ` bom upload assembly.xlsx`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		projectID, _ := cmd.Flags().GetString("project")
		opts := api.BOMUploadOptions{
			ProjectID:   projectID,
			ExtractLCSC: true,
		}
		return Client.BOMUpload(ctx, args[0], opts, os.Stdout)
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
		return Client.BOMStatus(ctx, args[0], os.Stdout)
	},
}

func init() {
	bomUpload.Flags().StringP("project", "p", "", "Project ID to associate BOM with")
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
		return Client.ProjectCreate(ctx, args[0], description, os.Stdout)
	},
}

func init() {
	projectCreate.Flags().StringP("description", "d", "", "Project description")
	Project.AddCommand(projectCreate)
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

var Stackup = &cobra.Command{
	Use:   "stackup",
	Short: "PCB stackup operations",
	Long:  `Generate and manage PCB stackup documentation and diffs.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
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

func init() {
	DFM.Flags().StringP("project", "p", "", "Project ID")
	Fabricate.Flags().StringP("project", "p", "", "Project ID")
	Fabricate.Flags().IntP("quantity", "q", 5, "Quantity to order")
	Fabricate.AddCommand(Stackup)
	AOI.Flags().StringP("project", "p", "", "Project ID")
	QC.Flags().StringP("project", "p", "", "Project ID")
	Publish.Flags().StringP("project", "p", "", "Project ID")
	Publish.Flags().StringP("version", "V", "", "Version string")
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

var Init = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new parts project",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		return Client.Init(ctx, os.Stdout)
	},
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
		return Client.Release(ctx, args[0], os.Stdout)
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
