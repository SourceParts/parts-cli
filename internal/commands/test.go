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
// Test & Validation — test coverage, provisioning, reliability prediction
// =============================================================================

var TestValidation = &cobra.Command{
	Use:   "test",
	Short: "Test & validation pipeline (coverage, provision, reliability)",
	Long: `Test & validation pipeline for hardware products.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. coverage     — test point coverage analysis + probe accessibility
  2. provision    — device provisioning (keys, certs, serial numbers)
  3. reliability  — MTBF prediction (MIL-HDBK-217F simplified)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// =============================================================================
// Post-Production — RMA, failure analysis, ECO feedback
// =============================================================================

var PostProduction = &cobra.Command{
	Use:   "post-production",
	Short: "Post-production pipeline (RMA, failure analysis, ECO feedback)",
	Long: `Post-production pipeline for field quality and continuous improvement.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. rma process         — process RMA requests
  2. failure-analysis    — Pareto failure analysis + lot correlation
  3. feedback            — ECN suggestions from failure patterns`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var postProductionRMA = &cobra.Command{
	Use:   "rma",
	Short: "RMA operations (process)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// --- Station 1: Test Coverage ---

var testCoverage = &cobra.Command{
	Use:   "coverage",
	Short: "Analyze test point coverage and probe accessibility",
	Long: `Upload test points CSV and PCB file. Checks probe spacing
(min 1.27mm), keep-out violations, and ICT fixture clearance.

Test points CSV columns: ref, net_name, x, y, side

Review blocked points before committing to fixture design.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		tpPath, _ := cmd.Flags().GetString("test-points")
		pcbPath, _ := cmd.Flags().GetString("pcb")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if tpPath == "" || pcbPath == "" {
			return fmt.Errorf("--test-points and --pcb are required")
		}

		fmt.Printf("Analyzing test coverage for %s...\n", filepath.Base(pcbPath))

		result, err := assemblyUploadMultipleAndGetJSON(
			map[string]string{
				"test_points": tpPath,
				"pcb_file":    pcbPath,
			},
			"/v1/test/coverage",
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

		fmt.Printf("\nTotal test points: %v\n", result["total_points"])
		fmt.Printf("Accessible:        %v\n", result["accessible"])
		fmt.Printf("Blocked:           %v\n", result["blocked"])
		fmt.Printf("Coverage:          %v%%\n", result["coverage_percentage"])

		if blocked, ok := result["blocked_details"].([]interface{}); ok && len(blocked) > 0 {
			fmt.Println("\nBlocked Points:")
			fmt.Printf("  %-12s %-20s %s\n", "Ref", "Net", "Reason")
			fmt.Printf("  %-12s %-20s %s\n", "------------", "--------------------", "--------------------")
			for i, item := range blocked {
				if i >= 15 {
					fmt.Printf("  ... and %d more\n", len(blocked)-15)
					break
				}
				m := item.(map[string]interface{})
				ref, _ := m["ref"].(string)
				net, _ := m["net_name"].(string)
				reason, _ := m["reason"].(string)
				if len(net) > 20 {
					net = net[:17] + "..."
				}
				fmt.Printf("  %-12s %-20s %s\n", ref, net, reason)
			}
		}

		blockedCount := toFloat(result["blocked"])
		if blockedCount == 0 {
			fmt.Println("\nAll points accessible. Proceed with fixture design.")
		} else {
			fmt.Println("\nReview blocked points. Relocate test points or adjust fixture.")
		}
		return nil
	},
}

// --- Station 2: Device Provisioning ---

