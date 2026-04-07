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
// DFM — Design for Manufacturability Pipeline
// =============================================================================

// DFMPipeline is the parent command for the tiered DFM review pipeline.
// It replaces the previous simple DFM command with a subcommand structure.
var DFMPipeline = &cobra.Command{
	Use:   "dfm",
	Short: "DFM (Design for Manufacturability) review pipeline",
	Long: `DFM review pipeline — tiered design review service.

Submit design files for expert DFM review with automated complexity
scoring and professional report delivery.

Tiers:
  basic:         $97  (3-5 day turnaround, design file review, email response)
  comprehensive: $297 (1-2 day turnaround, detailed analysis, material recs)

Pipeline:
  1. estimate          — analyze complexity and get pricing
  2. submit            — submit for review with payment
  3. status            — check review progress
  4. findings add      — (admin) add review findings
  5. report generate   — (admin) generate PDF report + email
  6. report deliver    — (admin) re-send report`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// --- Estimate ---

var dfmEstimate = &cobra.Command{
	Use:   "estimate <design-file>",
	Short: "Analyze design file complexity and get DFM review pricing",
	Long: `Upload a design file (Gerber ZIP, .kicad_pcb, or CAD file) for
automated complexity analysis. Returns a complexity score (1-10),
layer count, component estimate, and pricing for each tier.

If --tier is not specified, the API auto-recommends based on complexity.`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` dfm estimate gerbers.zip
` + domain.BinaryName + ` dfm estimate board.kicad_pcb --tier comprehensive`,
	RunE: func(cmd *cobra.Command, args []string) error {
		filePath := args[0]
		tier, _ := cmd.Flags().GetString("tier")
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Analyzing design complexity for %s...\n", filepath.Base(filePath))

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", filePath); err != nil {
			return fmt.Errorf("failed to add design file: %w", err)
		}
		if tier != "" {
			writer.WriteField("tier", tier)
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/dfm/estimate", domain.API)
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

		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
		}

		var result map[string]interface{}
		json.Unmarshal(body, &result)

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nTier:          %v (%v)\n", result["tier"], result["tier_label"])
		fmt.Printf("Price:         $%.2f\n", toFloat(result["price"]))
		fmt.Printf("Turnaround:    %v business days\n", result["turnaround_days"])
		fmt.Printf("Complexity:    %.0f/10\n", toFloat(result["complexity_score"]))
		fmt.Printf("Layers:        %v\n", result["layer_count"])
		fmt.Printf("Components:    ~%v\n", result["component_estimate"])
		fmt.Printf("Board area:    %.1f mm2\n", toFloat(result["board_area_mm2"]))
		fmt.Printf("HDI:           %v\n", boolLabel(result["has_hdi"]))
		fmt.Printf("Blind/buried:  %v\n", boolLabel(result["has_blind_vias"]))

		if rec, ok := result["recommendation"].(string); ok && rec != "" {
			fmt.Printf("\n  %s\n", rec)
		}

		fmt.Println("\nNext: parts dfm submit <file> --tier basic --customer \"Name\" --email user@example.com")
		return nil
	},
}

// --- Submit ---

var dfmSubmit = &cobra.Command{
	Use:   "submit <design-file>",
	Short: "Submit a DFM review request with design files and customer info",
	Long: `Upload a design file and submit a DFM review request. Creates a
review request in the database and triggers a Stripe payment intent.

Promo codes: LAUNCH99 ($99 basic), PARTNER199 ($199 comprehensive)`,
	Args: cobra.ExactArgs(1),
	Example: domain.BinaryName + ` dfm submit gerbers.zip --tier basic --customer "Zach Eisenhauer" --email zach@example.com
` + domain.BinaryName + ` dfm submit board.kicad_pcb --tier comprehensive --customer "Josh" --email josh@example.com --promo PARTNER199`,
	RunE: func(cmd *cobra.Command, args []string) error {
		filePath := args[0]
		tier, _ := cmd.Flags().GetString("tier")
		customer, _ := cmd.Flags().GetString("customer")
		email, _ := cmd.Flags().GetString("email")
		promo, _ := cmd.Flags().GetString("promo")
		notes, _ := cmd.Flags().GetString("notes")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if tier == "" {
			return fmt.Errorf("--tier is required (basic or comprehensive)")
		}
		if customer == "" {
			return fmt.Errorf("--customer is required")
		}
		if email == "" {
			return fmt.Errorf("--email is required")
		}

		fmt.Printf("Submitting DFM review for %s (%s tier)...\n", filepath.Base(filePath), tier)

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", filePath); err != nil {
			return fmt.Errorf("failed to add design file: %w", err)
		}
		writer.WriteField("tier", tier)
		writer.WriteField("customer_name", customer)
		writer.WriteField("customer_email", email)
		if promo != "" {
			writer.WriteField("promo_code", promo)
		}
		if notes != "" {
			writer.WriteField("notes", notes)
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/dfm/submit", domain.API)
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

		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
		}

		var result map[string]interface{}
		json.Unmarshal(body, &result)

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nRequest ID:    %v\n", result["request_id"])
		fmt.Printf("Status:        %v\n", result["status"])
		fmt.Printf("Tier:          %v (${%.2f})\n", result["tier_label"], toFloat(result["price"]))
		fmt.Printf("Customer:      %v <%v>\n", result["customer_name"], result["customer_email"])
		fmt.Printf("Complexity:    %.0f/10\n", toFloat(result["complexity_score"]))
		fmt.Printf("Est. complete: %v\n", result["estimated_completion"])

		if promo, ok := result["promo_applied"].(string); ok && promo != "" {
			fmt.Printf("Promo applied: %s\n", promo)
		}
		if warn, ok := result["promo_warning"].(string); ok && warn != "" {
			fmt.Printf("Promo warning: %s\n", warn)
		}
		if payURL, ok := result["payment_url"].(string); ok && payURL != "" {
			fmt.Printf("\nPayment URL: %s\n", payURL)
		}

		fmt.Printf("\nNext: parts dfm status %v\n", result["request_id"])
		return nil
	},
}

