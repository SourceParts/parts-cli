package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/spf13/cobra"
)

var (
	compProduct  string
	compVersion  string
	compMarkets  string
	compRadio    string
	compBoard    string
	compProject  string
	compLab      string
	compDate     string
	compStatus   string
	compTestID   string
	compMargin   float64
	compReport   string
	compFreq     float64
	compS11      float64
	compVSWR     float64
	compEff      float64
)

// Compliance is the parent command for regulatory compliance.
var Compliance = &cobra.Command{
	Use:   "compliance",
	Short: "Regulatory compliance & EMC testing",
	Long: `Track FCC, CE, RCM, antenna tuning, and EMC testing for hardware products.

Examples:
  parts compliance create --product "PocketPC v2.2" --markets us,eu,au --radio wifi,ble
  parts compliance tests CP-XXXXXX
  parts compliance result CP-XXXXXX <test_id> --status pass --margin 6.2
  parts compliance antenna CP-XXXXXX --freq 2440 --s11 -18.3 --vswr 1.28`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var compCreate = &cobra.Command{
	Use:   "create",
	Short: "Create compliance project",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		if compProduct == "" {
			return fmt.Errorf("--product is required")
		}

		markets := []string{}
		if compMarkets != "" {
			markets = strings.Split(compMarkets, ",")
		}
		radio := []string{}
		if compRadio != "" {
			radio = strings.Split(compRadio, ",")
		}

		body := map[string]interface{}{
			"product_name":       compProduct,
			"product_version":    compVersion,
			"markets":            markets,
			"radio_technologies": radio,
			"board_serial":       compBoard,
			"project_id":         compProject,
		}
		jsonBody, _ := json.Marshal(body)

		return Client.RawPost(ctx, "https://"+domain.API+"/v1/compliance", string(jsonBody), os.Stdout)
	},
}

var compList = &cobra.Command{
	Use:   "list",
	Short: "List compliance projects",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		url := "https://" + domain.API + "/v1/compliance"
		if compStatus != "" {
			url += "?status=" + compStatus
		}
		return Client.RawGet(ctx, url, os.Stdout)
	},
}

var compGet = &cobra.Command{
	Use:   "get <code>",
	Short: "Get compliance project details",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		url := fmt.Sprintf("https://%s/v1/compliance/%s", domain.API, args[0])
		return Client.RawGet(ctx, url, os.Stdout)
	},
}

var compTests = &cobra.Command{
	Use:   "tests <code>",
	Short: "List tests for a compliance project",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		url := fmt.Sprintf("https://%s/v1/compliance/%s", domain.API, args[0])
		return Client.RawGet(ctx, url, os.Stdout)
	},
}

var compResult = &cobra.Command{
	Use:   "result <code> <test_id>",
	Short: "Record a test result",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		update := map[string]interface{}{
			"id":     args[1],
			"status": compStatus,
		}
		if compMargin != 0 {
			update["margin_db"] = compMargin
		}
		if compReport != "" {
			update["report_url"] = compReport
		}

		body := map[string]interface{}{"test_update": update}
		jsonBody, _ := json.Marshal(body)
		url := fmt.Sprintf("https://%s/v1/compliance/%s", domain.API, args[0])
		return Client.RawPatch(ctx, url, string(jsonBody), os.Stdout)
	},
}

var compAntenna = &cobra.Command{
	Use:   "antenna <code> <test_id>",
	Short: "Record antenna tuning results",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		update := map[string]interface{}{
			"id":     args[1],
			"status": "pass",
		}
		if compFreq != 0 {
			update["frequency_mhz"] = compFreq
		}
		if compS11 != 0 {
			update["s11_db"] = compS11
		}
		if compVSWR != 0 {
			update["vswr"] = compVSWR
		}
		if compEff != 0 {
			update["efficiency_pct"] = compEff
		}

		body := map[string]interface{}{"test_update": update}
		jsonBody, _ := json.Marshal(body)
		url := fmt.Sprintf("https://%s/v1/compliance/%s", domain.API, args[0])
		return Client.RawPatch(ctx, url, string(jsonBody), os.Stdout)
	},
}

var compStandards = &cobra.Command{
	Use:   "standards",
	Short: "List available test standards",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		url := fmt.Sprintf("https://%s/v1/compliance/standards", domain.API)
		return Client.RawGet(ctx, url, os.Stdout)
	},
}

func init() {
	compCreate.Flags().StringVar(&compProduct, "product", "", "Product name (required)")
	compCreate.Flags().StringVar(&compVersion, "version", "", "Product version")
	compCreate.Flags().StringVar(&compMarkets, "markets", "", "Target markets (comma-separated: us,eu,au,ca,jp)")
	compCreate.Flags().StringVar(&compRadio, "radio", "", "Radio technologies (comma-separated: wifi_2g4,ble,lora_sub1g)")
	compCreate.Flags().StringVar(&compBoard, "board", "", "Board serial")
	compCreate.Flags().StringVar(&compProject, "project", "", "Project ID")

	compList.Flags().StringVar(&compStatus, "status", "", "Filter by status")

	compResult.Flags().StringVar(&compStatus, "status", "pass", "Test status (pass/fail/conditional)")
	compResult.Flags().Float64Var(&compMargin, "margin", 0, "Margin to limit in dB")
	compResult.Flags().StringVar(&compReport, "report", "", "Report PDF URL")

	compAntenna.Flags().Float64Var(&compFreq, "freq", 0, "Frequency in MHz")
	compAntenna.Flags().Float64Var(&compS11, "s11", 0, "Return loss S11 in dB")
	compAntenna.Flags().Float64Var(&compVSWR, "vswr", 0, "VSWR")
	compAntenna.Flags().Float64Var(&compEff, "efficiency", 0, "Antenna efficiency %")

	Compliance.AddCommand(compCreate)
	Compliance.AddCommand(compList)
	Compliance.AddCommand(compGet)
	Compliance.AddCommand(compTests)
	Compliance.AddCommand(compResult)
	Compliance.AddCommand(compAntenna)
	Compliance.AddCommand(compStandards)
}

