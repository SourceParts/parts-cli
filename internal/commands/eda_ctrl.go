package commands

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

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

	// Auto-upload companion files (.kicad_dru, .kicad_pro) from same directory
	dir := filepath.Dir(pcbPath)
	base := strings.TrimSuffix(filepath.Base(pcbPath), filepath.Ext(pcbPath))
	companions := []string{".kicad_dru", ".kicad_pro"}
	for _, ext := range companions {
		compPath := filepath.Join(dir, base+ext)
		if _, err := os.Stat(compPath); err == nil {
			fieldName := "companion_" + strings.TrimPrefix(ext, ".")
			_ = addFileToMultipart(writer, fieldName, compPath)
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
	if apiKey := Client.GetAPIKey(); apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
		req.Header.Set("X-API-Key", apiKey)
	}

	// SHA256 hash for server-side caching
	if hash := computeFileHash(pcbPath); hash != "" {
		req.Header.Set("X-PCB-Hash", hash)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted {
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}
	return result, nil
}

// getJSON makes an authenticated GET request and returns JSON.
func getJSON(endpoint string) (map[string]interface{}, error) {
	url := fmt.Sprintf("https://%s%s", domain.API, endpoint)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if apiKey := Client.GetAPIKey(); apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
		req.Header.Set("X-API-Key", apiKey)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse: %w", err)
	}
	return result, nil
}

// --- Async PCB Job ---

var edaCtrlJob = &cobra.Command{
	Use:   "job <file.kicad_pcb>",
	Short: "Submit an async PCB operation and poll for result",
	Long: `Submit a heavy PCB operation to the async job queue.
Bypasses Cloudflare timeout by processing via the worker service.

Examples:
  parts eda ctrl job board.kicad_pcb --op reassign --payload '{"assignments": [...]}'
  parts eda ctrl job board.kicad_pcb --op validate
  parts eda ctrl job board.kicad_pcb --op ripup --payload '{"net_names": ["LED_R1"]}'`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		operation, _ := cmd.Flags().GetString("op")
		payloadJSON, _ := cmd.Flags().GetString("payload")
		noWait, _ := cmd.Flags().GetBool("no-wait")

		if operation == "" {
			return fmt.Errorf("--op is required (validate, reassign, place, resize, ripup, remove-footprints, export)")
		}
		if payloadJSON == "" {
			payloadJSON = "{}"
		}

		fmt.Printf("Submitting async %s job...\n", operation)
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/pcb/job", map[string]string{
			"operation":    operation,
			"payload_json": payloadJSON,
		})
		if err != nil {
			return err
		}

		jobID, _ := result["job_id"].(string)
		statusURL, _ := result["status_url"].(string)
		fmt.Printf("Job submitted: %s\n", jobID)
		fmt.Printf("Status URL: %s\n", statusURL)

		if noWait {
			fmt.Println("Use --no-wait=false to poll for completion.")
			return nil
		}

		// Poll for completion
		fmt.Print("Waiting")
		for i := 0; i < 150; i++ { // 5 min max (150 * 2s)
			time.Sleep(2 * time.Second)
			fmt.Print(".")

			status, err := getJSON(statusURL)
			if err != nil {
				fmt.Printf("\nPoll error: %v\n", err)
				continue
			}

			s, _ := status["status"].(string)
			switch s {
			case "done":
				fmt.Printf("\nJob %s completed!\n", jobID)
				if bs, ok := status["board_stats"].(map[string]interface{}); ok {
					fmt.Printf("Board: %.1f mm², Fill: %.1f%%, %v footprints\n",
						bs["board_area_mm2"], bs["fill_pct"], bs["footprints"])
				}
				if stats, ok := status["stats"].(map[string]interface{}); ok {
					enc := json.NewEncoder(os.Stdout)
					enc.SetIndent("", "  ")
					enc.Encode(stats)
				}
				if dl, ok := status["diff_lines"].(float64); ok && dl > 0 {
					fmt.Printf("Diff: %.0f lines\n", dl)
				}
				if url, ok := status["result_url"].(string); ok && url != "" {
					fmt.Printf("Result: %s\n", url)
				}
				return nil

			case "failed":
				errMsg, _ := status["error"].(string)
				return fmt.Errorf("job failed: %s", errMsg)

			case "pending", "processing":
				continue

			default:
				continue
			}
		}

		return fmt.Errorf("job %s timed out after 5 minutes", jobID)
	},
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

