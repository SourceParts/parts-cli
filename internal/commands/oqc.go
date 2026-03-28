package commands

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var (
	oqcAssembly    string
	oqcBoard       string
	oqcProject     string
	oqcStatus      string
	oqcTracking    string
	oqcNotes       string
)

// OQC is the parent command for outgoing quality control.
var OQC = &cobra.Command{
	Use:   "oqc",
	Short: "Outgoing Quality Control",
	Long: `Inspect finished products/assemblies before shipping.
Upload photos, auto-match to incoming IQC parts, track shipments.

Examples:
  parts oqc upload photo.jpg --assembly "PocketPC v2.2" --board PP-A64-06958EE5
  parts oqc list --status passed
  parts oqc match OQ-ABC789
  parts oqc ship OQ-ABC789 --tracking 1Z999AA10123456784`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var oqcUpload = &cobra.Command{
	Use:   "upload <image>",
	Short: "Create OQC inspection with photo",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		defer cancel()

		url := "https://api.source.parts/v1/quality/oqc"
		fields := map[string]string{}
		if oqcAssembly != "" {
			fields["assembly_name"] = oqcAssembly
		}
		if oqcBoard != "" {
			fields["board_serial"] = oqcBoard
		}
		if oqcProject != "" {
			fields["project_id"] = oqcProject
		}
		if oqcNotes != "" {
			fields["notes"] = oqcNotes
		}

		return Client.EDAUpload(ctx, url, args[0], fields, nil, os.Stdout)
	},
}

var oqcList = &cobra.Command{
	Use:   "list",
	Short: "List OQC inspections",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		url := "https://api.source.parts/v1/quality/oqc"
		params := []string{}
		if oqcStatus != "" {
			params = append(params, "status="+oqcStatus)
		}
		if oqcProject != "" {
			params = append(params, "project_id="+oqcProject)
		}
		if oqcBoard != "" {
			params = append(params, "board_serial="+oqcBoard)
		}
		if len(params) > 0 {
			url += "?" + strings.Join(params, "&")
		}

		return Client.RawGet(ctx, url, os.Stdout)
	},
}

var oqcGet = &cobra.Command{
	Use:   "get <short-code>",
	Short: "Get OQC inspection details",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		url := fmt.Sprintf("https://api.source.parts/v1/quality/oqc/%s", args[0])
		return Client.RawGet(ctx, url, os.Stdout)
	},
}

var oqcMatch = &cobra.Command{
	Use:   "match <short-code>",
	Short: "Auto-match OQC to IQC parts",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()

		url := fmt.Sprintf("https://api.source.parts/v1/quality/oqc/%s/match", args[0])
		return Client.RawGet(ctx, url, os.Stdout)
	},
}

var oqcShip = &cobra.Command{
	Use:   "ship <short-code>",
	Short: "Mark OQC as shipped",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if oqcTracking == "" {
			return fmt.Errorf("--tracking is required")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		url := fmt.Sprintf("https://api.source.parts/v1/quality/oqc/%s", args[0])
		body := fmt.Sprintf(`{"tracking_number":"%s"}`, oqcTracking)
		return Client.RawPatch(ctx, url, body, os.Stdout)
	},
}

func init() {
	oqcUpload.Flags().StringVar(&oqcAssembly, "assembly", "", "Assembly name (e.g., PocketPC v2.2)")
	oqcUpload.Flags().StringVar(&oqcBoard, "board", "", "Board serial (e.g., PP-A64-06958EE5)")
	oqcUpload.Flags().StringVar(&oqcProject, "project", "", "Project ID")
	oqcUpload.Flags().StringVar(&oqcNotes, "notes", "", "Inspector notes")

	oqcList.Flags().StringVar(&oqcStatus, "status", "", "Filter by status")
	oqcList.Flags().StringVar(&oqcProject, "project", "", "Filter by project")
	oqcList.Flags().StringVar(&oqcBoard, "board", "", "Filter by board serial")

	oqcShip.Flags().StringVar(&oqcTracking, "tracking", "", "Tracking number (required)")

	OQC.AddCommand(oqcUpload)
	OQC.AddCommand(oqcList)
	OQC.AddCommand(oqcGet)
	OQC.AddCommand(oqcMatch)
	OQC.AddCommand(oqcShip)
}
