package commands

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/spf13/cobra"
)

var (
	fwChip        string
	fwJedecID     string
	fwBoardSerial string
	fwSoC         string
	fwDieUID      string
	fwMetadata    string
)

// Firmware is the parent command for firmware operations.
var Firmware = &cobra.Command{
	Use:   "firmware",
	Short: "Firmware dump management",
	Long:  `Upload, list, and manage firmware dumps from SPI flash, NAND, and other storage.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
}

var firmwareUpload = &cobra.Command{
	Use:   "upload <file>",
	Short: "Upload a firmware dump",
	Long: `Upload a firmware binary to Source Parts with metadata.

Examples:
  parts firmware upload dump.bin.zst --chip W25N01GV --jedec ef:aa:21
  parts firmware upload dump.bin.zst --board PP-F1C200s-B8642360 --metadata metadata.json`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 600*time.Second)
		defer cancel()

		filePath := args[0]
		if _, err := os.Stat(filePath); os.IsNotExist(err) {
			return fmt.Errorf("file not found: %s", filePath)
		}

		opts := types.FirmwareUploadOptions{
			Chip:         fwChip,
			JedecID:      fwJedecID,
			BoardSerial:  fwBoardSerial,
			SoC:          fwSoC,
			DieUID:       fwDieUID,
			MetadataFile: fwMetadata,
		}

		return Client.FirmwareUpload(ctx, filePath, opts, os.Stdout)
	},
}

var firmwareList = &cobra.Command{
	Use:   "list",
	Short: "List firmware dumps",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		opts := types.FirmwareListOptions{
			JedecID:     fwJedecID,
			Chip:        fwChip,
			BoardSerial: fwBoardSerial,
		}

		return Client.FirmwareList(ctx, opts, os.Stdout)
	},
}

func init() {
	firmwareUpload.Flags().StringVar(&fwChip, "chip", "", "Flash chip model (e.g., W25N01GV)")
	firmwareUpload.Flags().StringVar(&fwJedecID, "jedec", "", "JEDEC ID (e.g., ef:aa:21)")
	firmwareUpload.Flags().StringVar(&fwBoardSerial, "board", "", "Board serial (e.g., PP-F1C200s-B8642360)")
	firmwareUpload.Flags().StringVar(&fwSoC, "soc", "", "SoC name (e.g., F1C200s)")
	firmwareUpload.Flags().StringVar(&fwDieUID, "die-uid", "", "Flash die unique ID")
	firmwareUpload.Flags().StringVar(&fwMetadata, "metadata", "", "Path to metadata JSON file")

	firmwareList.Flags().StringVar(&fwJedecID, "jedec", "", "Filter by JEDEC ID")
	firmwareList.Flags().StringVar(&fwChip, "chip", "", "Filter by chip model")
	firmwareList.Flags().StringVar(&fwBoardSerial, "board", "", "Filter by board serial")

	Firmware.AddCommand(firmwareUpload)
	Firmware.AddCommand(firmwareList)
}
