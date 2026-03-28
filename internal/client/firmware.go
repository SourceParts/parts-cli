package client

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/types"
)

// FirmwareUpload uploads a firmware dump with metadata to the API.
func (c *Client) FirmwareUpload(ctx context.Context, fileName string, opts types.FirmwareUploadOptions, w io.Writer) error {
	fileContent, err := os.ReadFile(fileName)
	if err != nil {
		return fmt.Errorf("error reading file: %w", err)
	}

	hasher := sha256.New()
	hasher.Write(fileContent)
	hashString := fmt.Sprintf("%x", hasher.Sum(nil))

	fmt.Fprintf(w, "File: %s (%d bytes)\n", filepath.Base(fileName), len(fileContent))
	fmt.Fprintf(w, "SHA256: %s\n", hashString)

	// Create multipart form
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", filepath.Base(fileName))
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := part.Write(fileContent); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	_ = writer.WriteField("hash", hashString)
	if opts.Chip != "" {
		_ = writer.WriteField("chip", opts.Chip)
	}
	if opts.JedecID != "" {
		_ = writer.WriteField("jedec_id", opts.JedecID)
	}
	if opts.BoardSerial != "" {
		_ = writer.WriteField("board_serial", opts.BoardSerial)
	}
	if opts.SoC != "" {
		_ = writer.WriteField("soc", opts.SoC)
	}
	if opts.DieUID != "" {
		_ = writer.WriteField("die_uid", opts.DieUID)
	}

	// Attach metadata JSON if provided
	if opts.MetadataFile != "" {
		metaContent, err := os.ReadFile(opts.MetadataFile)
		if err != nil {
			return fmt.Errorf("error reading metadata file: %w", err)
		}
		_ = writer.WriteField("metadata", string(metaContent))
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("error closing writer: %w", err)
	}

	url := domain.Endpoint_FirmwareUpload
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, body)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	fmt.Fprintf(w, "Uploading to %s...\n", domain.API)

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("upload failed: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// RawGet performs an authenticated GET request and writes the response body.
func (c *Client) RawGet(ctx context.Context, url string, w io.Writer) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// RawPatch performs an authenticated PATCH request with a JSON body.
func (c *Client) RawPatch(ctx context.Context, url string, jsonBody string, w io.Writer) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, url, bytes.NewBufferString(jsonBody))
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// RawPost performs an authenticated POST request with a JSON body.
func (c *Client) RawPost(ctx context.Context, url string, jsonBody string, w io.Writer) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBufferString(jsonBody))
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// FirmwareList lists firmware dumps from the API.
func (c *Client) FirmwareList(ctx context.Context, opts types.FirmwareListOptions, w io.Writer) error {
	url := domain.Endpoint_FirmwareList
	sep := "?"
	if opts.JedecID != "" {
		url += sep + "jedec_id=" + opts.JedecID
		sep = "&"
	}
	if opts.Chip != "" {
		url += sep + "chip=" + opts.Chip
		sep = "&"
	}
	if opts.BoardSerial != "" {
		url += sep + "board_serial=" + opts.BoardSerial
	}

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}