var testProvision = &cobra.Command{
	Use:   "provision",
	Short: "Generate per-device provisioning packages (keys, certs, serial numbers)",
	Long: `Create unique keys, certificates, and serial numbers for each device.
Returns provisioning packages for flashing during production test.

Verify firmware URL and device list before provisioning.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		firmware, _ := cmd.Flags().GetString("firmware")
		devicesStr, _ := cmd.Flags().GetString("devices")
		certTemplate, _ := cmd.Flags().GetString("cert-template")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if firmware == "" {
			return fmt.Errorf("--firmware is required")
		}
		if devicesStr == "" {
			return fmt.Errorf("--devices is required")
		}

		deviceIDs := strings.Split(devicesStr, ",")
		for i := range deviceIDs {
			deviceIDs[i] = strings.TrimSpace(deviceIDs[i])
		}

		fmt.Printf("Provisioning %d devices with %s template...\n", len(deviceIDs), certTemplate)

		// Build device_ids as a JSON array
		payload := map[string]interface{}{
			"firmware_url":         firmware,
			"device_ids":           deviceIDs,
			"certificate_template": certTemplate,
		}

		result, err := postJSONAndGetJSON("/v1/test/provision", payload)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nProvision ID: %v\n", result["provision_id"])
		fmt.Printf("Firmware:     %v\n", result["firmware_url"])
		fmt.Printf("Template:     %v\n", result["certificate_template"])
		fmt.Printf("Devices:      %v\n", result["total_devices"])
		fmt.Printf("Package URL:  %v\n", result["provision_package_url"])

		if devices, ok := result["devices"].([]interface{}); ok && len(devices) > 0 {
			fmt.Println("\nProvisioned Devices:")
			fmt.Printf("  %-15s %-20s %-25s\n", "Device ID", "Serial", "Key ID")
			fmt.Printf("  %-15s %-20s %-25s\n", "---------------", "--------------------", "-------------------------")
			for i, dev := range devices {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(devices)-10)
					break
				}
				m := dev.(map[string]interface{})
				fmt.Printf("  %-15v %-20v %-25v\n",
					m["device_id"], m["serial"], m["key_id"])
			}
		}

		fmt.Println("\nNext: Download package and flash devices during production test.")
		return nil
	},
}

// --- Station 3: Reliability Prediction ---

var testReliability = &cobra.Command{
	Use:   "reliability <bom.csv>",
	Short: "Calculate MTBF using MIL-HDBK-217F simplified method",
	Long: `Upload BOM file and calculate per-component failure rates,
total MTBF, FIT rate, and identify weakest components.

Environments: ground_benign, ground_fixed, ground_mobile, airborne, naval, space

Review weakest links and consider derating or alternatives.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		tempC, _ := cmd.Flags().GetFloat64("temp")
		env, _ := cmd.Flags().GetString("environment")
		dutyCycle, _ := cmd.Flags().GetFloat64("duty-cycle")
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Predicting reliability for %s (%s, %.0fC)...\n",
			filepath.Base(bomPath), env, tempC)

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.WriteField("ambient_temp_c", fmt.Sprintf("%.1f", tempC))
		writer.WriteField("environment", env)
		writer.WriteField("duty_cycle", fmt.Sprintf("%.2f", dutyCycle))
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/test/reliability", domain.API)
		req, err := http.NewRequest("POST", url, &requestBody)
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		setAuthHeader(req)

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

		mtbf := toFloat(result["mtbf_hours"])
		mtbfYears := mtbf / 8760.0

		fmt.Printf("\nMTBF:          %.0f hours (%.1f years)\n", mtbf, mtbfYears)
		fmt.Printf("FIT rate:      %v failures/billion hours\n", result["fit_rate"])
		fmt.Printf("R(1 year):     %.4f (%.2f%%)\n",
			toFloat(result["reliability_at_1year"]),
			toFloat(result["reliability_at_1year"])*100)
		fmt.Printf("Standard:      %v\n", result["standard"])

		if conditions, ok := result["operating_conditions"].(map[string]interface{}); ok {
			fmt.Printf("\nOperating Conditions:\n")
			fmt.Printf("  Temperature:  %.0fC\n", toFloat(conditions["ambient_temp_c"]))
			fmt.Printf("  Environment:  %v\n", conditions["environment"])
			fmt.Printf("  Duty cycle:   %.0f%%\n", toFloat(conditions["duty_cycle"])*100)
			fmt.Printf("  Temp factor:  %.4f\n", toFloat(conditions["temp_acceleration_factor"]))
			fmt.Printf("  Env factor:   %.1f\n", toFloat(conditions["environment_factor"]))
		}

		if weakest, ok := result["weakest_links"].([]interface{}); ok && len(weakest) > 0 {
			fmt.Println("\nWeakest Links:")
			fmt.Printf("  %-15s %-30s %12s %10s\n", "Ref", "Description", "Failure Rate", "Contrib %")
			fmt.Printf("  %-15s %-30s %12s %10s\n", "---------------", "------------------------------", "------------", "----------")
			for _, item := range weakest {
				m := item.(map[string]interface{})
				desc, _ := m["description"].(string)
				if len(desc) > 30 {
					desc = desc[:27] + "..."
				}
				fmt.Printf("  %-15v %-30s %12.6f %9.1f%%\n",
					m["ref"], desc, toFloat(m["failure_rate"]), toFloat(m["contribution_pct"]))
			}
		}

		fmt.Println("\nReview weakest links. Consider derating or alternative components.")
		return nil
	},
}

// --- Station 4: RMA Process ---