// --- Status ---

var dfmStatus = &cobra.Command{
	Use:   "status <request-id>",
	Short: "Check the status of a DFM review request",
	Long: `Poll the current status of a DFM review request.

Status flow:
  submitted -> payment_pending -> in_review -> findings_ready ->
  report_sent -> complete`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` dfm status DFM-A1B2C3D4`,
	RunE: func(cmd *cobra.Command, args []string) error {
		requestID := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Checking status for %s...\n", requestID)

		url := fmt.Sprintf("https://%s/v1/dfm/status/%s", domain.API, requestID)
		req, err := http.NewRequest("GET", url, nil)
		if err != nil {
			return err
		}
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		if apiKey := Client.GetAPIKey(); apiKey != "" {
			req.Header.Set("X-API-Key", apiKey)
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
		}

		var result map[string]interface{}
		json.Unmarshal(body, &result)

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nRequest:       %v\n", result["request_id"])
		fmt.Printf("Status:        %v\n", result["status"])
		fmt.Printf("Progress:      %.0f%%\n", toFloat(result["progress"]))
		fmt.Printf("Findings:      %.0f\n", toFloat(result["findings_count"]))
		fmt.Printf("Est. complete: %v\n", result["estimated_completion"])

		return nil
	},
}

// --- Findings ---