// --- Station 3b: Remove Footprints ---

var edaCtrlRemoveFootprints = &cobra.Command{
	Use:   "remove <file.kicad_pcb>",
	Short: "Remove footprints by reference designator",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		refsFlag, _ := cmd.Flags().GetString("refs")
		apply, _ := cmd.Flags().GetBool("apply")

		if refsFlag == "" {
			return fmt.Errorf("--refs is required (e.g. --refs Q11,Q12,R4)")
		}

		refs := strings.Split(refsFlag, ",")
		for i := range refs {
			refs[i] = strings.TrimSpace(refs[i])
		}
		refsJSON, _ := json.Marshal(refs)

		fmt.Printf("Removing %d footprints...\n", len(refs))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/pcb/remove-footprints", map[string]string{
			"refs_json": string(refsJSON),
		})
		if err != nil {
			return err
		}

		fmt.Printf("\nRemoved: %v footprints (%v pads)\n",
			result["footprints_removed"], result["pads_removed"])
		fmt.Printf("Orphan copper cleaned: %v tracks, %v vias\n",
			result["orphan_tracks"], result["orphan_vias"])

		if found, ok := result["refs_found"].([]interface{}); ok {
			fmt.Printf("Found: %v\n", found)
		}
		if orphanNets, ok := result["orphan_nets"].([]interface{}); ok && len(orphanNets) > 0 {
			fmt.Printf("Orphan nets removed: %v\n", orphanNets)
		}

		if requested, ok := result["refs_requested"].([]interface{}); ok {
			if found, ok2 := result["refs_found"].([]interface{}); ok2 {
				if len(found) < len(requested) {
					fmt.Printf("\nWarning: %d refs not found in PCB\n", len(requested)-len(found))
				}
			}
		}

		if apply {
			if modified, ok := result["modified_content"].(string); ok && modified != "" {
				if err := os.WriteFile(pcbPath, []byte(modified), 0644); err != nil {
					return fmt.Errorf("failed to write modified PCB: %w", err)
				}
				fmt.Printf("Applied to %s\n", pcbPath)
			} else {
				return fmt.Errorf("no modified_content in response")
			}
		} else {
			diff, _ := result["diff"].(string)
			if diff != "" {
				fmt.Println("\n--- Unified Diff ---")
				fmt.Println(diff[:min(len(diff), 2000)])
				if len(diff) > 2000 {
					fmt.Printf("... (%d more lines)\n", result["diff_lines"])
				}
				fmt.Println("--- End Diff ---")
			}
			fmt.Println("\nUse --apply to apply changes to the local file.")
		}

		fmt.Println("\nNext: parts eda ctrl validate <file>")
		return nil
	},
}

// --- Station 3c: Place Footprints ---

