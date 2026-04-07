package commands

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// =============================================================================
// Supply Chain — AOI-style operator-approved procurement, AVL, obsolescence
// =============================================================================

var SupplyChain = &cobra.Command{
	Use:   "supply-chain",
	Short: "Supply chain pipeline (procurement, AVL, obsolescence)",
	Long: `AOI-style operator-approved supply chain pipeline.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. procurement approve    — group BOM by vendor, check MOQs, price breaks
  2. avl qualify            — check components against AVL rules + counterfeit risk
  3. obsolescence check     — lifecycle status + alternative suggestions`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var scProcurement = &cobra.Command{
	Use:   "procurement",
	Short: "Procurement operations (approve)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var scAVL = &cobra.Command{
	Use:   "avl",
	Short: "AVL operations (qualify)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var scObsolescence = &cobra.Command{
	Use:   "obsolescence",
	Short: "Obsolescence operations (check)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// --- Station 1: Procurement Approve ---

var scProcurementApprove = &cobra.Command{
	Use:   "approve <bom.csv>",
	Short: "Group BOM by vendor, check MOQs, calculate price breaks",
	Long: `Upload a BOM file (.csv or .json) to the API, group components by vendor,
validate minimum order quantities, apply price-break discounts, and estimate
lead times for each purchase order.

Review the purchase orders before placing with vendors.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		quantity, _ := cmd.Flags().GetInt("quantity")
		targetDate, _ := cmd.Flags().GetString("target-date")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if quantity <= 0 {
			return fmt.Errorf("--quantity must be a positive integer")
		}
		if targetDate == "" {
			return fmt.Errorf("--target-date is required (e.g. 2026-04-15)")
		}

		fmt.Printf("Building procurement plan for %d units from %s (target: %s)...\n",
			quantity, filepath.Base(bomPath), targetDate)

		// Upload BOM as multipart
		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.WriteField("quantity", fmt.Sprintf("%d", quantity))
		writer.WriteField("target_date", targetDate)
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/supply-chain/procurement/approve", domain.API)
		req, err := http.NewRequest("POST", url, &requestBody)
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		respBody, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
		}

		var result map[string]interface{}
		json.Unmarshal(respBody, &result)

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nBuild Quantity: %v\n", result["build_quantity"])
		fmt.Printf("Target Date:   %v\n", result["target_date"])
		fmt.Printf("Components:    %v\n", result["component_count"])
		fmt.Printf("Vendor POs:    %v\n", result["purchase_order_count"])
		fmt.Printf("\n  Total Cost:        $%.2f\n", toFloat(result["total_cost"]))
		fmt.Printf("  Longest Lead Time: %v days\n", result["longest_lead_time"])

		if pos, ok := result["purchase_orders"].([]interface{}); ok {
			for i, po := range pos {
				if m, ok := po.(map[string]interface{}); ok {
					fmt.Printf("\n  PO #%d: %v\n", i+1, m["vendor_name"])
					fmt.Printf("    Items:     %v\n", len(m["items"].([]interface{})))
					fmt.Printf("    Subtotal:  $%.2f\n", toFloat(m["subtotal"]))
					fmt.Printf("    Lead Time: %v days\n", m["lead_time_days"])
				}
			}
		}

		fmt.Println("\nNext: parts supply-chain avl qualify <bom.csv>")
		return nil
	},
}

// --- Station 2: AVL Qualify ---

var scAVLQualify = &cobra.Command{
	Use:   "qualify <bom.csv>",
	Short: "Check components against AVL rules and counterfeit risk",
	Long: `Upload a BOM file (.csv or .json) to the API and check each component
against the Approved Vendor List (AVL): authorized distributors, source
control requirements, and counterfeit risk scoring.

Review flagged components before proceeding with procurement.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Qualifying AVL for %s...\n", filepath.Base(bomPath))

		// Upload BOM as multipart
		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/supply-chain/avl/qualify", domain.API)
		req, err := http.NewRequest("POST", url, &requestBody)
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		respBody, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
		}

		var result map[string]interface{}
		json.Unmarshal(respBody, &result)

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		approved := result["approved_count"]
		flagged := result["flagged_count"]
		rejected := result["rejected_count"]

		fmt.Printf("\nComponents: %v\n", result["component_count"])
		fmt.Printf("  Approved: %v\n", approved)
		fmt.Printf("  Flagged:  %v\n", flagged)
		fmt.Printf("  Rejected: %v\n", rejected)

		if comps, ok := result["components"].([]interface{}); ok {
			for _, comp := range comps {
				if m, ok := comp.(map[string]interface{}); ok {
					status, _ := m["status"].(string)
					if status == "flagged" || status == "rejected" {
						fmt.Printf("\n  [%s] %v (%v) — risk score: %v\n",
							statusIcon(status), m["mpn"], m["reference"], m["risk_score"])
						if notes, ok := m["notes"].([]interface{}); ok {
							for _, n := range notes {
								fmt.Printf("    - %v\n", n)
							}
						}
					}
				}
			}
		}

		fmt.Println("\nNext: parts supply-chain obsolescence check <bom.csv>")
		return nil
	},
}

