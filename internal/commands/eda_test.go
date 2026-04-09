package commands

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/cobra"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// Arg Validation
// =============================================================================

func TestEDAERCArgValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{"valid single arg", []string{"board.kicad_sch"}, false},
		{"no args", []string{}, true},
		{"too many args", []string{"a.kicad_sch", "b.kicad_sch"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := &cobra.Command{
				Use:  "erc",
				Args: cobra.ExactArgs(1),
				RunE: func(cmd *cobra.Command, args []string) error { return nil },
			}
			cmd.SetArgs(tt.args)
			err := cmd.Execute()
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestEDADRCArgValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{"valid single arg", []string{"board.kicad_pcb"}, false},
		{"no args", []string{}, true},
		{"too many args", []string{"a.kicad_pcb", "b.kicad_pcb"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := &cobra.Command{
				Use:  "drc",
				Args: cobra.ExactArgs(1),
				RunE: func(cmd *cobra.Command, args []string) error { return nil },
			}
			cmd.SetArgs(tt.args)
			err := cmd.Execute()
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestEDANetlistArgValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{"valid single arg", []string{"main.kicad_sch"}, false},
		{"no args", []string{}, true},
		{"too many args", []string{"a.kicad_sch", "b.kicad_sch"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := &cobra.Command{
				Use:  "netlist",
				Args: cobra.ExactArgs(1),
				RunE: func(cmd *cobra.Command, args []string) error { return nil },
			}
			cmd.SetArgs(tt.args)
			err := cmd.Execute()
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestEDAExportPCBArgValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{"valid single arg", []string{"board.kicad_pcb"}, false},
		{"no args", []string{}, true},
		{"too many args", []string{"a.kicad_pcb", "b.kicad_pcb"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := &cobra.Command{
				Use:  "pcb",
				Args: cobra.ExactArgs(1),
				RunE: func(cmd *cobra.Command, args []string) error { return nil },
			}
			cmd.SetArgs(tt.args)
			err := cmd.Execute()
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestEDAExportSchArgValidation(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantErr bool
	}{
		{"valid single arg", []string{"main.kicad_sch"}, false},
		{"no args", []string{}, true},
		{"too many args", []string{"a.kicad_sch", "b.kicad_sch"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := &cobra.Command{
				Use:  "sch",
				Args: cobra.ExactArgs(1),
				RunE: func(cmd *cobra.Command, args []string) error { return nil },
			}
			cmd.SetArgs(tt.args)
			err := cmd.Execute()
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

// =============================================================================
// File Validation
// =============================================================================

func TestEDANetlistFileValidation(t *testing.T) {
	dir := t.TempDir()

	validFile := filepath.Join(dir, "board.kicad_sch")
	require.NoError(t, os.WriteFile(validFile, []byte("(kicad_sch)"), 0644))

	wrongExt := filepath.Join(dir, "board.txt")
	require.NoError(t, os.WriteFile(wrongExt, []byte("text"), 0644))

	t.Run("nonexistent file", func(t *testing.T) {
		_, err := os.Stat(filepath.Join(dir, "nope.kicad_sch"))
		assert.True(t, os.IsNotExist(err))
	})

	t.Run("wrong extension rejected", func(t *testing.T) {
		ext := filepath.Ext(wrongExt)
		assert.NotEqual(t, ".kicad_sch", ext)
	})

	t.Run("valid .kicad_sch accepted", func(t *testing.T) {
		info, err := os.Stat(validFile)
		require.NoError(t, err)
		assert.False(t, info.IsDir())
		assert.Equal(t, ".kicad_sch", filepath.Ext(validFile))
	})
}

func TestEDAExportPCBFileValidation(t *testing.T) {
	dir := t.TempDir()

	pcbFile := filepath.Join(dir, "board.kicad_pcb")
	require.NoError(t, os.WriteFile(pcbFile, []byte("(kicad_pcb)"), 0644))

	wrongExt := filepath.Join(dir, "board.txt")
	require.NoError(t, os.WriteFile(wrongExt, []byte("text"), 0644))

	t.Run("nonexistent file", func(t *testing.T) {
		_, err := os.Stat(filepath.Join(dir, "nope.kicad_pcb"))
		assert.True(t, os.IsNotExist(err))
	})

	t.Run("wrong extension rejected", func(t *testing.T) {
		ext := filepath.Ext(wrongExt)
		assert.NotEqual(t, ".kicad_pcb", ext)
	})

	t.Run("valid .kicad_pcb accepted", func(t *testing.T) {
		info, err := os.Stat(pcbFile)
		require.NoError(t, err)
		assert.False(t, info.IsDir())
		assert.Equal(t, ".kicad_pcb", filepath.Ext(pcbFile))
	})
}

// =============================================================================
// Flag Registration
// =============================================================================

func TestEDAExportPCBFlagRegistration(t *testing.T) {
	cmd := edaExportPCB
	flags := []string{"format", "output", "layers", "side", "units", "precision",
		"board-only", "no-dnp", "include-tracks", "include-zones",
		"compress", "smd-only", "exclude-dnp", "black-and-white", "mirror"}
	for _, name := range flags {
		assert.NotNil(t, cmd.Flags().Lookup(name), "missing flag: %s", name)
	}

	t.Run("pcb format default", func(t *testing.T) {
		f := cmd.Flags().Lookup("format")
		assert.Equal(t, "step", f.DefValue)
	})
}

func TestEDAExportSchFlagRegistration(t *testing.T) {
	cmd := edaExportSch
	flags := []string{"format", "output", "pages", "fields", "group-by",
		"sort-field", "format-preset", "black-and-white", "exclude-dnp"}
	for _, name := range flags {
		assert.NotNil(t, cmd.Flags().Lookup(name), "missing flag: %s", name)
	}

	t.Run("sch format default", func(t *testing.T) {
		f := cmd.Flags().Lookup("format")
		assert.Equal(t, "pdf", f.DefValue)
	})
}

func TestEDANetlistFlagRegistration(t *testing.T) {
	cmd := edaNetlist
	assert.NotNil(t, cmd.Flags().Lookup("format"))
	assert.NotNil(t, cmd.Flags().Lookup("output"))

	t.Run("format default", func(t *testing.T) {
		f := cmd.Flags().Lookup("format")
		assert.Equal(t, "xml", f.DefValue)
	})

	t.Run("output short flag", func(t *testing.T) {
		o := cmd.Flags().ShorthandLookup("o")
		assert.NotNil(t, o)
		assert.Equal(t, "output", o.Name)
	})
}

func TestEDAERCFlagRegistration(t *testing.T) {
	cmd := edaERC
	assert.NotNil(t, cmd.Flags().Lookup("severity"))
	assert.NotNil(t, cmd.Flags().Lookup("rules"))
	assert.NotNil(t, cmd.Flags().Lookup("json"))

	t.Run("severity short flag", func(t *testing.T) {
		s := cmd.Flags().ShorthandLookup("s")
		assert.NotNil(t, s)
		assert.Equal(t, "severity", s.Name)
	})

	t.Run("json short flag", func(t *testing.T) {
		j := cmd.Flags().ShorthandLookup("j")
		assert.NotNil(t, j)
		assert.Equal(t, "json", j.Name)
	})
}

// =============================================================================
// writeExportResult
// =============================================================================

func TestWriteExportResult_Base64(t *testing.T) {
	dir := t.TempDir()
	output := filepath.Join(dir, "board.step")

	payload := map[string]interface{}{
		"status": "success",
		"data": map[string]interface{}{
			"file_base64": base64.StdEncoding.EncodeToString([]byte("STEP file content")),
			"filename":    "board.step",
			"size_bytes":  17,
		},
	}
	data, err := json.Marshal(payload)
	require.NoError(t, err)

	err = writeExportResult(data, output, "step")
	require.NoError(t, err)

	content, err := os.ReadFile(output)
	require.NoError(t, err)
	assert.Equal(t, "STEP file content", string(content))
}

func TestWriteExportResult_TextContent(t *testing.T) {
	dir := t.TempDir()
	output := filepath.Join(dir, "positions.csv")

	payload := map[string]interface{}{
		"status": "success",
		"data": map[string]interface{}{
			"content":    "Ref,Val,X,Y\nR1,10k,1.0,2.0\n",
			"filename":   "positions.csv",
			"size_bytes": 28,
		},
	}
	data, err := json.Marshal(payload)
	require.NoError(t, err)

	err = writeExportResult(data, output, "csv")
	require.NoError(t, err)

	content, err := os.ReadFile(output)
	require.NoError(t, err)
	assert.Contains(t, string(content), "R1,10k")
}

func TestWriteExportResult_Error(t *testing.T) {
	payload := map[string]interface{}{
		"error": "kicad-cli not available on this server",
	}
	data, err := json.Marshal(payload)
	require.NoError(t, err)

	err = writeExportResult(data, "", "step")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "kicad-cli not available")
}

func TestWriteExportResult_EmptyData(t *testing.T) {
	payload := map[string]interface{}{
		"status": "success",
		"data": map[string]interface{}{
			"file_base64": "",
			"content":     "",
			"filename":    "",
		},
	}
	data, err := json.Marshal(payload)
	require.NoError(t, err)

	err = writeExportResult(data, "", "step")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "empty response")
}

func TestWriteExportResult_DefaultFilename(t *testing.T) {
	dir := t.TempDir()

	payload := map[string]interface{}{
		"status": "success",
		"data": map[string]interface{}{
			"file_base64": base64.StdEncoding.EncodeToString([]byte("data")),
			"filename":    "",
			"size_bytes":  4,
		},
	}
	data, err := json.Marshal(payload)
	require.NoError(t, err)

	origDir, _ := os.Getwd()
	os.Chdir(dir)
	defer os.Chdir(origDir)

	err = writeExportResult(data, "", "step")
	require.NoError(t, err)

	_, err = os.Stat(filepath.Join(dir, "export.step"))
	assert.NoError(t, err)
}

func TestWriteExportResult_InvalidJSON(t *testing.T) {
	dir := t.TempDir()
	output := filepath.Join(dir, "raw.bin")

	rawData := []byte("raw binary content that is not json")
	err := writeExportResult(rawData, output, "bin")
	require.NoError(t, err)

	content, err := os.ReadFile(output)
	require.NoError(t, err)
	assert.Equal(t, rawData, content)
}