var edaCtrlPlace = &cobra.Command{
	Use:   "place <file.kicad_pcb>",
	Short: "Place new footprints on a PCB",
	Long: `Place footprints at specified coordinates.

Pass placements as JSON via --placements flag:
  [{"ref":"LED1","footprint":"1010","x":103.25,"y":136.97,"layer":"B.Cu","value":"APA-104"}]

Supported package sizes: 0201, 0402, 0603, 0805, 1010 (4-pad LED)
Or use KiCad library format: Resistor_SMD:R_0402_1005Metric`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		placementsJSON, _ := cmd.Flags().GetString("placements")
		apply, _ := cmd.Flags().GetBool("apply")

		if placementsJSON == "" {
			return fmt.Errorf("--placements is required (JSON array)")
		}

		// Validate JSON
		var placements []map[string]interface{}
		if err := json.Unmarshal([]byte(placementsJSON), &placements); err != nil {
			return fmt.Errorf("invalid placements JSON: %w", err)
		}

		fmt.Printf("Placing %d footprints...\n", len(placements))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/pcb/place", map[string]string{
			"placements_json": placementsJSON,
		})
		if err != nil {
			return err
		}

		if placed, ok := result["placed"].([]interface{}); ok {
			fmt.Printf("\nPlaced: %d footprints\n", len(placed))
			for _, p := range placed {
				m := p.(map[string]interface{})
				fmt.Printf("  %v (%v, %v)\n", m["ref"], m["pkg"], m["source"])
			}
		}
		if errs, ok := result["errors"].([]interface{}); ok && len(errs) > 0 {
			fmt.Printf("\nErrors: %d\n", len(errs))
			for _, e := range errs {
				fmt.Printf("  %v\n", e)
			}
		}

		if stats, ok := result["board_stats"].(map[string]interface{}); ok && len(stats) > 0 {
			fmt.Printf("\nBoard: %.1f mm², Fill: %.1f%% (%v footprints)\n",
				stats["board_area_mm2"], stats["fill_pct"], stats["footprints"])
		}

		if apply {
			if modified, ok := result["modified_content"].(string); ok && modified != "" {
				if err := os.WriteFile(pcbPath, []byte(modified), 0644); err != nil {
					return fmt.Errorf("failed to write modified PCB: %w", err)
				}
				fmt.Printf("Applied to %s\n", pcbPath)
			} else {
				return fmt.Errorf("no modified_content in response")
			}
		} else {
			fmt.Println("\nUse --apply to apply changes to the local file.")
		}

		return nil
	},
}

// --- Station 3d: Resize Footprints ---

var edaCtrlResize = &cobra.Command{
	Use:   "resize <file.kicad_pcb>",
	Short: "Resize footprint pads to a different package",
	Long: `Resize footprint pads to a target package size.

Pass resizes as JSON via --resizes flag:
  [{"ref":"C9","target_pkg":"0805"},{"ref":"C13","target_pkg":"0805"}]

Or use shorthand: --refs C9,C13,C17 --target 0805`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		resizesJSON, _ := cmd.Flags().GetString("resizes")
		refsFlag, _ := cmd.Flags().GetString("refs")
		target, _ := cmd.Flags().GetString("target")
		apply, _ := cmd.Flags().GetBool("apply")

		// Build resizes from either --resizes JSON or --refs + --target
		if resizesJSON == "" && refsFlag != "" && target != "" {
			refs := strings.Split(refsFlag, ",")
			var resizes []map[string]string
			for _, r := range refs {
				resizes = append(resizes, map[string]string{
					"ref": strings.TrimSpace(r), "target_pkg": target,
				})
			}
			b, _ := json.Marshal(resizes)
			resizesJSON = string(b)
		}

		if resizesJSON == "" {
			return fmt.Errorf("--resizes JSON or --refs + --target required")
		}

		var resizes []map[string]string
		if err := json.Unmarshal([]byte(resizesJSON), &resizes); err != nil {
			return fmt.Errorf("invalid resizes JSON: %w", err)
		}

		fmt.Printf("Resizing %d footprints...\n", len(resizes))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/pcb/resize", map[string]string{
			"resizes_json": resizesJSON,
		})
		if err != nil {
			return err
		}

		if resized, ok := result["resized"].([]interface{}); ok {
			fmt.Printf("\nResized: %d footprints\n", len(resized))
			for _, r := range resized {
				m := r.(map[string]interface{})
				fmt.Printf("  %v: %v → %v\n", m["ref"], m["from"], m["to"])
			}
		}
		if errs, ok := result["errors"].([]interface{}); ok && len(errs) > 0 {
			fmt.Printf("\nErrors: %d\n", len(errs))
			for _, e := range errs {
				fmt.Printf("  %v\n", e)
			}
		}

		if stats, ok := result["board_stats"].(map[string]interface{}); ok && len(stats) > 0 {
			fmt.Printf("\nBoard: %.1f mm², Fill: %.1f%% (%v footprints)\n",
				stats["board_area_mm2"], stats["fill_pct"], stats["footprints"])
		}

		if apply {
			if modified, ok := result["modified_content"].(string); ok && modified != "" {
				if err := os.WriteFile(pcbPath, []byte(modified), 0644); err != nil {
					return fmt.Errorf("failed to write modified PCB: %w", err)
				}
				fmt.Printf("Applied to %s\n", pcbPath)
			} else {
				return fmt.Errorf("no modified_content in response")
			}
		} else {
			fmt.Println("\nUse --apply to apply changes to the local file.")
		}

		return nil
	},
}