var postProductionRMAProcess = &cobra.Command{
	Use:   "process",
	Short: "Process an RMA request (failure categorization + disposition)",
	Long: `Submit RMA details. Server categorizes failure mode (DOA, wear-out,
damage, no-fault-found), checks warranty status, and determines disposition
(replace, repair, refund, reject).

Review disposition before confirming with customer.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		orderID, _ := cmd.Flags().GetString("order")
		failure, _ := cmd.Flags().GetString("failure")
		serial, _ := cmd.Flags().GetString("serial")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if orderID == "" {
			return fmt.Errorf("--order is required")
		}
		if failure == "" {
			return fmt.Errorf("--failure is required")
		}
		if serial == "" {
			return fmt.Errorf("--serial is required")
		}

		fmt.Printf("Processing RMA for order %s, serial %s...\n", orderID, serial)

		result, err := postJSONAndGetJSON("/v1/post-production/rma/process", map[string]interface{}{
			"order_id":            orderID,
			"failure_description": failure,
			"serial_number":       serial,
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nRMA Number:   %v\n", result["rma_number"])
		fmt.Printf("Order:        %v\n", result["order_id"])
		fmt.Printf("Serial:       %v\n", result["serial_number"])
		fmt.Printf("Failure:      %v\n", result["failure_description"])
		fmt.Printf("Category:     %v\n", result["failure_category"])
		fmt.Printf("Warranty:     %v\n", result["warranty_status"])
		fmt.Printf("Disposition:  %v\n", result["disposition"])

		if instructions, ok := result["return_instructions"].(map[string]interface{}); ok {
			fmt.Println("\nReturn Instructions:")
			if action, ok := instructions["action"].(string); ok {
				fmt.Printf("  Action: %s\n", action)
			}
			if reason, ok := instructions["reason"].(string); ok {
				fmt.Printf("  Reason: %s\n", reason)
			}
			if label, ok := instructions["shipping_label"].(string); ok {
				fmt.Printf("  Label:  %s\n", label)
			}
			if center, ok := instructions["rma_center"].(string); ok {
				fmt.Printf("  Center: %s\n", center)
			}
		}

		disposition, _ := result["disposition"].(string)
		if disposition == "replace" || disposition == "repair" || disposition == "refund" {
			fmt.Println("\nCommunicate disposition to customer. Provide return shipping label.")
		} else {
			fmt.Println("\nRMA rejected. Communicate reason to customer.")
		}
		return nil
	},
}

// --- Station 5: Failure Analysis ---

var postProductionFailureAnalysis = &cobra.Command{
	Use:   "failure-analysis <failures.csv>",
	Short: "Run Pareto failure analysis with lot correlation",
	Long: `Upload failure data CSV and run Pareto analysis.
Identifies top failure modes, correlates with production lots,
and provides actionable recommendations.

Failure data CSV columns: serial, failure_mode, date, lot_number

Review Pareto chart and lot correlation before taking action.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		failurePath := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Analyzing failures from %s...\n", filepath.Base(failurePath))

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "failure_data", failurePath); err != nil {
			return fmt.Errorf("failed to add failure data file: %w", err)
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/post-production/failure-analysis", domain.API)
		req, err := http.NewRequest("POST", url, &requestBody)
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", writer.FormDataContentType())
		req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
		setAuthHeader(req)

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

		fmt.Printf("\nAnalysis ID:        %v\n", result["analysis_id"])
		fmt.Printf("Total failures:     %v\n", result["total_failures"])
		fmt.Printf("Unique modes:       %v\n", result["unique_failure_modes"])
		fmt.Printf("Unique lots:        %v\n", result["unique_lots"])

		if pareto, ok := result["pareto"].([]interface{}); ok && len(pareto) > 0 {
			fmt.Println("\nPareto Analysis:")
			fmt.Printf("  %-25s %8s %8s %10s\n", "Failure Mode", "Count", "%", "Cumul %")
			fmt.Printf("  %-25s %8s %8s %10s\n", "-------------------------", "--------", "--------", "----------")
			for i, item := range pareto {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(pareto)-10)
					break
				}
				m := item.(map[string]interface{})
				mode, _ := m["failure_mode"].(string)
				if len(mode) > 25 {
					mode = mode[:22] + "..."
				}
				fmt.Printf("  %-25s %8v %7.1f%% %9.1f%%\n",
					mode, m["count"], toFloat(m["percentage"]), toFloat(m["cumulative_pct"]))
			}
		}

		if lots, ok := result["lot_correlation"].([]interface{}); ok && len(lots) > 0 {
			fmt.Println("\nLot Correlation:")
			fmt.Printf("  %-15s %10s %12s\n", "Lot", "Failures", "Fail Rate %")
			fmt.Printf("  %-15s %10s %12s\n", "---------------", "----------", "------------")
			for i, item := range lots {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(lots)-10)
					break
				}
				m := item.(map[string]interface{})
				fmt.Printf("  %-15v %10v %11.1f%%\n",
					m["lot"], m["failures"], toFloat(m["failure_rate"]))
			}
		}

		if recs, ok := result["recommendations"].([]interface{}); ok && len(recs) > 0 {
			fmt.Println("\nRecommendations:")
			for _, rec := range recs {
				fmt.Printf("  - %v\n", rec)
			}
		}

		fmt.Println("\nNext: parts post-production feedback --analysis-id <id>")
		return nil
	},
}

