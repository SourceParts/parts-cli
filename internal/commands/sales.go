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
// Sales — AOI-style operator-approved quoting and invoicing pipeline
// =============================================================================

var Sales = &cobra.Command{
	Use:   "sales",
	Short: "Sales pipeline (quote, negotiate, order, invoice, commission)",
	Long: `AOI-style operator-approved sales pipeline.

Each command performs one atomic step and returns results for review.
Approve each step before proceeding to the next.

Pipeline:
  1. quote build       — price a BOM and generate a quote
  2. quote negotiate   — revise quantities/pricing on a quote
  3. order convert     — validate stock and convert quote to order
  4. invoice generate  — generate invoice data from an order
  5. commission calculate — calculate sales commission`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var salesQuote = &cobra.Command{
	Use:   "quote",
	Short: "Quote operations (build, negotiate)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var salesOrder = &cobra.Command{
	Use:   "order",
	Short: "Order operations (convert)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var salesInvoice = &cobra.Command{
	Use:   "invoice",
	Short: "Invoice operations (generate)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var salesCommission = &cobra.Command{
	Use:   "commission",
	Short: "Commission operations (calculate)",
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

// postJSONAndGetJSON posts a JSON body to an API endpoint and returns JSON.
func postJSONAndGetJSON(endpoint string, payload map[string]interface{}) (map[string]interface{}, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal payload: %w", err)
	}

	url := resolveEndpoint(endpoint)
	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	setAuthHeader(req)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}
	return result, nil
}

// --- Station 1: Quote Build ---

var salesQuoteBuild = &cobra.Command{
	Use:   "build <bom.csv>",
	Short: "Price a BOM and generate a quote",
	Long: `Upload a BOM file (.csv or .json) to the API, price all components,
add fabrication + assembly + margin, and return a full quote breakdown.

Review the quote before sending to the customer.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		bomPath := args[0]
		quantity, _ := cmd.Flags().GetInt("quantity")
		customer, _ := cmd.Flags().GetString("customer")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if quantity <= 0 {
			return fmt.Errorf("--quantity must be a positive integer")
		}
		if customer == "" {
			return fmt.Errorf("--customer is required")
		}

		fmt.Printf("Building quote for %s (%d units) from %s...\n", customer, quantity, filepath.Base(bomPath))

		// Upload BOM as multipart
		var requestBody bytes.Buffer
		writer := multipart.NewWriter(&requestBody)
		if err := addFileToMultipart(writer, "file", bomPath); err != nil {
			return fmt.Errorf("failed to add BOM file: %w", err)
		}
		writer.WriteField("quantity", fmt.Sprintf("%d", quantity))
		writer.WriteField("customer_name", customer)
		writer.Close()

		url := fmt.Sprintf("https://%s/v1/sales/quote/build", domain.API)
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

		fmt.Printf("\nQuote: %v\n", result["quote_id"])
		fmt.Printf("Customer: %v\n", result["customer_name"])
		fmt.Printf("Build Qty: %v\n", result["build_quantity"])
		fmt.Printf("Line Items: %v\n", result["line_item_count"])
		fmt.Printf("\n  Component Subtotal: $%.2f\n", toFloat(result["component_subtotal"]))
		fmt.Printf("  Fab Cost:           $%.2f\n", toFloat(result["fab_cost"]))
		fmt.Printf("  Assembly Cost:      $%.2f\n", toFloat(result["assembly_cost"]))
		fmt.Printf("  Total Cost:         $%.2f\n", toFloat(result["total_cost"]))

		if margin, ok := result["margin_analysis"].(map[string]interface{}); ok {
			fmt.Printf("\n  Margin:  %.0f%%\n", toFloat(margin["margin_pct"])*100)
			fmt.Printf("  Selling: $%.2f\n", toFloat(margin["selling_price"]))
		}

		fmt.Println("\nNext: parts sales quote negotiate --quote <id> --quantity <n>")
		return nil
	},
}

// --- Station 2: Quote Negotiate ---

var salesQuoteNegotiate = &cobra.Command{
	Use:   "negotiate",
	Short: "Revise quantities or pricing on a quote",
	Long: `Recalculate a quote at revised quantities or margin.
Shows the margin delta compared to the original.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		quoteID, _ := cmd.Flags().GetString("quote")
		quantity, _ := cmd.Flags().GetInt("quantity")
		marginPct, _ := cmd.Flags().GetFloat64("margin")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if quoteID == "" {
			return fmt.Errorf("--quote is required")
		}

		fmt.Printf("Negotiating quote %s...\n", quoteID)

		payload := map[string]interface{}{
			"quote_id": quoteID,
		}
		if quantity > 0 {
			payload["revised_quantity"] = quantity
		}
		if marginPct > 0 {
			payload["revised_margin_pct"] = marginPct
		}

		result, err := postJSONAndGetJSON("/v1/sales/quote/negotiate", payload)
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nQuote: %v\n", result["quote_id"])
		fmt.Printf("Margin Delta: $%.2f\n", toFloat(result["margin_delta"]))
		fmt.Printf("Price Delta:  $%.2f\n", toFloat(result["price_delta"]))

		if revised, ok := result["revised_margin"].(map[string]interface{}); ok {
			fmt.Printf("\n  Revised Margin:  %.0f%%\n", toFloat(revised["margin_pct"])*100)
			fmt.Printf("  Revised Selling: $%.2f\n", toFloat(revised["selling_price"]))
		}

		fmt.Println("\nNext: parts sales order convert --quote <id>")
		return nil
	},
}

