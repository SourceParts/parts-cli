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
// Logistics — AOI-style operator-approved shipping & logistics pipeline
// =============================================================================

var Logistics = &cobra.Command{
	Use:   "logistics",
	Short: "Shipping & logistics pipeline (shipment, customs, consignment, inventory)",
	Long: `AOI-style operator-approved shipping & logistics pipeline.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. shipment create        — create shipment with label + customs
  2. shipment track         — track a shipment
  3. customs declare        — map BOM to HS codes + declared values
  4. consignment manifest   — diff BOM vs inventory for CM shipment
  5. inventory reconcile    — reconcile physical count vs system inventory`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var logisticsShipment = &cobra.Command{
	Use:   "shipment",
	Short: "Shipment operations (create, track)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var logisticsCustoms = &cobra.Command{
	Use:   "customs",
	Short: "Customs operations (declare)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var logisticsConsignment = &cobra.Command{
	Use:   "consignment",
	Short: "Consignment operations (manifest)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var logisticsInventory = &cobra.Command{
	Use:   "inventory",
	Short: "Inventory operations (reconcile)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// --- Station 1: Shipment Create ---

var logisticsShipmentCreate = &cobra.Command{
	Use:   "create",
	Short: "Create a shipment with label and customs docs",
	Long: `Create a shipment for an order. Generates shipping label data,
packing list, and customs declaration for international shipments.

Review shipment details and label before dispatching.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		orderID, _ := cmd.Flags().GetString("order")
		destination, _ := cmd.Flags().GetString("destination")
		carrier, _ := cmd.Flags().GetString("carrier")
		weightKg, _ := cmd.Flags().GetFloat64("weight")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if orderID == "" {
			return fmt.Errorf("--order is required")
		}
		if destination == "" {
			return fmt.Errorf("--destination is required")
		}

		fmt.Printf("Creating shipment for order %s via %s...\n", orderID, carrier)

		payload := map[string]interface{}{
			"order_id": orderID,
			"destination": map[string]string{
				"street": destination,
			},
			"carrier": carrier,
			"package": map[string]interface{}{
				"weight_kg": weightKg,
			},
		}

		result, err := postJSONAndGetJSON("/v1/logistics/shipment/create", payload)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nShipment:  %v\n", result["shipment_id"])
		fmt.Printf("Order:     %v\n", result["order_id"])
		fmt.Printf("Tracking:  %v\n", result["tracking_number"])
		fmt.Printf("Carrier:   %v\n", result["carrier"])
		fmt.Printf("Label:     %v\n", result["label_url"])
		fmt.Printf("\n  Estimated Cost:     $%.2f\n", toFloat(result["estimated_cost"]))
		fmt.Printf("  Estimated Delivery: %v\n", result["estimated_delivery"])

		international, _ := result["international"].(bool)
		if international {
			fmt.Println("  International:      Yes (customs declaration generated)")
		} else {
			fmt.Println("  International:      No")
		}

		fmt.Println("\nNext: parts logistics shipment track --shipment <id> --carrier", carrier)
		return nil
	},
}

// --- Station 2: Shipment Track ---

var logisticsShipmentTrack = &cobra.Command{
	Use:   "track",
	Short: "Track a shipment by ID or tracking number",
	Long: `Query tracking events for a shipment. Shows timestamps,
locations, and status updates.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		shipmentID, _ := cmd.Flags().GetString("shipment")
		carrier, _ := cmd.Flags().GetString("carrier")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if shipmentID == "" {
			return fmt.Errorf("--shipment is required")
		}

		fmt.Printf("Tracking shipment %s...\n", shipmentID)

		result, err := postJSONAndGetJSON("/v1/logistics/shipment/track", map[string]interface{}{
			"shipment_id": shipmentID,
			"carrier":     carrier,
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nShipment: %v\n", result["shipment_id"])
		fmt.Printf("Status:   %v\n", result["current_status"])
		fmt.Printf("ETA:      %v\n", result["eta"])

		if events, ok := result["events"].([]interface{}); ok && len(events) > 0 {
			fmt.Println("\nTracking Events:")
			for _, event := range events {
				m := event.(map[string]interface{})
				ts, _ := m["timestamp"].(string)
				if len(ts) > 16 {
					ts = ts[:16]
				}
				fmt.Printf("  [%s] %-25v %v\n", ts, m["location"], m["description"])
			}
		}

		status, _ := result["current_status"].(string)
		if status == "delivered" {
			fmt.Println("\nShipment delivered. Confirm receipt with recipient.")
		} else {
			fmt.Println("\nNext: Track again later for updated status.")
		}
		return nil
	},
}

// --- Station 3: Customs Declare ---

var logisticsCustomsDeclare = &cobra.Command{
	Use:   "declare <bom.csv>",
	Short: "Map BOM components to HS codes and calculate declared values",
	Long: `Upload a BOM file and generate a customs declaration.
Maps components to HS codes by category (ICs->8542, passives->8532,
connectors->8536, PCBs->8534).

Review HS codes and declared values before submitting to customs.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		invoiceAmount, _ := cmd.Flags().GetFloat64("invoice-amount")
		destCountry, _ := cmd.Flags().GetString("destination")
		originCountry, _ := cmd.Flags().GetString("origin")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if invoiceAmount <= 0 {
			return fmt.Errorf("--invoice-amount must be positive")
		}
		if destCountry == "" {
			return fmt.Errorf("--destination is required")
		}

		fmt.Printf("Generating customs declaration for %s (%s -> %s)...\n",
			filepath.Base(bomPath), originCountry, destCountry)

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.WriteField("invoice_amount", fmt.Sprintf("%.2f", invoiceAmount))
		writer.WriteField("destination_country", destCountry)
		writer.WriteField("origin_country", originCountry)
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/logistics/customs/declare", domain.API)
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

		fmt.Printf("\nDeclaration: %v\n", result["declaration_id"])
		fmt.Printf("Route:       %v -> %v\n", result["origin_country"], result["destination_country"])
		fmt.Printf("Line Items:  %v\n", result["total_line_items"])
		fmt.Printf("Total Declared Value: $%.2f\n", toFloat(result["total_declared_value"]))
		fmt.Printf("Invoice Amount:       $%.2f\n", toFloat(result["invoice_amount"]))

		if lineItems, ok := result["line_items"].([]interface{}); ok && len(lineItems) > 0 {
			fmt.Println("\nLine Items:")
			fmt.Printf("  %-30s %-8s %8s %12s\n", "Description", "HS Code", "Qty", "Value")
			fmt.Printf("  %-30s %-8s %8s %12s\n", "------------------------------", "--------", "--------", "------------")
			for i, item := range lineItems {
				if i >= 20 {
					fmt.Printf("  ... and %d more\n", len(lineItems)-20)
					break
				}
				m := item.(map[string]interface{})
				desc, _ := m["description"].(string)
				if len(desc) > 30 {
					desc = desc[:27] + "..."
				}
				fmt.Printf("  %-30s %-8v %8v $%10.2f\n",
					desc, m["hs_code"], m["quantity"], toFloat(m["total_value"]))
			}
		}

		fmt.Println("\nNext: parts logistics shipment create --order <id> --destination <addr> --carrier dhl")
		return nil
	},
}

// --- Station 4: Consignment Manifest ---

var logisticsConsignmentManifest = &cobra.Command{
	Use:   "manifest <bom.csv>",
	Short: "Diff BOM vs inventory to generate consignment manifest",
	Long: `Upload a BOM file and compare against CM inventory levels.
Generates a manifest of what needs to be shipped to the CM.

Review the manifest before shipping. Verify short items.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		inventoryPath, _ := cmd.Flags().GetString("inventory")
		cmAddress, _ := cmd.Flags().GetString("cm-address")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if cmAddress == "" {
			return fmt.Errorf("--cm-address is required")
		}

		// Read inventory file as JSON mapping if provided
		inventoryLevels := "{}"
		if inventoryPath != "" {
			data, err := os.ReadFile(inventoryPath)
			if err != nil {
				return fmt.Errorf("failed to read inventory file: %w", err)
			}
			inventoryLevels = string(data)
		}

		fmt.Printf("Generating consignment manifest from %s...\n", filepath.Base(bomPath))

		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.WriteField("inventory_levels", inventoryLevels)
		writer.WriteField("cm_address", cmAddress)
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/logistics/consignment/manifest", domain.API)
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

		fmt.Printf("\nManifest:  %v\n", result["manifest_id"])
		fmt.Printf("CM:        %v\n", result["cm_address"])
		fmt.Printf("\n  Items to ship:  %v\n", result["total_items_to_ship"])
		fmt.Printf("  Items on hand:  %v\n", result["total_items_on_hand"])
		fmt.Printf("  Items short:    %v\n", result["total_items_short"])
		fmt.Printf("  Est. packages:  %v\n", result["total_packages"])
		fmt.Printf("  Est. weight:    %v kg\n", result["total_weight_estimate_kg"])

		if shortItems, ok := result["items_short"].([]interface{}); ok && len(shortItems) > 0 {
			fmt.Println("\nShort Items (need procurement):")
			fmt.Printf("  %-20s %10s %10s %10s\n", "Part Number", "Needed", "On Hand", "Short")
			fmt.Printf("  %-20s %10s %10s %10s\n", "--------------------", "----------", "----------", "----------")
			for i, item := range shortItems {
				if i >= 15 {
					fmt.Printf("  ... and %d more\n", len(shortItems)-15)
					break
				}
				m := item.(map[string]interface{})
				fmt.Printf("  %-20v %10v %10v %10v\n",
					m["part_number"], m["quantity_needed"], m["quantity_on_hand"], m["quantity_short"])
			}
		}

		if shortCount := result["total_items_short"]; shortCount != nil && toFloat(shortCount) > 0 {
			fmt.Println("\nProcure short items before shipping.")
		} else {
			fmt.Println("\nAll items accounted for.")
			fmt.Println("Next: parts logistics shipment create --order <id> --destination <cm-addr> --carrier dhl")
		}
		return nil
	},
}

// --- Station 5: Inventory Reconcile ---

var logisticsInventoryReconcile = &cobra.Command{
	Use:   "reconcile",
	Short: "Reconcile physical inventory count vs system records",
	Long: `Upload a physical count CSV and system inventory CSV.
Diffs quantities and reports matches, overages, and shortages.

Physical count CSV columns: part_number, counted_quantity
System inventory CSV columns: part_number, system_quantity

Review discrepancies before adjusting system records.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		physicalPath, _ := cmd.Flags().GetString("physical")
		systemPath, _ := cmd.Flags().GetString("system")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if physicalPath == "" || systemPath == "" {
			return fmt.Errorf("--physical and --system are required")
		}

		fmt.Printf("Reconciling %s vs %s...\n", filepath.Base(physicalPath), filepath.Base(systemPath))

		result, err := assemblyUploadMultipleAndGetJSON(
			map[string]string{
				"physical_count":   physicalPath,
				"system_inventory": systemPath,
			},
			"/v1/logistics/inventory/reconcile",
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

		fmt.Printf("\nParts checked:  %v\n", result["total_parts_checked"])
		fmt.Printf("Matches:        %v\n", result["match_count"])
		fmt.Printf("Overages:       %v\n", result["overage_count"])
		fmt.Printf("Shortages:      %v\n", result["shortage_count"])
		fmt.Printf("Accuracy:       %v%%\n", result["accuracy_pct"])

		if shortages, ok := result["shortages"].([]interface{}); ok && len(shortages) > 0 {
			fmt.Println("\nShortages:")
			fmt.Printf("  %-20s %10s %10s %10s\n", "Part Number", "Counted", "System", "Diff")
			fmt.Printf("  %-20s %10s %10s %10s\n", "--------------------", "----------", "----------", "----------")
			for i, item := range shortages {
				if i >= 15 {
					fmt.Printf("  ... and %d more\n", len(shortages)-15)
					break
				}
				m := item.(map[string]interface{})
				fmt.Printf("  %-20v %10v %10v %10v\n",
					m["part_number"], m["counted_quantity"], m["system_quantity"], m["difference"])
			}
		}

		if overages, ok := result["overages"].([]interface{}); ok && len(overages) > 0 {
			fmt.Println("\nOverages:")
			fmt.Printf("  %-20s %10s %10s %10s\n", "Part Number", "Counted", "System", "Diff")
			fmt.Printf("  %-20s %10s %10s %10s\n", "--------------------", "----------", "----------", "----------")
			for i, item := range overages {
				if i >= 15 {
					fmt.Printf("  ... and %d more\n", len(overages)-15)
					break
				}
				m := item.(map[string]interface{})
				fmt.Printf("  %-20v %10v %10v %+10v\n",
					m["part_number"], m["counted_quantity"], m["system_quantity"], m["difference"])
			}
		}

		discrepancies := toFloat(result["total_discrepancies"])
		if discrepancies == 0 {
			fmt.Println("\nInventory matches. No action needed.")
		} else {
			fmt.Println("\nInvestigate discrepancies. Update system records after verification.")
		}
		return nil
	},
}

func init() {
	// Shipment create flags
	logisticsShipmentCreate.Flags().String("order", "", "Order ID (required)")
	logisticsShipmentCreate.Flags().String("destination", "", "Destination address (required)")
	logisticsShipmentCreate.Flags().String("carrier", "dhl", "Carrier: dhl, fedex, sf_express, usps")
	logisticsShipmentCreate.Flags().Float64("weight", 0.5, "Package weight in kg")
	logisticsShipmentCreate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Shipment track flags
	logisticsShipmentTrack.Flags().String("shipment", "", "Shipment ID (required)")
	logisticsShipmentTrack.Flags().String("carrier", "", "Carrier name")
	logisticsShipmentTrack.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Customs declare flags
	logisticsCustomsDeclare.Flags().Float64("invoice-amount", 0, "Total invoice amount in USD (required)")
	logisticsCustomsDeclare.Flags().String("destination", "", "Destination country code (required)")
	logisticsCustomsDeclare.Flags().String("origin", "CN", "Origin country code (default CN)")
	logisticsCustomsDeclare.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Consignment manifest flags
	logisticsConsignmentManifest.Flags().String("inventory", "", "Path to inventory levels JSON file")
	logisticsConsignmentManifest.Flags().String("cm-address", "", "CM shipping address (required)")
	logisticsConsignmentManifest.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Inventory reconcile flags
	logisticsInventoryReconcile.Flags().String("physical", "", "Path to physical count CSV (required)")
	logisticsInventoryReconcile.Flags().String("system", "", "Path to system inventory CSV (required)")
	logisticsInventoryReconcile.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	logisticsShipment.AddCommand(logisticsShipmentCreate)
	logisticsShipment.AddCommand(logisticsShipmentTrack)
	logisticsCustoms.AddCommand(logisticsCustomsDeclare)
	logisticsConsignment.AddCommand(logisticsConsignmentManifest)
	logisticsInventory.AddCommand(logisticsInventoryReconcile)

	Logistics.AddCommand(logisticsShipment)
	Logistics.AddCommand(logisticsCustoms)
	Logistics.AddCommand(logisticsConsignment)
	Logistics.AddCommand(logisticsInventory)
}