// --- Station 6: ECO Feedback ---

var postProductionECOFeedback = &cobra.Command{
	Use:     "feedback",
	Aliases: []string{"eco-feedback"},
	Short:   "Generate ECN suggestions from failure patterns",
	Long: `Submit failure analysis reference and get ECN suggestions.
Suggests design/process changes based on failure patterns
(e.g., paste aperture changes, AVL updates, ESD protection).

Review ECN suggestions before creating formal change requests.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		analysisID, _ := cmd.Flags().GetString("analysis-id")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if analysisID == "" {
			return fmt.Errorf("--analysis-id is required")
		}

		fmt.Printf("Generating ECO feedback from analysis %s...\n", analysisID)

		result, err := postJSONAndGetJSON("/v1/post-production/eco/feedback", map[string]interface{}{
			"failure_analysis_id": analysisID,
			"failure_data":        map[string]interface{}{},
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nFeedback ID:    %v\n", result["feedback_id"])
		fmt.Printf("Analysis ref:   %v\n", result["failure_analysis_id"])
		fmt.Printf("Suggested ECNs: %v\n", result["total_suggested_ecns"])
		fmt.Printf("Priority score: %v/100\n", result["priority_score"])

		if ecns, ok := result["suggested_ecns"].([]interface{}); ok && len(ecns) > 0 {
			fmt.Println("\nSuggested ECNs:")
			for i, item := range ecns {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(ecns)-10)
					break
				}
				m := item.(map[string]interface{})
				severity, _ := m["severity"].(string)
				title, _ := m["title"].(string)
				ecnType, _ := m["type"].(string)
				rationale, _ := m["rationale"].(string)

				fmt.Printf("\n  [%s] %s\n", strings.ToUpper(severity), title)
				fmt.Printf("    Type: %s\n", ecnType)
				if affected, ok := m["affected_designators"].([]interface{}); ok && len(affected) > 0 {
					refs := make([]string, len(affected))
					for j, a := range affected {
						refs[j] = fmt.Sprintf("%v", a)
					}
					fmt.Printf("    Affected: %s\n", strings.Join(refs, ", "))
				}
				if len(rationale) > 100 {
					rationale = rationale[:97] + "..."
				}
				fmt.Printf("    Rationale: %s\n", rationale)
			}
		} else {
			fmt.Println("\nNo ECN suggestions generated. Failure patterns may not match known rules.")
		}

		fmt.Println("\nReview suggestions and create formal ECNs for approved items.")
		return nil
	},
}

func init() {
	// Test coverage flags
	testCoverage.Flags().String("test-points", "", "Path to test points CSV (required)")
	testCoverage.Flags().String("pcb", "", "Path to .kicad_pcb file (required)")
	testCoverage.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Test provision flags
	testProvision.Flags().String("firmware", "", "Firmware URL (required)")
	testProvision.Flags().String("devices", "", "Comma-separated device IDs (required)")
	testProvision.Flags().String("cert-template", "production", "Certificate template (production, development)")
	testProvision.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Test reliability flags
	testReliability.Flags().Float64("temp", 25, "Ambient temperature in Celsius")
	testReliability.Flags().String("environment", "ground_benign", "Operating environment")
	testReliability.Flags().Float64("duty-cycle", 1.0, "Duty cycle (0.0-1.0)")
	testReliability.Flags().BoolP("json", "j", false, "Output raw JSON")

	// RMA process flags
	postProductionRMAProcess.Flags().String("order", "", "Order ID (required)")
	postProductionRMAProcess.Flags().String("failure", "", "Failure description (required)")
	postProductionRMAProcess.Flags().String("serial", "", "Serial number (required)")
	postProductionRMAProcess.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Failure analysis flags
	postProductionFailureAnalysis.Flags().BoolP("json", "j", false, "Output raw JSON")

	// ECO feedback flags
	postProductionECOFeedback.Flags().String("analysis-id", "", "Failure analysis ID (required)")
	postProductionECOFeedback.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up Test subcommands
	TestValidation.AddCommand(testCoverage)
	TestValidation.AddCommand(testProvision)
	TestValidation.AddCommand(testReliability)

	// Wire up Post-Production subcommands
	postProductionRMA.AddCommand(postProductionRMAProcess)
	PostProduction.AddCommand(postProductionRMA)
	PostProduction.AddCommand(postProductionFailureAnalysis)
	PostProduction.AddCommand(postProductionECOFeedback)
}
