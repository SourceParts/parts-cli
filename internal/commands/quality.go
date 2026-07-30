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
	"strings"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// =============================================================================
// Quality — AOI-style operator-approved quality & compliance pipeline
// =============================================================================

var Quality = &cobra.Command{
	Use:   "quality",
	Short: "Quality & compliance pipeline (IQC, X-ray, FAI, compliance)",
	Long: `AOI-style operator-approved quality & compliance pipeline.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. iqc inspect          — incoming quality control inspection
  2. xray analyze         — X-ray solder joint analysis
  3. fai inspect          — first article inspection vs BOM
  4. compliance check     — RoHS/REACH/conflict-minerals check`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var qualityIQC = &cobra.Command{
	Use:   "iqc",
	Short: "Incoming quality control operations (inspect)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var qualityXray = &cobra.Command{
	Use:   "xray",
	Short: "X-ray analysis operations (analyze)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var qualityFAI = &cobra.Command{
	Use:   "fai",
	Short: "First article inspection operations (inspect)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var qualityCompliance = &cobra.Command{
	Use:   "compliance",
	Short: "Compliance operations (check)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// --- Station 1: IQC Inspect ---

var qualityIQCInspect = &cobra.Command{
	Use:   "inspect",
	Short: "Inspect incoming components (photos + PO data)",
	Long: `Upload component reel/packaging photos and PO reference data.
Server validates label readability, date code freshness, MPN match,
and MSL level.

Review the inspection checks before accepting components into stock.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		photosStr, _ := cmd.Flags().GetString("photos")
		partNumber, _ := cmd.Flags().GetString("part-number")
		quantity, _ := cmd.Flags().GetInt("quantity")
		dateCode, _ := cmd.Flags().GetString("date-code")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if photosStr == "" {
			return fmt.Errorf("--photos is required")
		}
		if partNumber == "" {
			return fmt.Errorf("--part-number is required")
		}

		photoPaths := strings.Split(photosStr, ",")
		for i, p := range photoPaths {
			photoPaths[i] = strings.TrimSpace(p)
		}

		fmt.Printf("Inspecting incoming component %s (%d units)...\n", partNumber, quantity)

		fileFields := make(map[string]string)
		for i, p := range photoPaths {
			fileFields[fmt.Sprintf("photos_%d", i)] = p
		}

		formFields := map[string]string{
			"part_number":       partNumber,
			"expected_quantity": fmt.Sprintf("%d", quantity),
		}
		if dateCode != "" {
			formFields["expected_date_code"] = dateCode
		}

		// Use multipart upload with multiple photo files
		result, err := qualityUploadPhotosAndGetJSON(
			photoPaths,
			"photos",
			"/v1/quality/iqc/inspect",
			formFields,
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nInspection: %v\n", result["inspection_id"])
		fmt.Printf("Part:       %v\n", result["part_number"])
		fmt.Printf("Disposition: %v\n", result["disposition"])
		fmt.Printf("MSL Level:  %v\n", result["msl_level"])
		fmt.Printf("Moisture Risk: %v\n", result["moisture_exposure_risk"])

		if checks, ok := result["checks"].([]interface{}); ok {
			fmt.Println("\nChecks:")
			for _, check := range checks {
				m := check.(map[string]interface{})
				pass, _ := m["pass"].(bool)
				icon := "PASS"
				if !pass {
					icon = "FAIL"
				}
				fmt.Printf("  [%s] %v: %v\n", icon, m["name"], m["detail"])
			}
		}

		disposition, _ := result["disposition"].(string)
		if disposition == "accept" {
			fmt.Println("\nComponents accepted. Proceed to stock intake.")
		} else if disposition == "reject" {
			fmt.Println("\nComponents REJECTED. Contact supplier.")
		} else {
			fmt.Println("\nComponents ON HOLD. Investigate flagged checks.")
		}
		return nil
	},
}

// --- Station 2: X-ray Analyze ---

var qualityXrayAnalyze = &cobra.Command{
	Use:   "analyze",
	Short: "Analyze X-ray images of solder joints",
	Long: `Upload X-ray images of BGA/QFN solder joints.
Server analyzes void percentage, checks for solder bridges and
head-in-pillow defects per IPC-7095/IPC-A-610 standards.

Review the defect report before accepting the board.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		imagesStr, _ := cmd.Flags().GetString("images")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if imagesStr == "" {
			return fmt.Errorf("--images is required")
		}

		imagePaths := strings.Split(imagesStr, ",")
		for i, p := range imagePaths {
			imagePaths[i] = strings.TrimSpace(p)
		}

		fmt.Printf("Analyzing %d X-ray image(s)...\n", len(imagePaths))

		result, err := qualityUploadPhotosAndGetJSON(
			imagePaths,
			"images",
			"/v1/quality/xray/analyze",
			nil,
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nAnalysis:   %v\n", result["analysis_id"])
		fmt.Printf("Joints:     %v\n", result["joints_analyzed"])
		fmt.Printf("Void %%:     %.2f%% (limit: %v%%)\n", toFloat(result["void_percentage"]), result["void_limit_pct"])

		voidPass, _ := result["void_pass"].(bool)
		if voidPass {
			fmt.Println("Void Check: PASS")
		} else {
			fmt.Println("Void Check: FAIL")
		}

		fmt.Printf("Disposition: %v\n", result["disposition"])
		fmt.Printf("Standard:   %v\n", result["standard"])

		if defects, ok := result["defects"].([]interface{}); ok && len(defects) > 0 {
			fmt.Println("\nDefects:")
			for _, defect := range defects {
				m := defect.(map[string]interface{})
				fmt.Printf("  [%v] %v: %v\n", m["severity"], m["type"], m["location"])
			}
		}

		disposition, _ := result["disposition"].(string)
		if disposition == "accept" {
			fmt.Println("\nX-ray passed. Proceed to functional testing.")
		} else {
			fmt.Println("\nDefects found. Rework affected joints and re-inspect.")
		}
		return nil
	},
}

// --- Station 3: FAI Inspect ---

var qualityFAIInspect = &cobra.Command{
	Use:   "inspect",
	Short: "First article inspection — verify board against BOM",
	Long: `Upload assembled board photos and BOM file.
Server cross-references each visible component against the BOM
for presence, polarity, orientation, and correct value.

Review flagged components before approving the first article.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		photosStr, _ := cmd.Flags().GetString("photos")
		bomPath, _ := cmd.Flags().GetString("bom")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if photosStr == "" {
			return fmt.Errorf("--photos is required")
		}
		if bomPath == "" {
			return fmt.Errorf("--bom is required")
		}

		photoPaths := strings.Split(photosStr, ",")
		for i, p := range photoPaths {
			photoPaths[i] = strings.TrimSpace(p)
		}

		fmt.Printf("Inspecting first article (%d photo(s), BOM: %s)...\n",
			len(photoPaths), filepath.Base(bomPath))

		// Upload photos and BOM together
		result, err := qualityUploadFAIAndGetJSON(photoPaths, bomPath)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nFAI:         %v\n", result["fai_id"])
		fmt.Printf("Photos:      %v\n", result["total_photos"])
		fmt.Printf("BOM Items:   %v\n", result["total_bom_components"])
		fmt.Printf("References:  %v\n", result["total_references"])
		fmt.Printf("Pass Rate:   %v%%\n", result["pass_rate"])
		fmt.Printf("Flagged:     %v\n", result["flagged_count"])

		if flagged, ok := result["flagged"].([]interface{}); ok && len(flagged) > 0 {
			fmt.Println("\nFlagged Components:")
			fmt.Printf("  %-10s %-15s %-20s %s\n", "Ref", "Status", "Expected Value", "MPN")
			fmt.Printf("  %-10s %-15s %-20s %s\n", "----------", "---------------", "--------------------", "---")
			for i, item := range flagged {
				if i >= 20 {
					fmt.Printf("  ... and %d more\n", len(flagged)-20)
					break
				}
				m := item.(map[string]interface{})
				fmt.Printf("  %-10v %-15v %-20v %v\n",
					m["ref"], m["status"], m["expected_value"], m["expected_mpn"])
			}
		}

		flaggedCount := toFloat(result["flagged_count"])
		if flaggedCount == 0 {
			fmt.Println("\nFirst article approved. All components verified.")
		} else {
			fmt.Println("\nReview flagged components. Correct issues before production run.")
		}
		return nil
	},
}

// --- Station 4: Compliance Check ---

var qualityComplianceCheck = &cobra.Command{
	Use:   "check <bom.csv>",
	Short: "Check BOM compliance for target markets",
	Long: `Upload a BOM file and check every component against RoHS, REACH,
conflict minerals (3TG), and market-specific requirements.

Supported markets: EU, US, CN

Review non-compliant components before production or export.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		marketsStr, _ := cmd.Flags().GetString("markets")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if marketsStr == "" {
			return fmt.Errorf("--markets is required")
		}

		markets := strings.Split(marketsStr, ",")
		for i, m := range markets {
			markets[i] = strings.TrimSpace(strings.ToUpper(m))
		}

		fmt.Printf("Checking compliance for %s (markets: %s)...\n",
			filepath.Base(bomPath), strings.Join(markets, ", "))

		result, err := assemblyUploadMultipleAndGetJSON(
			map[string]string{"bom": bomPath},
			"/v1/quality/compliance/check",
			map[string]string{"target_markets": strings.Join(markets, ",")},
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nCompliance: %v\n", result["compliance_id"])
		fmt.Printf("Markets:    %v\n", strings.Join(markets, ", "))
		fmt.Printf("Components: %v\n", result["total_components"])
		fmt.Printf("Non-Compliant: %v\n", result["non_compliant_count"])

		reportReady, _ := result["report_ready"].(bool)
		if reportReady {
			fmt.Println("Report:     READY")
		} else {
			fmt.Println("Report:     NOT READY (resolve issues first)")
		}

		if summary, ok := result["compliance_summary"].(map[string]interface{}); ok {
			fmt.Println("\nMarket Summary:")
			for market, data := range summary {
				if m, ok := data.(map[string]interface{}); ok {
					compliant, _ := m["compliant"].(bool)
					status := "COMPLIANT"
					if !compliant {
						status = "ISSUES FOUND"
					}
					fmt.Printf("  %s: %s\n", market, status)
					if directives, ok := m["directives"].([]interface{}); ok {
						for _, d := range directives {
							fmt.Printf("    - %v\n", d)
						}
					}
					if issues, ok := m["issues"].([]interface{}); ok {
						for _, issue := range issues {
							fmt.Printf("    ! %v\n", issue)
						}
					}
				}
			}
		}

		if ncItems, ok := result["non_compliant"].([]interface{}); ok && len(ncItems) > 0 {
			fmt.Println("\nNon-Compliant Components:")
			fmt.Printf("  %-10s %-25s %-12s %-12s\n", "Ref", "MPN", "RoHS", "REACH")
			fmt.Printf("  %-10s %-25s %-12s %-12s\n", "----------", "-------------------------", "------------", "------------")
			for i, item := range ncItems {
				if i >= 20 {
					fmt.Printf("  ... and %d more\n", len(ncItems)-20)
					break
				}
				m := item.(map[string]interface{})
				fmt.Printf("  %-10v %-25v %-12v %-12v\n",
					m["ref"], m["mpn"], m["rohs"], m["reach"])
			}
		}

		ncCount := toFloat(result["non_compliant_count"])
		if ncCount == 0 && reportReady {
			fmt.Println("\nAll components compliant. Report ready for export documentation.")
		} else {
			fmt.Println("\nReview non-compliant components. Source alternatives or obtain exemptions.")
		}
		return nil
	},
}

// qualityUploadPhotosAndGetJSON uploads multiple photos with form fields and returns JSON.
func qualityUploadPhotosAndGetJSON(photoPaths []string, fieldName string, endpoint string, formFields map[string]string) (map[string]interface{}, error) {
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	for _, photoPath := range photoPaths {
		if err := addFileToMultipart(writer, fieldName, photoPath); err != nil {
			return nil, fmt.Errorf("failed to add photo %s: %w", filepath.Base(photoPath), err)
		}
	}

	for key, value := range formFields {
		if value != "" {
			writer.WriteField(key, value)
		}
	}
	writer.Close()

	url := resolveEndpoint(endpoint)
	req, err := http.NewRequest("POST", url, &requestBody)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	setAuthHeader(req)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}
	return result, nil
}

// qualityUploadFAIAndGetJSON uploads board photos + BOM for FAI inspection.
func qualityUploadFAIAndGetJSON(photoPaths []string, bomPath string) (map[string]interface{}, error) {
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	for _, photoPath := range photoPaths {
		if err := addFileToMultipart(writer, "photos", photoPath); err != nil {
			return nil, fmt.Errorf("failed to add photo %s: %w", filepath.Base(photoPath), err)
		}
	}

	if err := addFileToMultipart(writer, "bom", bomPath); err != nil {
		return nil, fmt.Errorf("failed to add BOM file: %w", err)
	}
	writer.Close()

	url := fmt.Sprintf("https://%s/v1/quality/fai/inspect", domain.API)
	req, err := http.NewRequest("POST", url, &requestBody)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	setAuthHeader(req)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}
	return result, nil
}

