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
// Assembly Pipeline — AOI-style operator-approved SMT assembly pipeline
// =============================================================================

var Assembly = &cobra.Command{
	Use:   "assembly",
	Short: "SMT assembly pipeline (readiness, feeder, reflow, AOI, test)",
	Long: `AOI-style operator-approved SMT assembly pipeline.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. readiness      — pre-assembly readiness checklist
  2. feeder-setup   — optimal feeder slot assignment
  3. reflow-profile — reflow profile recommendation
  4. aoi            — automated optical inspection
  5. test           — functional test validation + yield`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// assemblyUploadMultipleAndGetJSON uploads multiple files with form fields and returns JSON.
func assemblyUploadMultipleAndGetJSON(fileFields map[string]string, endpoint string, formFields map[string]string) (map[string]interface{}, error) {
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	for fieldName, filePath := range fileFields {
		if err := addFileToMultipart(writer, fieldName, filePath); err != nil {
			return nil, fmt.Errorf("failed to add %s: %w", fieldName, err)
		}
	}

	for key, value := range formFields {
		if value != "" {
			writer.WriteField(key, value)
		}
	}
	writer.Close()

	url := fmt.Sprintf("https://%s%s", domain.API, endpoint)
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

// assemblyUploadPhotosAndGetJSON uploads multiple photos + optional reference image.
func assemblyUploadPhotosAndGetJSON(photoPaths []string, referencePath string, endpoint string, formFields map[string]string) (map[string]interface{}, error) {
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	for _, photoPath := range photoPaths {
		file, err := os.Open(photoPath)
		if err != nil {
			return nil, fmt.Errorf("failed to open photo %s: %w", photoPath, err)
		}
		part, err := writer.CreateFormFile("photos", filepath.Base(photoPath))
		if err != nil {
			file.Close()
			return nil, fmt.Errorf("failed to create form file: %w", err)
		}
		_, err = io.Copy(part, file)
		file.Close()
		if err != nil {
			return nil, fmt.Errorf("failed to copy photo: %w", err)
		}
	}

	if referencePath != "" {
		if err := addFileToMultipart(writer, "reference", referencePath); err != nil {
			return nil, fmt.Errorf("failed to add reference: %w", err)
		}
	}

	for key, value := range formFields {
		if value != "" {
			writer.WriteField(key, value)
		}
	}
	writer.Close()

	url := fmt.Sprintf("https://%s%s", domain.API, endpoint)
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

// --- Station 1: Readiness Check ---

var assemblyReadiness = &cobra.Command{
	Use:   "readiness",
	Short: "Pre-assembly readiness checklist",
	Long: `Upload BOM, gerber ZIP, and position CSV to verify assembly readiness.

Checks: BOM parseable, gerbers valid, stencil layer present,
positions match BOM references. Returns pass/fail per item.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath, _ := cmd.Flags().GetString("bom")
		gerbersPath, _ := cmd.Flags().GetString("gerbers")
		positionsPath, _ := cmd.Flags().GetString("positions")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if bomPath == "" || gerbersPath == "" || positionsPath == "" {
			return fmt.Errorf("--bom, --gerbers, and --positions are required")
		}

		fmt.Println("Running assembly readiness check...")
		result, err := assemblyUploadMultipleAndGetJSON(
			map[string]string{
				"bom":       bomPath,
				"gerbers":   gerbersPath,
				"positions": positionsPath,
			},
			"/v1/assembly/readiness",
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

		overall := result["overall_status"]
		fmt.Printf("\nReadiness: %v\n", overall)

		if checklist, ok := result["checklist"].([]interface{}); ok {
			fmt.Println("\nChecklist:")
			for _, item := range checklist {
				m := item.(map[string]interface{})
				status := m["status"]
				icon := "PASS"
				if status == "fail" {
					icon = "FAIL"
				} else if status == "warn" {
					icon = "WARN"
				}
				fmt.Printf("  [%s] %v: %v\n", icon, m["label"], m["detail"])
			}
		}

		if overall == "pass" {
			fmt.Println("\nNext: parts assembly feeder-setup --bom bom.csv --positions positions.csv --machine neoden")
		} else {
			fmt.Println("\nAddress failing items, then re-run: parts assembly readiness ...")
		}
		return nil
	},
}

// --- Station 2: Feeder Setup ---

var assemblyFeederSetup = &cobra.Command{
	Use:   "feeder-setup",
	Short: "Generate optimal feeder slot assignment",
	Long: `Upload BOM and position CSV. Server groups components and assigns
feeder slots to minimize changeover time.

Outputs a feeder map with slot assignments sorted by placement count.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath, _ := cmd.Flags().GetString("bom")
		positionsPath, _ := cmd.Flags().GetString("positions")
		machine, _ := cmd.Flags().GetString("machine")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if bomPath == "" || positionsPath == "" {
			return fmt.Errorf("--bom and --positions are required")
		}

		fmt.Printf("Generating feeder setup for %s...\n", machine)
		result, err := assemblyUploadMultipleAndGetJSON(
			map[string]string{
				"bom":       bomPath,
				"positions": positionsPath,
			},
			"/v1/assembly/feeder-setup",
			map[string]string{"machine_type": machine},
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nMachine: %s\n", machine)
		fmt.Printf("Total feeders: %v\n", result["total_feeders"])
		fmt.Printf("Total placements: %v\n", result["total_placements"])

		if feederMap, ok := result["feeder_map"].([]interface{}); ok && len(feederMap) > 0 {
			fmt.Println("\nFeeder Map:")
			for i, entry := range feederMap {
				if i >= 20 {
					fmt.Printf("  ... and %d more\n", len(feederMap)-20)
					break
				}
				m := entry.(map[string]interface{})
				fmt.Printf("  Slot %v: %-20v (%v) x%v\n",
					m["slot"], m["value"], m["footprint"], m["count"])
			}
		}

		fmt.Println("\nNext: parts assembly reflow-profile --bom bom.csv")
		return nil
	},
}

// --- Station 3: Reflow Profile ---

var assemblyReflowProfile = &cobra.Command{
	Use:   "reflow-profile",
	Short: "Analyze BOM thermal specs and recommend reflow profile",
	Long: `Upload BOM CSV. Server analyzes MSL levels, peak reflow temps,
and soak times across all components.

Returns a recommended reflow profile with thermal constraints.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath, _ := cmd.Flags().GetString("bom")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if bomPath == "" {
			return fmt.Errorf("--bom is required")
		}

		fmt.Printf("Analyzing reflow profile for %s...\n", filepath.Base(bomPath))
		result, err := uploadAndGetJSON(bomPath, "/v1/assembly/reflow-profile", nil)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		if profile, ok := result["recommended_profile"].(map[string]interface{}); ok {
			fmt.Println("\nRecommended Reflow Profile:")
			fmt.Printf("  Solder type:    %v\n", profile["solder_type"])
			fmt.Printf("  Peak temp:      %v°C\n", profile["peak_temp"])
			fmt.Printf("  Soak:           %v–%v°C for %vs\n",
				profile["soak_start"], profile["soak_end"], profile["soak_time_seconds"])
			fmt.Printf("  Liquidus temp:  %v°C\n", profile["liquidus_temp"])
			fmt.Printf("  Time > liquidus: %vs\n", profile["time_above_liquidus"])
			fmt.Printf("  Preheat rate:   %v°C/s\n", profile["preheat_rate"])
			fmt.Printf("  Cooling rate:   %v°C/s\n", profile["cooling_rate"])
		}

		if warnings, ok := result["msl_warnings"].([]interface{}); ok && len(warnings) > 0 {
			fmt.Println("\nMSL Warnings:")
			for _, w := range warnings {
				m := w.(map[string]interface{})
				fmt.Printf("  %v (%v components)\n", m["action"], m["count"])
			}
		}

		if constraints, ok := result["thermal_constraints"].([]interface{}); ok && len(constraints) > 0 {
			fmt.Println("\nThermal Constraints:")
			for _, c := range constraints {
				m := c.(map[string]interface{})
				fmt.Printf("  %v\n", m["detail"])
			}
		}

		fmt.Println("\nNext: Set oven profile, run assembly, then: parts assembly aoi --photos board.jpg")
		return nil
	},
}

// --- Station 4: AOI (Automated Optical Inspection) ---

var assemblyAOI = &cobra.Command{
	Use:   "aoi",
	Short: "Automated optical inspection of assembled boards",
	Long: `Upload board photos and optional golden reference image.
Server compares placement quality and flags defects.

Defect categories: tombstoned, missing, rotated, shifted, bridged,
insufficient solder, excess solder, wrong component, polarity reversed.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		photosFlag, _ := cmd.Flags().GetString("photos")
		referencePath, _ := cmd.Flags().GetString("reference")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if photosFlag == "" {
			return fmt.Errorf("--photos is required (comma-separated paths)")
		}

		photoPaths := strings.Split(photosFlag, ",")
		for i, p := range photoPaths {
			photoPaths[i] = strings.TrimSpace(p)
		}

		fmt.Printf("Running AOI on %d photo(s)...\n", len(photoPaths))
		result, err := assemblyUploadPhotosAndGetJSON(
			photoPaths, referencePath, "/v1/assembly/aoi", nil,
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nPhotos inspected: %v\n", result["total_photos"])
		fmt.Printf("Total defects flagged: %v\n", result["total_defects_found"])

		if inspections, ok := result["inspections"].([]interface{}); ok {
			for _, insp := range inspections {
				m := insp.(map[string]interface{})
				defects, _ := m["defects"].([]interface{})
				fmt.Printf("  %v: %v (%d issues)\n", m["photo"], m["status"], len(defects))
				for _, d := range defects {
					dm := d.(map[string]interface{})
					fmt.Printf("    [%v] %v: %v\n", dm["severity"], dm["type"], dm["detail"])
				}
			}
		}

		fmt.Println("\nNext: Review flagged items, then: parts assembly test --results results.csv --criteria criteria.json")
		return nil
	},
}

// --- Station 5: Functional Test ---

var assemblyTest = &cobra.Command{
	Use:   "test",
	Short: "Validate functional test results against pass/fail criteria",
	Long: `Upload test results CSV and pass/fail criteria JSON.
Server validates each unit against specs, calculates yield,
and recommends lot disposition.

Criteria JSON format: {"TestName": {"min": 3.2, "max": 3.4}, ...}`,
	RunE: func(cmd *cobra.Command, args []string) error {
		resultsPath, _ := cmd.Flags().GetString("results")
		criteriaPath, _ := cmd.Flags().GetString("criteria")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if resultsPath == "" {
			return fmt.Errorf("--results is required")
		}

		// Upload results file with criteria as form field or file
		fileFields := map[string]string{
			"results": resultsPath,
		}
		formFields := map[string]string{}

		if criteriaPath != "" {
			// Read criteria file and send as form field
			criteriaData, err := os.ReadFile(criteriaPath)
			if err != nil {
				return fmt.Errorf("failed to read criteria file: %w", err)
			}
			formFields["criteria"] = string(criteriaData)
		}

		fmt.Printf("Validating test results from %s...\n", filepath.Base(resultsPath))
		result, err := assemblyUploadMultipleAndGetJSON(
			fileFields, "/v1/assembly/functional-test", formFields,
		)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		yieldPct := result["yield_percent"]
		disposition := result["disposition"]
		fmt.Printf("\nYield: %v%% (%v/%v pass)\n", yieldPct, result["passed"], result["total_units"])
		fmt.Printf("Disposition: %v\n", disposition)

		if outliers, ok := result["outliers"].([]interface{}); ok && len(outliers) > 0 {
			fmt.Println("\nOutliers:")
			for i, o := range outliers {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(outliers)-10)
					break
				}
				m := o.(map[string]interface{})
				fmt.Printf("  %v: %v = %v\n", m["unit"], m["test"], m["value"])
			}
		}

		if disposition == "accept" {
			fmt.Println("\nLot accepted. Package and ship.")
		} else {
			fmt.Println("\nReview failed units. Rework or scrap per disposition policy.")
		}
		return nil
	},
}

func init() {
	// Readiness flags
	assemblyReadiness.Flags().String("bom", "", "Path to BOM CSV file (required)")
	assemblyReadiness.Flags().String("gerbers", "", "Path to gerber ZIP file (required)")
	assemblyReadiness.Flags().String("positions", "", "Path to position CSV file (required)")
	assemblyReadiness.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Feeder setup flags
	assemblyFeederSetup.Flags().String("bom", "", "Path to BOM CSV file (required)")
	assemblyFeederSetup.Flags().String("positions", "", "Path to position CSV file (required)")
	assemblyFeederSetup.Flags().String("machine", "neoden", "Machine type (neoden, juki, yamaha)")
	assemblyFeederSetup.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Reflow profile flags
	assemblyReflowProfile.Flags().String("bom", "", "Path to BOM CSV file (required)")
	assemblyReflowProfile.Flags().BoolP("json", "j", false, "Output raw JSON")

	// AOI flags
	assemblyAOI.Flags().String("photos", "", "Comma-separated board photo paths (required)")
	assemblyAOI.Flags().String("reference", "", "Path to golden reference image (optional)")
	assemblyAOI.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Functional test flags
	assemblyTest.Flags().String("results", "", "Path to test results CSV (required)")
	assemblyTest.Flags().String("criteria", "", "Path to pass/fail criteria JSON (optional)")
	assemblyTest.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	Assembly.AddCommand(assemblyReadiness)
	Assembly.AddCommand(assemblyFeederSetup)
	Assembly.AddCommand(assemblyReflowProfile)
	Assembly.AddCommand(assemblyAOI)
	Assembly.AddCommand(assemblyTest)
}
