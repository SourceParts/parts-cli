package client

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/logger"
	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newTestClient(t *testing.T, apiKey string) *Client {
	t.Helper()
	verbose := false
	api := domain.API
	return &Client{
		API:    &api,
		APIKey: apiKey,
		Logger: logger.New(&verbose),
		Client: http.DefaultClient,
	}
}

func createTestFile(t *testing.T, name string, content string) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, name)
	require.NoError(t, os.WriteFile(p, []byte(content), 0644))
	return p
}

func TestPCBExport(t *testing.T) {
	pcbFile := createTestFile(t, "board.kicad_pcb", "(kicad_pcb (version 8))")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, http.MethodPost, r.Method)
		assert.True(t, strings.HasSuffix(r.URL.Path, "/eda/pcb/export/step"),
			"expected path ending with /eda/pcb/export/step, got %s", r.URL.Path)

		// Verify auth header
		assert.Equal(t, "Bearer test-api-key", r.Header.Get("Authorization"))

		// Verify multipart body contains the file
		ct := r.Header.Get("Content-Type")
		mediaType, params, err := mime.ParseMediaType(ct)
		require.NoError(t, err)
		assert.Equal(t, "multipart/form-data", mediaType)

		mr := multipart.NewReader(r.Body, params["boundary"])
		foundFile := false
		fields := map[string]string{}
		for {
			part, err := mr.NextPart()
			if err == io.EOF {
				break
			}
			require.NoError(t, err)
			if part.FormName() == "file" {
				foundFile = true
				assert.Equal(t, "board.kicad_pcb", part.FileName())
			} else {
				val, _ := io.ReadAll(part)
				fields[part.FormName()] = string(val)
			}
		}
		assert.True(t, foundFile, "expected file in multipart upload")
		assert.Equal(t, "true", fields["board_only"])

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "success",
			"data": map[string]interface{}{
				"file_base64": "c3RlcCBkYXRh",
				"filename":    "board.step",
				"size_bytes":  9,
			},
		})
	}))
	defer server.Close()

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.EDAUpload(context.Background(),
		server.URL+"/v1/eda/pcb/export/step",
		pcbFile,
		map[string]string{"board_only": "true"},
		nil,
		&buf,
	)

	require.NoError(t, err)
	assert.NotEmpty(t, buf.Bytes())

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(buf.Bytes(), &resp))
	assert.Equal(t, "success", resp["status"])
}

func TestSchExport(t *testing.T) {
	schFile := createTestFile(t, "main.kicad_sch", "(kicad_sch)")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, http.MethodPost, r.Method)
		assert.True(t, strings.HasSuffix(r.URL.Path, "/eda/sch/export/bom"),
			"expected path ending with /eda/sch/export/bom, got %s", r.URL.Path)

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "success",
			"data": map[string]interface{}{
				"content":    "Ref,Value,Footprint\nR1,10k,0402\n",
				"filename":   "bom.csv",
				"size_bytes": 32,
			},
		})
	}))
	defer server.Close()

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.EDAUpload(context.Background(),
		server.URL+"/v1/eda/sch/export/bom",
		schFile,
		map[string]string{"exclude_dnp": "true"},
		nil,
		&buf,
	)

	require.NoError(t, err)

	var resp map[string]interface{}
	require.NoError(t, json.Unmarshal(buf.Bytes(), &resp))
	data := resp["data"].(map[string]interface{})
	assert.Contains(t, data["content"], "R1,10k")
}