var dfmFindings = &cobra.Command{
	Use:   "findings",
	Short: "Manage DFM review findings (admin)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var dfmFindingsAdd = &cobra.Command{
	Use:   "add <request-id>",
	Short: "Add a finding to a DFM review (admin)",
	Long: `Add a review finding to a DFM request. Each finding includes a
category, severity, description, recommendation, and affected area.

Severities: info, low, medium, high, critical`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` dfm findings add DFM-A1B2C3D4 --category design_issue --severity high --description "Trace width too narrow for current" --recommendation "Increase trace to 0.3mm" --area "U1 power input"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		requestID := args[0]
		category, _ := cmd.Flags().GetString("category")
		severity, _ := cmd.Flags().GetString("severity")
		description, _ := cmd.Flags().GetString("description")
		recommendation, _ := cmd.Flags().GetString("recommendation")
		area, _ := cmd.Flags().GetString("area")
		imageRef, _ := cmd.Flags().GetString("image-ref")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if category == "" {
			return fmt.Errorf("--category is required")
		}
		if severity == "" {
			return fmt.Errorf("--severity is required (info, low, medium, high, critical)")
		}
		if description == "" {
			return fmt.Errorf("--description is required")
		}
		if recommendation == "" {
			return fmt.Errorf("--recommendation is required")
		}
		if area == "" {
			return fmt.Errorf("--area is required")
		}

		fmt.Printf("Adding finding to %s...\n", requestID)

		finding := map[string]interface{}{
			"category":       category,
			"severity":       severity,
			"description":    description,
			"recommendation": recommendation,
			"affected_area":  area,
		}
		if imageRef != "" {
			finding["image_ref"] = imageRef
		}

		payload := map[string]interface{}{
			"findings": []interface{}{finding},
		}

		result, err := postJSONAndGetJSON(fmt.Sprintf("/v1/dfm/findings/%s", requestID), payload)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nRequest:    %v\n", result["request_id"])
		fmt.Printf("Added:      %.0f finding(s)\n", toFloat(result["findings_count"]))

		if findings, ok := result["findings"].([]interface{}); ok {
			for _, f := range findings {
				m := f.(map[string]interface{})
				fmt.Printf("  [%v] %v: %v\n",
					m["severity"], m["category"], m["description"])
			}
		}

		fmt.Printf("\nNext: parts dfm report generate %s\n", requestID)
		return nil
	},
}

// --- Report ---

var dfmReport = &cobra.Command{
	Use:   "report",
	Short: "Manage DFM review reports (admin)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var dfmReportGenerate = &cobra.Command{
	Use:   "generate <request-id>",
	Short: "Generate a PDF report and email it to the customer (admin)",
	Long: `Trigger PDF report generation from the review findings.
The report is uploaded to storage and emailed to the customer on file.

Ensure all findings have been added before generating.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` dfm report generate DFM-A1B2C3D4`,
	RunE: func(cmd *cobra.Command, args []string) error {
		requestID := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Generating DFM report for %s...\n", requestID)

		result, err := postJSONAndGetJSON(
			fmt.Sprintf("/v1/dfm/report/%s/generate", requestID),
			map[string]interface{}{},
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nRequest:    %v\n", result["request_id"])
		fmt.Printf("Report:     %v\n", result["report_url"])
		fmt.Printf("Email sent: %v\n", boolLabel(result["email_sent"]))
		fmt.Printf("Recipient:  %v\n", result["recipient"])

		fmt.Printf("\nNext: parts dfm report deliver %s --email alt@example.com\n", requestID)
		return nil
	},
}

var dfmReportDeliver = &cobra.Command{
	Use:   "deliver <request-id>",
	Short: "Re-send the DFM report to a specific email (admin)",
	Long: `Re-send the previously generated PDF report to the customer
or to an alternative email address with an optional custom message.`,
	Args:    cobra.ExactArgs(1),
	Example: domain.BinaryName + ` dfm report deliver DFM-A1B2C3D4 --email josh@example.com --message "Your DFM report is ready"`,
	RunE: func(cmd *cobra.Command, args []string) error {
		requestID := args[0]
		email, _ := cmd.Flags().GetString("email")
		message, _ := cmd.Flags().GetString("message")
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Delivering DFM report for %s...\n", requestID)

		payload := map[string]interface{}{}
		if email != "" {
			payload["email"] = email
		}
		if message != "" {
			payload["message"] = message
		}

		result, err := postJSONAndGetJSON(
			fmt.Sprintf("/v1/dfm/report/%s/deliver", requestID),
			payload,
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nRequest:    %v\n", result["request_id"])
		fmt.Printf("Report:     %v\n", result["report_url"])
		fmt.Printf("Email sent: %v\n", boolLabel(result["email_sent"]))
		fmt.Printf("Recipient:  %v\n", result["recipient"])
		if msg, ok := result["custom_message"].(string); ok && msg != "" {
			fmt.Printf("Message:    %s\n", msg)
		}

		return nil
	},
}

// boolLabel returns "yes" or "no" for a boolean interface value.
func boolLabel(v interface{}) string {
	if b, ok := v.(bool); ok && b {
		return "yes"
	}
	return "no"
}

func init() {
	// Estimate flags
	dfmEstimate.Flags().String("tier", "", "Review tier (basic or comprehensive)")
	dfmEstimate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Submit flags
	dfmSubmit.Flags().String("tier", "", "Review tier (basic or comprehensive) — required")
	dfmSubmit.Flags().String("customer", "", "Customer's full name — required")
	dfmSubmit.Flags().String("email", "", "Customer's email address — required")
	dfmSubmit.Flags().String("promo", "", "Promotional code (e.g. LAUNCH99, PARTNER199)")
	dfmSubmit.Flags().String("notes", "", "Additional notes or requirements")
	dfmSubmit.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Status flags
	dfmStatus.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Findings add flags
	dfmFindingsAdd.Flags().String("category", "", "Finding category (e.g. design_issue, manufacturability)")
	dfmFindingsAdd.Flags().String("severity", "", "Severity: info, low, medium, high, critical")
	dfmFindingsAdd.Flags().String("description", "", "Description of the issue")
	dfmFindingsAdd.Flags().String("recommendation", "", "Recommended fix")
	dfmFindingsAdd.Flags().String("area", "", "Affected area of the design")
	dfmFindingsAdd.Flags().String("image-ref", "", "Optional reference to annotated image")
	dfmFindingsAdd.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Report generate flags
	dfmReportGenerate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Report deliver flags
	dfmReportDeliver.Flags().String("email", "", "Override recipient email address")
	dfmReportDeliver.Flags().String("message", "", "Custom note to include in the email")
	dfmReportDeliver.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	dfmFindings.AddCommand(dfmFindingsAdd)
	dfmReport.AddCommand(dfmReportGenerate)
	dfmReport.AddCommand(dfmReportDeliver)

	DFMPipeline.AddCommand(dfmEstimate)
	DFMPipeline.AddCommand(dfmSubmit)
	DFMPipeline.AddCommand(dfmStatus)
	DFMPipeline.AddCommand(dfmFindings)
	DFMPipeline.AddCommand(dfmReport)
}
