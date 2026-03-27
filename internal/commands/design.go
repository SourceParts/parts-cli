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
// Design — Design & Engineering pipeline (schematic, impedance, thermal)
// =============================================================================

var Design = &cobra.Command{
	Use:   "design",
	Short: "Design & engineering pipeline (schematic review, impedance, thermal)",
	Long: `Design & engineering analysis pipeline.

Each command performs one atomic analysis step and returns results for review.

Pipeline:
  1. schematic-review    — ERC-style schematic review
  2. impedance           — controlled-impedance calculation
  3. thermal             — BOM-based thermal analysis`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// --- Station 1: Schematic Review ---

var designSchematicReview = &cobra.Command{
	Use:   "schematic-review <file.kicad_sch>",
	Short: "Review a KiCad schematic for common design issues",
	Long: `Upload a .kicad_sch file and check for:
  - Unconnected pins and missing no-connect flags
  - Missing decoupling capacitors (ICs without bypass caps)
  - Power domain analysis (voltage rails, current budget)
  - Net naming conventions

Review all findings before proceeding with layout.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		schPath := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Reviewing schematic %s...\n", filepath.Base(schPath))

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", schPath); err != nil {
			return fmt.Errorf("failed to add schematic file: %w", err)
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/design/schematic-review", domain.API)
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

		fmt.Printf("\nReview:     %v\n", result["review_id"])
		fmt.Printf("Score:      %v/100\n", result["score"])
		fmt.Printf("Components: %v\n", result["total_components"])
		fmt.Printf("ICs:        %v\n", result["total_ics"])
		fmt.Printf("Capacitors: %v\n", result["total_capacitors"])
		fmt.Printf("Nets:       %v\n", result["total_nets"])

		if findings, ok := result["findings"].([]interface{}); ok && len(findings) > 0 {
			fmt.Printf("\nFindings (%d):\n", len(findings))
			for i, finding := range findings {
				if i >= 20 {
					fmt.Printf("  ... and %d more\n", len(findings)-20)
					break
				}
				m := finding.(map[string]interface{})
				sev, _ := m["severity"].(string)
				cat, _ := m["category"].(string)
				desc, _ := m["description"].(string)
				ref, _ := m["component_ref"].(string)
				prefix := "  "
				if sev == "warning" {
					prefix = "  [WARN] "
				} else if sev == "error" {
					prefix = "  [ERR]  "
				} else {
					prefix = "  [INFO] "
				}
				if ref != "" {
					fmt.Printf("%s(%s) %s: %s\n", prefix, cat, ref, desc)
				} else {
					fmt.Printf("%s(%s) %s\n", prefix, cat, desc)
				}
			}
		} else {
			fmt.Println("\nNo findings. Schematic looks clean.")
		}

		if domains, ok := result["power_domains"].([]interface{}); ok && len(domains) > 0 {
			fmt.Println("\nPower Domains:")
			fmt.Printf("  %-20s %10s %12s %12s\n", "Rail", "Voltage", "Est. mA", "Est. W")
			fmt.Printf("  %-20s %10s %12s %12s\n", "--------------------", "----------", "------------", "------------")
			for _, d := range domains {
				m := d.(map[string]interface{})
				name, _ := m["rail_name"].(string)
				voltage := "unknown"
				if v, ok := m["voltage_v"].(float64); ok && v > 0 {
					voltage = fmt.Sprintf("%.1fV", v)
				}
				fmt.Printf("  %-20s %10s %12.1f %12.3f\n",
					name, voltage, toFloat(m["estimated_current_ma"]), toFloat(m["estimated_power_w"]))
			}
		}

		fmt.Println("\nNext: parts design impedance --width <mm> --type microstrip --dielectric <Er> --height <mm>")
		return nil
	},
}

// --- Station 2: Impedance Calculation ---

var designImpedance = &cobra.Command{
	Use:   "impedance",
	Short: "Calculate controlled impedance for a PCB trace",
	Long: `Calculate characteristic impedance for microstrip, stripline,
or differential pair configurations.

Uses standard formulas (Hammerstad-Jensen for microstrip, IPC-2141).
Returns impedance, propagation delay, loss, and recommendations.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		width, _ := cmd.Flags().GetFloat64("width")
		spacing, _ := cmd.Flags().GetFloat64("spacing")
		traceType, _ := cmd.Flags().GetString("type")
		dielectric, _ := cmd.Flags().GetFloat64("dielectric")
		height, _ := cmd.Flags().GetFloat64("height")
		copperOz, _ := cmd.Flags().GetFloat64("copper")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if width <= 0 {
			return fmt.Errorf("--width must be positive")
		}
		if height <= 0 {
			return fmt.Errorf("--height must be positive")
		}

		fmt.Printf("Calculating %s impedance (w=%.3fmm, h=%.3fmm, Er=%.2f)...\n",
			traceType, width, height, dielectric)

		payload := map[string]interface{}{
			"stackup": map[string]interface{}{
				"dielectric_height_mm": height,
				"dielectric_constant":  dielectric,
			},
			"trace_width_mm":   width,
			"trace_spacing_mm": spacing,
			"copper_weight_oz": copperOz,
			"trace_type":       traceType,
		}

		result, err := postJSONAndGetJSON("/v1/design/impedance", payload)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nCalculation: %v\n", result["calculation_id"])
		fmt.Printf("Type:        %v\n", result["trace_type"])
		fmt.Printf("Width:       %v mm\n", result["trace_width_mm"])
		if spacing > 0 {
			fmt.Printf("Spacing:     %v mm\n", result["trace_spacing_mm"])
		}
		fmt.Printf("Copper:      %v oz (%.4f mm)\n", result["copper_weight_oz"], toFloat(result["copper_thickness_mm"]))
		fmt.Printf("Dielectric:  Er=%v, H=%v mm\n", result["dielectric_constant"], result["dielectric_height_mm"])
		fmt.Printf("Eff. Er:     %v\n", result["effective_dielectric_constant"])

		fmt.Printf("\n  Impedance:  %.2f ohm\n", toFloat(result["impedance_ohms"]))
		fmt.Printf("  Delay:      %.3f ps/mm\n", toFloat(result["delay_ps_per_mm"]))
		fmt.Printf("  Loss:       %.4f dB/mm\n", toFloat(result["loss_db_per_mm"]))

		if rec, ok := result["recommendation"].(string); ok && rec != "" {
			fmt.Printf("\n  %s\n", rec)
		}

		fmt.Println("\nNext: parts design thermal <bom.csv>")
		return nil
	},
}