// --- Station 3: Obsolescence Check ---

var scObsolescenceCheck = &cobra.Command{
	Use:   "check <bom.csv>",
	Short: "Check lifecycle status and suggest alternatives for at-risk parts",
	Long: `Upload a BOM file (.csv or .json) to the API and check lifecycle status
for each component: active, NRND, obsolete, EOL, or unknown.
Suggests alternatives for at-risk parts.

Review at-risk components before design freeze.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Checking obsolescence for %s...\n", filepath.Base(bomPath))

		// Upload BOM as multipart
		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/supply-chain/obsolescence/check", domain.API)
		req, err := http.NewRequest("POST", url, &requestBody)
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		respBody, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
		}

		var result map[string]interface{}
		json.Unmarshal(respBody, &result)

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nComponents: %v\n", result["component_count"])
		fmt.Printf("  Active:   %v\n", result["active_count"])
		fmt.Printf("  At Risk:  %v\n", result["at_risk_count"])

		if comps, ok := result["components"].([]interface{}); ok {
			for _, comp := range comps {
				if m, ok := comp.(map[string]interface{}); ok {
					status, _ := m["lifecycle_status"].(string)
					if status != "active" && status != "" {
						fmt.Printf("\n  [%s] %v (%v) — %s, %v years active\n",
							lifecycleIcon(status), m["mpn"], m["reference"],
							statusLabel(status), m["years_active"])
						if alt, ok := m["alternative_mpn"].(string); ok && alt != "" {
							fmt.Printf("    Alternative: %s\n", alt)
						}
					}
				}
			}
		}

		if recs, ok := result["recommendations"].([]interface{}); ok && len(recs) > 0 {
			fmt.Println("\nRecommendations:")
			for _, r := range recs {
				fmt.Printf("  - %v\n", r)
			}
		}

		fmt.Println("\nObsolescence check complete.")
		return nil
	},
}

// statusIcon returns a visual indicator for AVL status.
func statusIcon(status string) string {
	switch status {
	case "approved":
		return "OK"
	case "flagged":
		return "!!"
	case "rejected":
		return "XX"
	default:
		return "??"
	}
}

// lifecycleIcon returns a visual indicator for lifecycle status.
func lifecycleIcon(status string) string {
	switch status {
	case "active":
		return "OK"
	case "nrnd":
		return "!!"
	case "eol":
		return "!!"
	case "obsolete":
		return "XX"
	default:
		return "??"
	}
}

// statusLabel returns a human-readable lifecycle label.
func statusLabel(status string) string {
	switch status {
	case "active":
		return "Active"
	case "nrnd":
		return "Not Recommended for New Designs"
	case "eol":
		return "End of Life"
	case "obsolete":
		return "Obsolete"
	default:
		return "Unknown"
	}
}

func init() {
	// Procurement approve flags
	scProcurementApprove.Flags().IntP("quantity", "n", 0, "Build quantity (required)")
	scProcurementApprove.Flags().String("target-date", "", "Target delivery date ISO 8601 (required)")
	scProcurementApprove.Flags().BoolP("json", "j", false, "Output raw JSON")

	// AVL qualify flags
	scAVLQualify.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Obsolescence check flags
	scObsolescenceCheck.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	scProcurement.AddCommand(scProcurementApprove)
	scAVL.AddCommand(scAVLQualify)
	scObsolescence.AddCommand(scObsolescenceCheck)

	SupplyChain.AddCommand(scProcurement)
	SupplyChain.AddCommand(scAVL)
	SupplyChain.AddCommand(scObsolescence)
}