func init() {
	// IQC inspect flags
	qualityIQCInspect.Flags().String("photos", "", "Comma-separated paths to component photos (required)")
	qualityIQCInspect.Flags().String("part-number", "", "Expected manufacturer part number (required)")
	qualityIQCInspect.Flags().Int("quantity", 0, "Expected quantity from PO")
	qualityIQCInspect.Flags().String("date-code", "", "Expected date code (YYWW format)")
	qualityIQCInspect.Flags().BoolP("json", "j", false, "Output raw JSON")

	// X-ray analyze flags
	qualityXrayAnalyze.Flags().String("images", "", "Comma-separated paths to X-ray images (required)")
	qualityXrayAnalyze.Flags().BoolP("json", "j", false, "Output raw JSON")

	// FAI inspect flags
	qualityFAIInspect.Flags().String("photos", "", "Comma-separated paths to board photos (required)")
	qualityFAIInspect.Flags().String("bom", "", "Path to BOM file (required)")
	qualityFAIInspect.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Compliance check flags
	qualityComplianceCheck.Flags().String("markets", "", "Comma-separated target markets: EU,US,CN (required)")
	qualityComplianceCheck.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	qualityIQC.AddCommand(qualityIQCInspect)
	qualityXray.AddCommand(qualityXrayAnalyze)
	qualityFAI.AddCommand(qualityFAIInspect)
	qualityCompliance.AddCommand(qualityComplianceCheck)

	Quality.AddCommand(qualityIQC)
	Quality.AddCommand(qualityXray)
	Quality.AddCommand(qualityFAI)
	Quality.AddCommand(qualityCompliance)
}