// --- Station 3: Thermal Analysis ---

var designThermal = &cobra.Command{
	Use:   "thermal <bom.csv>",
	Short: "Estimate thermal dissipation from BOM and identify hot spots",
	Long: `Upload a BOM file and estimate power dissipation per IC.
Identifies components exceeding thermal pad limits and recommends
thermal vias or heatsinking.

Review hot spots and recommendations before layout.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		ambientTemp, _ := cmd.Flags().GetFloat64("ambient")
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Analyzing thermal profile from %s...\n", filepath.Base(bomPath))

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.WriteField("ambient_temp_c", fmt.Sprintf("%.1f", ambientTemp))
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/design/thermal", domain.API)
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

		fmt.Printf("\nAnalysis:    %v\n", result["analysis_id"])
		fmt.Printf("Components:  %v\n", result["total_components"])
		fmt.Printf("Total Power: %.3f W\n", toFloat(result["total_power_w"]))
		fmt.Printf("Ambient:     %.1f C\n", toFloat(result["ambient_temp_c"]))

		if hotSpots, ok := result["hot_spots"].([]interface{}); ok && len(hotSpots) > 0 {
			fmt.Printf("\nHot Spots (%d):\n", len(hotSpots))
			fmt.Printf("  %-12s %-25s %8s %8s %10s\n", "Ref", "Description", "Power W", "Tj (C)", "Risk")
			fmt.Printf("  %-12s %-25s %8s %8s %10s\n", "------------", "-------------------------", "--------", "--------", "----------")
			for i, hs := range hotSpots {
				if i >= 15 {
					fmt.Printf("  ... and %d more\n", len(hotSpots)-15)
					break
				}
				m := hs.(map[string]interface{})
				desc, _ := m["description"].(string)
				if len(desc) > 25 {
					desc = desc[:22] + "..."
				}
				risk, _ := m["thermal_risk"].(string)
				fmt.Printf("  %-12v %-25s %8.3f %8.1f %10s\n",
					m["reference"], desc, toFloat(m["power_w"]), toFloat(m["junction_temp_c"]), risk)
			}
		} else {
			fmt.Println("\nNo hot spots detected.")
		}

		if recs, ok := result["recommendations"].([]interface{}); ok && len(recs) > 0 {
			fmt.Println("\nRecommendations:")
			for _, rec := range recs {
				fmt.Printf("  - %v\n", rec)
			}
		}

		fmt.Println("\nNext: parts design schematic-review <file.kicad_sch>")
		return nil
	},
}

func init() {
	// Schematic review flags
	designSchematicReview.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Impedance flags
	designImpedance.Flags().Float64("width", 0, "Trace width in mm (required)")
	designImpedance.Flags().Float64("spacing", 0, "Trace spacing in mm (for differential)")
	designImpedance.Flags().String("type", "microstrip", "Trace type: microstrip, stripline, differential")
	designImpedance.Flags().Float64("dielectric", 4.3, "Dielectric constant (Er)")
	designImpedance.Flags().Float64("height", 0, "Dielectric height in mm (required)")
	designImpedance.Flags().Float64("copper", 1.0, "Copper weight in oz")
	designImpedance.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Thermal flags
	designThermal.Flags().Float64("ambient", 25.0, "Ambient temperature in Celsius")
	designThermal.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	Design.AddCommand(designSchematicReview)
	Design.AddCommand(designImpedance)
	Design.AddCommand(designThermal)
}
