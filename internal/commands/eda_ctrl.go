package commands

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

// =============================================================================
// EDA Ctrl — AOI-style operator-approved PCB editing pipeline
// =============================================================================

var edaCtrl = &cobra.Command{
	Use:   "ctrl",
	Short: "PCB editing pipeline (analyze, ripup, validate, export)",
	Long: `AOI-style operator-approved PCB editing pipeline.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. analyze         — identify affected nets
  2. propose   — enumerate tracks/vias to remove
  3. ripup     — remove tracks, return diff
  4. validate        — run Design Rule Check
  5. export          — export gerbers + drill + positions`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// uploadAndGetJSON uploads a .kicad_pcb file to an API endpoint and returns JSON.
func uploadAndGetJSON(pcbPath, endpoint string, formFields map[string]string) (map[string]interface{}, error) {
	var requestBody bytes.Buffer
	writer := multipart.NewWriter(&requestBody)

	if err := addFileToMultipart(writer, "file", pcbPath); err != nil {
		return nil, fmt.Errorf("failed to add file: %w", err)
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
	if apiKey := Client.GetAPIKey(); apiKey != "" {
		req.Header.Set("X-API-Key", apiKey)
	}

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

// --- Station 0a: ERC ---

var edaCtrlERC = &cobra.Command{
	Use:   "erc <file.kicad_sch>",
	Short: "Run Electrical Rules Check on a schematic",
	Long: `Upload a .kicad_sch file to the API and run ERC.

Returns a violation report with error/warning counts.
Review the results before proceeding to netlist-diff.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		schPath := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Running ERC on %s...\n", filepath.Base(schPath))
		result, err := uploadAndGetJSON(schPath, "/v1/eda/erc", nil)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		errors := result["error_count"]
		warnings := result["warning_count"]
		status := "PASS"
		if errors != nil && errors.(float64) > 0 {
			status = "FAIL"
		}

		fmt.Printf("\nERC %s: %v errors, %v warnings\n", status, errors, warnings)

		if violations, ok := result["violations"].([]interface{}); ok && len(violations) > 0 {
			fmt.Println("\nViolations:")
			for i, v := range violations {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(violations)-10)
					break
				}
				m := v.(map[string]interface{})
				fmt.Printf("  [%v] %v\n", m["severity"], m["type"])
			}
		}

		if status == "PASS" {
			fmt.Println("\nNext: parts eda ctrl netlist-diff --old <old.kicad_sch> --new <new.kicad_sch>")
		} else {
			fmt.Println("\nFix ERC errors, then re-run: parts eda ctrl erc <file>")
		}
		return nil
	},
}

// --- Station 0b: Netlist Diff ---

var edaCtrlNetlistDiff = &cobra.Command{
	Use:   "netlist-diff",
	Short: "Compare two schematic netlists for connectivity changes",
	Long: `Upload old and new .kicad_sch files and diff their netlists.

Shows added/removed/changed nets and components.
The changed nets are the ones that need PCB rerouting.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		oldPath, _ := cmd.Flags().GetString("old")
		newPath, _ := cmd.Flags().GetString("new")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if oldPath == "" || newPath == "" {
			return fmt.Errorf("--old and --new are required")
		}

		fmt.Printf("Diffing netlists: %s → %s\n", filepath.Base(oldPath), filepath.Base(newPath))

		// Upload both files as multipart
		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "old_file", oldPath); err != nil {
			return err
		}
		if err := addFileToMultipart(writer, "new_file", newPath); err != nil {
			return err
		}
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/eda/netlist/diff", domain.API)
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

		fmt.Printf("\n%s\n", result["summary"])

		if nets, ok := result["nets"].(map[string]interface{}); ok {
			if changed, ok := nets["changed_detail"].(map[string]interface{}); ok && len(changed) > 0 {
				fmt.Println("\nChanged nets (need PCB rerouting):")
				for name, info := range changed {
					m := info.(map[string]interface{})
					added := m["added_connections"]
					removed := m["removed_connections"]
					fmt.Printf("  %s: +%v -%v connections\n", name, added, removed)
				}
			}
		}

		fmt.Println("\nNext: parts eda ctrl analyze <file.kicad_pcb> --nets <changed-net-names>")
		return nil
	},
}

// --- Station 1: Analyze ---

var edaCtrlAnalyze = &cobra.Command{
	Use:   "analyze <file.kicad_pcb>",
	Short: "Analyze a PCB for affected nets",
	Long: `Upload a .kicad_pcb file to the API and identify affected nets.

Returns a net inventory with track/via counts per net.
Review the results before proceeding to propose.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		ecnID, _ := cmd.Flags().GetString("ecn")
		netsFlag, _ := cmd.Flags().GetString("nets")
		jsonOut, _ := cmd.Flags().GetBool("json")

		fields := map[string]string{}
		if ecnID != "" {
			fields["ecn_id"] = ecnID
		}
		if netsFlag != "" {
			nets := strings.Split(netsFlag, ",")
			netsJSON, _ := json.Marshal(nets)
			fields["net_names_json"] = string(netsJSON)
		}

		fmt.Printf("Analyzing %s...\n", filepath.Base(pcbPath))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/analyze", fields)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		nets, ok := result["nets"].(map[string]interface{})
		if !ok {
			fmt.Println("No nets found.")
			return nil
		}

		fmt.Printf("\nAffected nets (%d):\n", len(nets))
		for name, info := range nets {
			m := info.(map[string]interface{})
			tracks := m["tracks"]
			vias := m["vias"]
			layers := m["layers"]
			fmt.Printf("  %-30s  %v tracks, %v vias  [%v]\n", name, tracks, vias, layers)
		}
		fmt.Println("\nNext: parts eda ctrl propose <file> --nets <net1,net2,...>")
		return nil
	},
}

// --- Station 2: Propose Rip-up ---

var edaCtrlProposeRipup = &cobra.Command{
	Use:   "propose <file.kicad_pcb>",
	Short: "Enumerate tracks/vias that would be removed",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		netsFlag, _ := cmd.Flags().GetString("nets")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if netsFlag == "" {
			return fmt.Errorf("--nets is required")
		}

		nets := strings.Split(netsFlag, ",")
		netsJSON, _ := json.Marshal(nets)

		fmt.Printf("Proposing rip-up for %d nets...\n", len(nets))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/ripup/propose", map[string]string{
			"net_names_json": string(netsJSON),
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nProposal: %v tracks, %v vias across %v nets\n",
			result["total_tracks"], result["total_vias"], result["net_count"])

		if proposal, ok := result["proposal"].(map[string]interface{}); ok {
			for name, info := range proposal {
				m := info.(map[string]interface{})
				fmt.Printf("  %-30s  %v tracks, %v vias\n", name, m["tracks"], m["vias"])
			}
		}
		fmt.Println("\nNext: parts eda ctrl ripup <file> --nets <...> [--apply]")
		return nil
	},
}

// --- Station 3: Execute Rip-up ---

var edaCtrlExecuteRipup = &cobra.Command{
	Use:   "ripup <file.kicad_pcb>",
	Short: "Remove tracks/vias and return a diff",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		netsFlag, _ := cmd.Flags().GetString("nets")
		apply, _ := cmd.Flags().GetBool("apply")

		if netsFlag == "" {
			return fmt.Errorf("--nets is required")
		}

		nets := strings.Split(netsFlag, ",")
		netsJSON, _ := json.Marshal(nets)

		fmt.Printf("Executing rip-up for %d nets...\n", len(nets))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/ripup/execute", map[string]string{
			"net_names_json": string(netsJSON),
		})
		if err != nil {
			return err
		}

		diff, _ := result["diff"].(string)
		fmt.Printf("\nRemoved: %v tracks, %v vias (%v diff lines)\n",
			result["tracks_removed"], result["vias_removed"], result["diff_lines"])

		if apply && diff != "" {
			// Write diff to temp file and apply with patch
			tmpFile, err := os.CreateTemp("", "eda-ripup-*.diff")
			if err != nil {
				return fmt.Errorf("failed to create temp file: %w", err)
			}
			if _, err := tmpFile.WriteString(diff); err != nil {
				tmpFile.Close()
				return fmt.Errorf("failed to write diff: %w", err)
			}
			tmpFile.Close()
			defer os.Remove(tmpFile.Name())

			fmt.Printf("Applying diff to %s...\n", pcbPath)
			patchCmd := exec.Command("patch", "-p1", "--no-backup-if-mismatch", "-i", tmpFile.Name(), pcbPath)
			patchCmd.Stdout = os.Stdout
			patchCmd.Stderr = os.Stderr
			if err := patchCmd.Run(); err != nil {
				fmt.Printf("Warning: patch failed (%v), trying manual apply...\n", err)
				// Fallback: the API should return modified_content
				if modified, ok := result["modified_content"].(string); ok && modified != "" {
					if err := os.WriteFile(pcbPath, []byte(modified), 0644); err != nil {
						return fmt.Errorf("failed to write modified PCB: %w", err)
					}
					fmt.Println("Applied via file replacement.")
				} else {
					return fmt.Errorf("patch failed and no modified_content in response")
				}
			} else {
				fmt.Println("Diff applied successfully.")
			}
		} else if diff != "" {
			fmt.Println("\n--- Unified Diff ---")
			fmt.Println(diff)
			fmt.Println("--- End Diff ---")
			fmt.Println("\nUse --apply to apply the diff to the local file.")
		}

		fmt.Println("\nNext: Open in KiCad, reroute, then: parts eda ctrl validate <file>")
		return nil
	},
}

// --- Station 4: Validate (DRC) ---

var edaCtrlValidate = &cobra.Command{
	Use:   "validate <file.kicad_pcb>",
	Short: "Run Design Rule Check",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		jsonOut, _ := cmd.Flags().GetBool("json")

		fmt.Printf("Running DRC on %s...\n", filepath.Base(pcbPath))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/drc", nil)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		errors := result["error_count"]
		warnings := result["warning_count"]
		unconnected := result["unconnected_count"]

		status := "PASS"
		if errors != nil && errors.(float64) > 0 {
			status = "FAIL"
		}

		fmt.Printf("\nDRC %s: %v errors, %v warnings, %v unconnected\n", status, errors, warnings, unconnected)

		if violations, ok := result["violations"].([]interface{}); ok && len(violations) > 0 {
			fmt.Println("\nViolations:")
			for i, v := range violations {
				if i >= 10 {
					fmt.Printf("  ... and %d more\n", len(violations)-10)
					break
				}
				m := v.(map[string]interface{})
				fmt.Printf("  [%v] %v\n", m["severity"], m["type"])
			}
		}

		if status == "PASS" {
			fmt.Println("\nNext: parts eda ctrl export <file> --output <dir>")
		} else {
			fmt.Println("\nFix errors in KiCad, then re-run: parts eda ctrl validate <file>")
		}
		return nil
	},
}

// --- Station 5: Export ---

var edaCtrlExport = &cobra.Command{
	Use:   "export <file.kicad_pcb>",
	Short: "Export gerbers, drill files, and positions",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		outputDir, _ := cmd.Flags().GetString("output")

		if outputDir == "" {
			outputDir = filepath.Join(filepath.Dir(pcbPath), "CAM")
		}
		os.MkdirAll(outputDir, 0755)
		outputPath := filepath.Join(outputDir, "gerbers.zip")

		fmt.Printf("Exporting gerbers from %s...\n", filepath.Base(pcbPath))
		err := uploadAndDownloadFile(nil, pcbPath, outputPath, "/v1/eda/export", nil)
		if err != nil {
			return err
		}

		fmt.Printf("\nExported to %s\n", outputPath)
		return nil
	},
}

func init() {
	// Analyze flags
	edaCtrlAnalyze.Flags().String("ecn", "", "ECN ID to extract affected nets")
	edaCtrlAnalyze.Flags().String("nets", "", "Comma-separated net names")
	edaCtrlAnalyze.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Propose-ripup flags
	edaCtrlProposeRipup.Flags().String("nets", "", "Comma-separated net names (required)")
	edaCtrlProposeRipup.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Execute-ripup flags
	edaCtrlExecuteRipup.Flags().String("nets", "", "Comma-separated net names (required)")
	edaCtrlExecuteRipup.Flags().Bool("apply", false, "Apply the diff to the local file")

	// Validate flags
	edaCtrlValidate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Export flags
	edaCtrlExport.Flags().StringP("output", "o", "", "Output directory (default: CAM/ next to PCB)")

	// ERC flags
	edaCtrlERC.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Netlist diff flags
	edaCtrlNetlistDiff.Flags().String("old", "", "Path to old .kicad_sch (required)")
	edaCtrlNetlistDiff.Flags().String("new", "", "Path to new .kicad_sch (required)")
	edaCtrlNetlistDiff.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up
	edaCtrl.AddCommand(edaCtrlERC)
	edaCtrl.AddCommand(edaCtrlNetlistDiff)
	edaCtrl.AddCommand(edaCtrlAnalyze)
	edaCtrl.AddCommand(edaCtrlProposeRipup)
	edaCtrl.AddCommand(edaCtrlExecuteRipup)
	edaCtrl.AddCommand(edaCtrlValidate)
	edaCtrl.AddCommand(edaCtrlExport)
}