// --- Station 3: Order Convert ---

var salesOrderConvert = &cobra.Command{
	Use:   "convert",
	Short: "Validate stock and convert a quote to an order",
	Long: `Check inventory for all line items and convert the quote.
Flags any shortages or long lead times.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		quoteID, _ := cmd.Flags().GetString("quote")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if quoteID == "" {
			return fmt.Errorf("--quote is required")
		}

		fmt.Printf("Converting quote %s to order...\n", quoteID)

		result, err := postJSONAndGetJSON("/v1/sales/order/convert", map[string]interface{}{
			"quote_id": quoteID,
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		allClear, _ := result["all_clear"].(bool)
		fmt.Printf("\nOrder: %v\n", result["order_id"])
		fmt.Printf("Quote: %v\n", result["quote_id"])

		if allClear {
			fmt.Println("Status: ALL CLEAR")
		} else {
			fmt.Printf("Status: %v ITEMS AT RISK\n", result["items_at_risk_count"])
			if items, ok := result["items_at_risk"].([]interface{}); ok {
				for _, item := range items {
					if m, ok := item.(map[string]interface{}); ok {
						fmt.Printf("  - %v: %v\n", m["part_number"], m["reason"])
					}
				}
			}
		}

		if allClear {
			fmt.Println("\nNext: parts sales invoice generate --order <id> --terms net30")
		} else {
			fmt.Println("\nResolve shortages, then retry: parts sales order convert --quote <id>")
		}
		return nil
	},
}

// --- Station 4: Invoice Generate ---

var salesInvoiceGenerate = &cobra.Command{
	Use:   "generate",
	Short: "Generate invoice data from an order",
	Long: `Create a draft invoice with line items, tax, totals, and due date.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		orderID, _ := cmd.Flags().GetString("order")
		terms, _ := cmd.Flags().GetString("terms")
		taxRate, _ := cmd.Flags().GetFloat64("tax")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if orderID == "" {
			return fmt.Errorf("--order is required")
		}

		fmt.Printf("Generating invoice for order %s...\n", orderID)

		result, err := postJSONAndGetJSON("/v1/sales/invoice/generate", map[string]interface{}{
			"order_id":      orderID,
			"payment_terms": terms,
			"tax_rate":      taxRate,
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nInvoice: %v\n", result["invoice_id"])
		fmt.Printf("Order:   %v\n", result["order_id"])
		fmt.Printf("Terms:   %v\n", result["payment_terms"])
		fmt.Printf("Due:     %v\n", result["due_date"])
		fmt.Printf("\n  Subtotal:  $%.2f\n", toFloat(result["subtotal"]))
		fmt.Printf("  Tax:       $%.2f (%.2f%%)\n", toFloat(result["tax_amount"]), toFloat(result["tax_rate"])*100)
		fmt.Printf("  Total:     $%.2f\n", toFloat(result["total"]))

		fmt.Println("\nNext: parts sales commission calculate --order <id> --rate 0.05")
		return nil
	},
}

// --- Station 5: Commission Calculate ---

var salesCommissionCalculate = &cobra.Command{
	Use:   "calculate",
	Short: "Calculate sales commission on an order",
	Long: `Compute commission payout based on order total and rate.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		orderID, _ := cmd.Flags().GetString("order")
		rate, _ := cmd.Flags().GetFloat64("rate")
		commType, _ := cmd.Flags().GetString("type")
		jsonOut, _ := cmd.Flags().GetBool("json")

		if orderID == "" {
			return fmt.Errorf("--order is required")
		}
		if rate <= 0 {
			return fmt.Errorf("--rate must be positive")
		}

		fmt.Printf("Calculating commission for order %s...\n", orderID)

		result, err := postJSONAndGetJSON("/v1/sales/commission/calculate", map[string]interface{}{
			"order_id":        orderID,
			"commission_rate": rate,
			"commission_type": commType,
		})
		if err != nil {
			return err
		}

		if jsonOut {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		}

		fmt.Printf("\nOrder: %v\n", result["order_id"])
		fmt.Printf("Order Total:  $%.2f\n", toFloat(result["order_total"]))
		fmt.Printf("Commission:   $%.2f (%v)\n", toFloat(result["commission_amount"]), result["commission_type"])
		fmt.Printf("Net Revenue:  $%.2f\n", toFloat(result["net_revenue"]))

		fmt.Println("\nCommission calculated. Review and approve payout.")
		return nil
	},
}

// toFloat safely converts an interface{} to float64.
func toFloat(v interface{}) float64 {
	if v == nil {
		return 0
	}
	switch n := v.(type) {
	case float64:
		return n
	case int:
		return float64(n)
	case json.Number:
		f, _ := n.Float64()
		return f
	default:
		return 0
	}
}

func init() {
	// Quote build flags
	salesQuoteBuild.Flags().IntP("quantity", "n", 0, "Build quantity (required)")
	salesQuoteBuild.Flags().String("customer", "", "Customer name (required)")
	salesQuoteBuild.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Quote negotiate flags
	salesQuoteNegotiate.Flags().String("quote", "", "Quote ID (required)")
	salesQuoteNegotiate.Flags().IntP("quantity", "n", 0, "Revised build quantity")
	salesQuoteNegotiate.Flags().Float64("margin", 0, "Revised margin percentage (decimal)")
	salesQuoteNegotiate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Order convert flags
	salesOrderConvert.Flags().String("quote", "", "Quote ID to convert (required)")
	salesOrderConvert.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Invoice generate flags
	salesInvoiceGenerate.Flags().String("order", "", "Order ID (required)")
	salesInvoiceGenerate.Flags().String("terms", "net30", "Payment terms (net30, net60, due_on_receipt)")
	salesInvoiceGenerate.Flags().Float64("tax", 0.0, "Tax rate as decimal (e.g. 0.0875)")
	salesInvoiceGenerate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Commission calculate flags
	salesCommissionCalculate.Flags().String("order", "", "Order ID (required)")
	salesCommissionCalculate.Flags().Float64("rate", 0, "Commission rate (required)")
	salesCommissionCalculate.Flags().String("type", "percentage", "Commission type: percentage or flat")
	salesCommissionCalculate.Flags().BoolP("json", "j", false, "Output raw JSON")

	// Wire up subcommands
	salesQuote.AddCommand(salesQuoteBuild)
	salesQuote.AddCommand(salesQuoteNegotiate)
	salesOrder.AddCommand(salesOrderConvert)
	salesInvoice.AddCommand(salesInvoiceGenerate)
	salesCommission.AddCommand(salesCommissionCalculate)

	Sales.AddCommand(salesQuote)
	Sales.AddCommand(salesOrder)
	Sales.AddCommand(salesInvoice)
	Sales.AddCommand(salesCommission)
}