// --- Station 3e: Reassign Nets / Move ---

var edaCtrlReassign = &cobra.Command{
	Use:   "reassign <file.kicad_pcb>",
	Short: "Reassign pad nets, merge nets, or move footprints",
	Long: `Reassign nets and move components on a PCB.

Pass assignments as JSON via --assignments flag:
  [{"net_from":"VOUT1","net_to":"VOUT1V8"}]                    — merge nets
  [{"ref":"R23","pad":"1","net_name":"TWI0_SDA"}]               — reassign pad
  [{"ref":"R7","x":96.0,"y":152.0}]                            — move footprint`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		assignmentsJSON, _ := cmd.Flags().GetString("assignments")
		apply, _ := cmd.Flags().GetBool("apply")

		if assignmentsJSON == "" {
			return fmt.Errorf("--assignments is required (JSON array)")
		}

		var assignments []map[string]interface{}
		if err := json.Unmarshal([]byte(assignmentsJSON), &assignments); err != nil {
			return fmt.Errorf("invalid assignments JSON: %w", err)
		}

		fmt.Printf("Applying %d assignments...\n", len(assignments))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/pcb/reassign", map[string]string{
			"assignments_json": assignmentsJSON,
		})
		if err != nil {
			return err
		}

		if changes, ok := result["changes"].([]interface{}); ok {
			fmt.Printf("\nChanges: %d\n", len(changes))
			for _, c := range changes {
				m := c.(map[string]interface{})
				switch m["type"] {
				case "net_merge":
					fmt.Printf("  merge: %v → %v (%v pads, %v tracks)\n", m["from"], m["to"], m["pads"], m["tracks"])
				case "pad_reassign":
					fmt.Printf("  pad: %v.%v  %v → %v\n", m["ref"], m["pad"], m["from"], m["to"])
				case "move":
					fmt.Printf("  move: %v  %v → %v\n", m["ref"], m["from"], m["to"])
				}
			}
		}

		if errs, ok := result["errors"].([]interface{}); ok && len(errs) > 0 {
			fmt.Printf("\nErrors: %d\n", len(errs))
			for _, e := range errs {
				fmt.Printf("  %v\n", e)
			}
		}

		if stats, ok := result["board_stats"].(map[string]interface{}); ok && len(stats) > 0 {
			fmt.Printf("\nBoard: %.1f mm², Fill: %.1f%% (%v footprints)\n",
				stats["board_area_mm2"], stats["fill_pct"], stats["footprints"])
		}

		if apply {
			if modified, ok := result["modified_content"].(string); ok && modified != "" {
				if err := os.WriteFile(pcbPath, []byte(modified), 0644); err != nil {
					return fmt.Errorf("failed to write: %w", err)
				}
				fmt.Printf("Applied to %s\n", pcbPath)
			} else {
				return fmt.Errorf("no modified_content in response")
			}
		} else {
			fmt.Println("\nUse --apply to apply changes to the local file.")
		}

		return nil
	},
}

func computeFileHash(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return ""
	}
	return hex.EncodeToString(h.Sum(nil))
}

// --- Station 3f: Zone Refill ---