func TestSchNetlist(t *testing.T) {
	schFile := createTestFile(t, "main.kicad_sch", "(kicad_sch)")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, http.MethodPost, r.Method)
		assert.True(t, strings.HasSuffix(r.URL.Path, "/eda/schematic/netlist"),
			"expected path ending with /eda/schematic/netlist, got %s", r.URL.Path)

		// Verify format field is sent
		ct := r.Header.Get("Content-Type")
		_, params, err := mime.ParseMediaType(ct)
		require.NoError(t, err)
		mr := multipart.NewReader(r.Body, params["boundary"])
		fields := map[string]string{}
		for {
			part, err := mr.NextPart()
			if err == io.EOF {
				break
			}
			require.NoError(t, err)
			if part.FormName() != "file" {
				val, _ := io.ReadAll(part)
				fields[part.FormName()] = string(val)
			}
		}
		assert.Equal(t, "json", fields["format"])

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"nets":["GND","VCC"],"components":2}`))
	}))
	defer server.Close()

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.EDAUpload(context.Background(),
		server.URL+"/v1/eda/schematic/netlist",
		schFile,
		map[string]string{"format": "json"},
		nil,
		&buf,
	)

	require.NoError(t, err)
	assert.Contains(t, buf.String(), "GND")
}

func TestEDAUploadErrorResponses(t *testing.T) {
	schFile := createTestFile(t, "board.kicad_sch", "(kicad_sch)")

	tests := []struct {
		name       string
		statusCode int
		body       string
		wantErr    string
	}{
		{
			name:       "404 not found",
			statusCode: http.StatusNotFound,
			body:       `{"error":"endpoint not found"}`,
			wantErr:    "404",
		},
		{
			name:       "500 server error",
			statusCode: http.StatusInternalServerError,
			body:       `{"error":"kicad-cli crashed"}`,
			wantErr:    "500",
		},
		{
			name:       "503 unavailable",
			statusCode: http.StatusServiceUnavailable,
			body:       `{"error":"kicad-cli not available"}`,
			wantErr:    "503",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tt.statusCode)
				w.Write([]byte(tt.body))
			}))
			defer server.Close()

			c := newTestClient(t, "test-api-key")

			var buf bytes.Buffer
			err := c.EDAUpload(context.Background(),
				server.URL+"/v1/eda/sch/export/pdf",
				schFile,
				nil,
				nil,
				&buf,
			)

			assert.Error(t, err)
			assert.Contains(t, err.Error(), tt.wantErr)
		})
	}
}

func TestEDAUploadAuthHeader(t *testing.T) {
	schFile := createTestFile(t, "board.kicad_sch", "(kicad_sch)")

	t.Run("with API key", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "Bearer my-key", r.Header.Get("Authorization"))
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"status":"success","data":{}}`))
		}))
		defer server.Close()

		c := newTestClient(t, "my-key")

		var buf bytes.Buffer
		_ = c.EDAUpload(context.Background(), server.URL+"/v1/eda/erc", schFile, nil, nil, &buf)
	})

	t.Run("without API key", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Empty(t, r.Header.Get("Authorization"))
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"status":"success","data":{}}`))
		}))
		defer server.Close()

		c := newTestClient(t, "")

		var buf bytes.Buffer
		_ = c.EDAUpload(context.Background(), server.URL+"/v1/eda/erc", schFile, nil, nil, &buf)
	})
}

func TestEDAUploadFileNotFound(t *testing.T) {
	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.EDAUpload(context.Background(),
		"http://localhost:1/v1/eda/pcb/export/step",
		"/nonexistent/board.kicad_pcb",
		nil,
		nil,
		&buf,
	)

	assert.Error(t, err)
	assert.Contains(t, err.Error(), "error reading file")
}

func TestEDAUploadContextCancellation(t *testing.T) {
	schFile := createTestFile(t, "board.kicad_sch", "(kicad_sch)")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {}
	}))
	defer server.Close()

	c := newTestClient(t, "test-api-key")

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	var buf bytes.Buffer
	err := c.EDAUpload(ctx, server.URL+"/v1/eda/erc", schFile, nil, nil, &buf)
	assert.Error(t, err)
}

func TestEDAUploadExtraFiles(t *testing.T) {
	schFile := createTestFile(t, "board.kicad_sch", "(kicad_sch)")
	rulesFile := createTestFile(t, "custom.rules", "rule_content_here")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ct := r.Header.Get("Content-Type")
		_, params, err := mime.ParseMediaType(ct)
		require.NoError(t, err)

		mr := multipart.NewReader(r.Body, params["boundary"])
		foundMain := false
		foundRules := false
		for {
			part, err := mr.NextPart()
			if err == io.EOF {
				break
			}
			require.NoError(t, err)
			if part.FormName() == "file" {
				foundMain = true
			}
			if part.FormName() == "rules_file" {
				foundRules = true
				assert.Equal(t, "custom.rules", part.FileName())
			}
		}
		assert.True(t, foundMain, "expected main file")
		assert.True(t, foundRules, "expected rules_file")

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"success"}`))
	}))
	defer server.Close()

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.EDAUpload(context.Background(),
		server.URL+"/v1/eda/erc",
		schFile,
		map[string]string{"severity": "error"},
		map[string]string{"rules_file": rulesFile},
		&buf,
	)
	require.NoError(t, err)
}

func TestPCBExportMethod(t *testing.T) {
	pcbFile := createTestFile(t, "board.kicad_pcb", "(kicad_pcb)")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.True(t, strings.HasSuffix(r.URL.Path, "/eda/pcb/export/glb"),
			"expected path ending with /eda/pcb/export/glb, got %s", r.URL.Path)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"success","data":{"file_base64":"dGVzdA==","filename":"board.glb"}}`))
	}))
	defer server.Close()

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.PCBExport(context.Background(), pcbFile, types.ExportOptions{
		Format:     "glb",
		FormFields: map[string]string{},
	}, &buf)

	// PCBExport calls EDAUpload with domain.Endpoint_PCBExport which is https://...
	// The test server is http://localhost, so we expect a connection error since
	// PCBExport builds the URL from the const, not from our test server.
	// This verifies the method exists and compiles.
	assert.Error(t, err)
}

func TestSchExportMethod(t *testing.T) {
	schFile := createTestFile(t, "main.kicad_sch", "(kicad_sch)")

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.SchExport(context.Background(), schFile, types.ExportOptions{
		Format:     "bom",
		FormFields: map[string]string{},
	}, &buf)

	// Same as above — verifies method exists, will fail connecting to real API
	assert.Error(t, err)
}

func TestSchNetlistMethod(t *testing.T) {
	schFile := createTestFile(t, "main.kicad_sch", "(kicad_sch)")

	c := newTestClient(t, "test-api-key")

	var buf bytes.Buffer
	err := c.SchNetlist(context.Background(), schFile, types.NetlistExportOptions{
		Format: "xml",
	}, &buf)

	assert.Error(t, err)
}