var edaCtrlRefill = &cobra.Command{
	Use:   "refill <file.kicad_pcb>",
	Short: "Refill all zones (fixes Altium-converted fill polygons)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		pcbPath := args[0]
		apply, _ := cmd.Flags().GetBool("apply")

		fmt.Printf("Refilling zones in %s...\n", filepath.Base(pcbPath))
		result, err := uploadAndGetJSON(pcbPath, "/v1/eda/pcb/refill", nil)
		if err != nil {
			return err
		}

		changed, _ := result["changed"].(bool)
		diffLines, _ := result["diff_lines"].(float64)

		if changed {
			fmt.Printf("Zones refilled (%d lines changed)\n", int(diffLines))
		} else {
			fmt.Println("No zones changed")
		}

		if stats, ok := result["board_stats"].(map[string]interface{}); ok && len(stats) > 0 {
			fmt.Printf("Board: %.1f mm², Fill: %.1f%%, %v footprints\n",
				stats["board_area_mm2"], stats["fill_pct"], stats["footprints"])
		}

		if apply && changed {
			if modified, ok := result["modified_content"].(string); ok && modified != "" {
				if err := os.WriteFile(pcbPath, []byte(modified), 0644); err != nil {
					return fmt.Errorf("failed to write: %w", err)
				}
				fmt.Printf("Applied to %s\n", pcbPath)
			}
		} else if changed {
			fmt.Println("Use --apply to save refilled zones to the local file.")
		}

		return nil
	},
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
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

		if stats, ok := result["board_stats"].(map[string]interface{}); ok && len(stats) > 0 {
			fmt.Printf("\nBoard: %.1f x %.1f mm (%.1f mm²)\n",
				stats["board_width_mm"], stats["board_height_mm"], stats["board_area_mm2"])
			fmt.Printf("Fill:  %.1f%% (%v footprints, %.1f mm² component area)\n",
				stats["fill_pct"], stats["footprints"], stats["component_area_mm2"])
			fmt.Printf("Copper: %v tracks, %v vias, %v zones\n",
				stats["tracks"], stats["vias"], stats["zones"])
		}

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

	// Remove footprints flags
	edaCtrlRemoveFootprints.Flags().String("refs", "", "Comma-separated reference designators (required)")
	edaCtrlRemoveFootprints.Flags().Bool("apply", false, "Apply changes to the local file")

	// Place footprints flags
	edaCtrlPlace.Flags().String("placements", "", "JSON array of placement objects (required)")
	edaCtrlPlace.Flags().Bool("apply", false, "Apply changes to the local file")

	// Resize footprints flags
	edaCtrlResize.Flags().String("resizes", "", "JSON array of {ref, target_pkg} objects")
	edaCtrlResize.Flags().String("refs", "", "Comma-separated refs (use with --target)")
	edaCtrlResize.Flags().String("target", "", "Target package size (e.g. 0805)")
	edaCtrlResize.Flags().Bool("apply", false, "Apply changes to the local file")

	// Job flags
	edaCtrlJob.Flags().String("op", "", "Operation: validate, reassign, place, resize, ripup, remove-footprints, export")
	edaCtrlJob.Flags().String("payload", "", "Operation payload JSON")
	edaCtrlJob.Flags().Bool("no-wait", false, "Submit and exit without polling")

	// Reassign flags
	edaCtrlReassign.Flags().String("assignments", "", "JSON array of assignment objects (required)")
	edaCtrlReassign.Flags().Bool("apply", false, "Apply changes to the local file")

	// Refill flags
	edaCtrlRefill.Flags().Bool("apply", false, "Apply refilled zones to the local file")

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
	edaCtrl.AddCommand(edaCtrlRemoveFootprints)
	edaCtrl.AddCommand(edaCtrlPlace)
	edaCtrl.AddCommand(edaCtrlResize)
	edaCtrl.AddCommand(edaCtrlReassign)
	edaCtrl.AddCommand(edaCtrlJob)
	edaCtrl.AddCommand(edaCtrlRefill)
	edaCtrl.AddCommand(edaCtrlValidate)
	edaCtrl.AddCommand(edaCtrlExport)
}
