package client

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/logger"
)

var _ domain.Client = &Client{}

// Client implements the domain.Client interface
type Client struct {
	API    *string
	APIKey string
	Logger *logger.Logger
	Client *http.Client

	Endpoint_Add       *string
	Endpoint_Search    *string
	Endpoint_Datasheet *string
	Endpoint_Marking   *string
}

// newAuthenticatedRequest creates an HTTP request with authentication headers.
func (c *Client) newAuthenticatedRequest(method, url string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequest(method, url, body)
	if err != nil {
		return nil, fmt.Errorf("error creating request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)

	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	return req, nil
}

// newAuthenticatedRequestWithContext creates an HTTP request with auth headers and context.
func (c *Client) newAuthenticatedRequestWithContext(ctx context.Context, method, url string, body io.Reader) (*http.Request, error) {
	req, err := c.newAuthenticatedRequest(method, url, body)
	if err != nil {
		return nil, err
	}
	return req.WithContext(ctx), nil
}

// IsAuthenticated returns true if an API key is configured.
func (c *Client) IsAuthenticated() bool {
	return c.APIKey != ""
}

// GetAPIKey returns the current API key.
func (c *Client) GetAPIKey() string {
	return c.APIKey
}

// SetAPIKey sets the API key.
func (c *Client) SetAPIKey(key string) {
	c.APIKey = key
}

// =============================================================================
// HTTP Error Handling
// =============================================================================

// httpErrorMessages maps HTTP status codes to user-friendly messages
var httpErrorMessages = map[int]string{
	400: "bad request",
	401: "unauthorized - run `parts auth login` to authenticate",
	403: "forbidden - access denied",
	404: "not found",
	408: "request timeout",
	429: "rate limited - please wait and try again",
	500: "internal server error",
	502: "bad gateway - API server is down or unreachable",
	503: "service unavailable - API server is temporarily unavailable",
	504: "gateway timeout - API server did not respond in time",
	520: "unknown error - origin server returned unexpected response",
	521: "web server is down",
	522: "connection timed out to origin server",
	523: "origin is unreachable",
	524: "timeout occurred waiting for origin server",
	525: "SSL handshake failed",
	526: "invalid SSL certificate",
}

// formatHTTPError returns a clean, user-friendly error message for HTTP errors.
// It detects HTML responses (like Cloudflare error pages) and returns a concise message.
func formatHTTPError(statusCode int, body []byte) error {
	// Check if response is HTML (gateway errors often return HTML error pages)
	checkLen := len(body)
	if checkLen > 100 {
		checkLen = 100
	}
	isHTML := len(body) > 0 && (body[0] == '<' || bytes.Contains(body[:checkLen], []byte("<!DOCTYPE")))

	// Get friendly message for known status codes
	friendlyMsg, known := httpErrorMessages[statusCode]

	if isHTML {
		// Don't dump HTML to terminal - use friendly message or generic one
		if known {
			return fmt.Errorf("HTTP %d: %s", statusCode, friendlyMsg)
		}
		return fmt.Errorf("HTTP %d: server returned an error page", statusCode)
	}

	// For JSON/text responses, include the body if it's reasonable length
	if known {
		if len(body) > 0 && len(body) < 200 {
			return fmt.Errorf("HTTP %d: %s - %s", statusCode, friendlyMsg, string(body))
		}
		return fmt.Errorf("HTTP %d: %s", statusCode, friendlyMsg)
	}

	// Unknown status code
	if len(body) > 0 && len(body) < 200 {
		return fmt.Errorf("HTTP %d: %s", statusCode, string(body))
	}
	return fmt.Errorf("HTTP %d: request failed", statusCode)
}

// handleHTTPResponse checks the response status and returns a formatted error if needed.
// Returns nil if status is successful (< 400).
func (c *Client) handleHTTPResponse(res *http.Response) error {
	if res.StatusCode < 400 {
		return nil
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("HTTP %d: failed to read response body", res.StatusCode)
	}

	return formatHTTPError(res.StatusCode, body)
}

// =============================================================================
// Authentication
// =============================================================================

// Auth validates an API key with the server and returns user info
func (c *Client) Auth(ctx context.Context, apiKey string, w io.Writer) error {
	if apiKey == "" {
		apiKey = c.APIKey
	}

	if apiKey == "" {
		return fmt.Errorf("no API key provided")
	}

	url := domain.Endpoint_AuthValidate
	c.Logger.Printf("Request URL: %s", url)

	body := fmt.Sprintf(`{"key": %q}`, apiKey)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewBufferString(body))
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}

	c.Logger.Printf("Validating API key...")
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	c.Logger.Printf("Status Code Received: %d", res.StatusCode)

	if res.StatusCode == 401 || res.StatusCode == 403 {
		return fmt.Errorf("invalid or expired API key")
	}

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("authentication failed: %s", string(b))
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// =============================================================================
// Part Operations
// =============================================================================

// Add adds a part to the database
func (c *Client) Add(ctx context.Context, partNumber string, opts types.AddOptions, w io.Writer) error {
	url := *c.Endpoint_Add
	c.Logger.Printf("Request URL: %s", url)

	// Build JSON body
	body := map[string]string{"part_number": partNumber}
	if opts.Manufacturer != "" {
		body["manufacturer"] = opts.Manufacturer
	}
	if opts.Description != "" {
		body["description"] = opts.Description
	}
	if opts.Category != "" {
		body["category"] = opts.Category
	}
	if opts.Package != "" {
		body["package"] = opts.Package
	}
	if opts.Value != "" {
		body["value"] = opts.Value
	}

	jsonBody, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("error encoding request body: %w", err)
	}

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(jsonBody))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	c.Logger.Printf("Adding part: %s", partNumber)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// Search searches for parts with optional filters
func (c *Client) Search(ctx context.Context, query string, opts types.SearchOptions, w io.Writer) error {
	url := *c.Endpoint_Search
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	values := req.URL.Query()
	values.Add("q", query)
	limit := 25
	if opts.Limit > 0 {
		limit = opts.Limit
	}
	values.Add("limit", fmt.Sprintf("%d", limit))
	if opts.InStock {
		values.Add("in_stock", "true")
	}
	if opts.EUOnly {
		values.Add("eu_only", "true")
	}
	if opts.USOnly {
		values.Add("us_only", "true")
	}
	if opts.CNOnly {
		values.Add("cn_only", "true")
	}
	req.URL.RawQuery = values.Encode()

	c.Logger.Printf("Searching for: %s", query)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// Datasheet retrieves part datasheet
func (c *Client) Datasheet(ctx context.Context, partNumber string, w io.Writer) error {
	url := fmt.Sprintf(*c.Endpoint_Datasheet, partNumber)
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	c.Logger.Printf("Fetching datasheet for: %s", partNumber)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// Marking retrieves part marking information
func (c *Client) Marking(ctx context.Context, partNumber string, w io.Writer) error {
	url := fmt.Sprintf(*c.Endpoint_Marking, partNumber)
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// Gather gathers comprehensive part information
func (c *Client) Gather(ctx context.Context, partNumber string, w io.Writer) error {
	url := fmt.Sprintf(domain.Endpoint_Gather, partNumber)
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// =============================================================================
// BOM Operations
// =============================================================================

// BOM validates a BOM file (legacy)
func (c *Client) BOM(ctx context.Context, fileName string, w io.Writer) error {
	opts := types.BOMUploadOptions{ExtractLCSC: true}
	return c.BOMUpload(ctx, fileName, opts, w)
}

// BOMUpload uploads a BOM file to the API
func (c *Client) BOMUpload(ctx context.Context, fileName string, opts types.BOMUploadOptions, w io.Writer) error {
	// Read file
	fileContent, err := os.ReadFile(fileName)
	if err != nil {
		return fmt.Errorf("error reading file: %w", err)
	}

	// Calculate hash
	hasher := sha256.New()
	hasher.Write(fileContent)
	hashString := fmt.Sprintf("%x", hasher.Sum(nil))

	c.Logger.Printf("File: %s, SHA256: %s", fileName, hashString)

	// Create multipart form
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	baseName := filepath.Base(fileName)
	part, err := writer.CreateFormFile("file", baseName)
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := part.Write(fileContent); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	_ = writer.WriteField("hash", hashString)
	if opts.ProjectID != "" {
		_ = writer.WriteField("projectId", opts.ProjectID)
	}
	if opts.ExtractLCSC {
		_ = writer.WriteField("action", "extract_lcsc")
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("error closing writer: %w", err)
	}

	url := domain.Endpoint_BOMUpload
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, body)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// BOMStatus checks BOM processing job status
func (c *Client) BOMStatus(ctx context.Context, jobID string, w io.Writer) error {
	url := fmt.Sprintf(domain.Endpoint_BOMStatus, jobID)
	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// PollBOMStatus polls for BOM job completion
func (c *Client) PollBOMStatus(ctx context.Context, jobID string, w io.Writer) error {
	pollInterval := 2 * time.Second
	timeout := 5 * time.Minute

	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("timeout waiting for BOM processing")
		case <-ticker.C:
			buf := &bytes.Buffer{}
			if err := c.BOMStatus(ctx, jobID, buf); err != nil {
				return err
			}

			var status types.BOMStatusResponse
			if err := json.Unmarshal(buf.Bytes(), &status); err != nil {
				return fmt.Errorf("error parsing status: %w", err)
			}

			switch status.Status {
			case "completed":
				_, err := w.Write(buf.Bytes())
				return err
			case "error":
				return fmt.Errorf("BOM processing failed: %s", status.Error)
			default:
				c.Logger.Printf("Status: %s (progress: %d%%)", status.Status, status.Progress)
			}
		}
	}
}

// =============================================================================
// Project Operations
// =============================================================================

// ProjectCreate creates a new project
func (c *Client) ProjectCreate(ctx context.Context, name, description string, w io.Writer) error {
	url := domain.Endpoint_ProjectCreate
	body := fmt.Sprintf(`{"name": %q, "description": %q}`, name, description)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewBufferString(body))
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// ProjectList lists all projects for the authenticated user
func (c *Client) ProjectList(ctx context.Context, opts types.ProjectListOptions, w io.Writer) error {
	url := domain.Endpoint_ProjectList

	sep := "?"
	if opts.Limit > 0 {
		url += fmt.Sprintf("%slimit=%d", sep, opts.Limit)
		sep = "&"
	}
	if opts.Offset > 0 {
		url += fmt.Sprintf("%soffset=%d", sep, opts.Offset)
		sep = "&"
	}
	if opts.Status != "" {
		url += fmt.Sprintf("%sstatus=%s", sep, opts.Status)
	}

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	data, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("error reading response: %w", err)
	}

	var resp struct {
		Status string `json:"status"`
		Data   struct {
			Projects []struct {
				ID        string `json:"id"`
				Name      string `json:"name"`
				Status    string `json:"status"`
				CreatedAt string `json:"created_at"`
			} `json:"projects"`
			Total  int `json:"total"`
			Limit  int `json:"limit"`
			Offset int `json:"offset"`
		} `json:"data"`
	}

	if err := json.Unmarshal(data, &resp); err != nil {
		_, err = w.Write(data)
		return err
	}

	if len(resp.Data.Projects) == 0 {
		fmt.Fprintln(w, "No projects found.")
		return nil
	}

	fmt.Fprintf(w, "Projects (%d total)\n\n", resp.Data.Total)
	fmt.Fprintf(w, "  %-36s  %-30s  %-10s  %s\n", "ID", "NAME", "STATUS", "CREATED")
	fmt.Fprintf(w, "  %-36s  %-30s  %-10s  %s\n", "------------------------------------", "------------------------------", "----------", "----------")
	for _, p := range resp.Data.Projects {
		created := p.CreatedAt
		if len(created) > 10 {
			created = created[:10]
		}
		name := p.Name
		if len(name) > 30 {
			name = name[:27] + "..."
		}
		fmt.Fprintf(w, "  %-36s  %-30s  %-10s  %s\n", p.ID, name, p.Status, created)
	}

	return nil
}

// ProjectGet gets detailed information about a specific project
func (c *Client) ProjectGet(ctx context.Context, projectID string, w io.Writer) error {
	url := fmt.Sprintf(domain.Endpoint_ProjectGet, projectID)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	data, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("error reading response: %w", err)
	}

	var resp struct {
		Status string `json:"status"`
		Data   struct {
			ID          string `json:"id"`
			Name        string `json:"name"`
			Description string `json:"description"`
			Status      string `json:"status"`
			UserID      string `json:"user_id"`
			CreatedAt   string `json:"created_at"`
			UpdatedAt   string `json:"updated_at"`
			PartsCount  int    `json:"parts_count"`
		} `json:"data"`
	}

	if err := json.Unmarshal(data, &resp); err != nil {
		_, err = w.Write(data)
		return err
	}

	d := resp.Data
	fmt.Fprintf(w, "Project: %s\n\n", d.Name)
	fmt.Fprintf(w, "  ID:          %s\n", d.ID)
	if d.Description != "" {
		fmt.Fprintf(w, "  Description: %s\n", d.Description)
	}
	fmt.Fprintf(w, "  Status:      %s\n", d.Status)
	fmt.Fprintf(w, "  Owner:       %s\n", d.UserID)
	fmt.Fprintf(w, "  Created:     %s\n", d.CreatedAt)
	fmt.Fprintf(w, "  Updated:     %s\n", d.UpdatedAt)
	if d.PartsCount > 0 {
		fmt.Fprintf(w, "  Parts:       %d\n", d.PartsCount)
	}

	return nil
}

// ProjectDelete deletes a project
func (c *Client) ProjectDelete(ctx context.Context, projectID string, w io.Writer) error {
	url := fmt.Sprintf(domain.Endpoint_ProjectDelete, projectID)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodDelete, url, nil)
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	fmt.Fprintf(w, "Project %s deleted successfully.\n", projectID)
	return nil
}

// ProjectECO creates an Engineering Change Order for a project
func (c *Client) ProjectECO(ctx context.Context, projectID string, data types.ECORequest, w io.Writer) error {
	url := fmt.Sprintf(domain.Endpoint_ProjectECO, projectID)

	bodyJSON, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("error marshaling ECO data: %w", err)
	}

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyJSON))
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// ProjectTransfer transfers project ownership to another user by email
func (c *Client) ProjectTransfer(ctx context.Context, projectID, email string, w io.Writer) error {
	url := fmt.Sprintf(domain.Endpoint_ProjectTransfer, projectID)

	body := fmt.Sprintf(`{"email": %q}`, email)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewBufferString(body))
	if err != nil {
		return err
	}

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// Skeleton creates a project skeleton
func (c *Client) Skeleton(ctx context.Context, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

// =============================================================================
// QuarterMaster Operations
// =============================================================================

// Q sends a query to the QuarterMaster endpoint for intelligent dispatch
func (c *Client) Q(ctx context.Context, text, queryType string, w io.Writer) error {
	url := domain.Endpoint_Q
	c.Logger.Printf("Request URL: %s", url)

	body := fmt.Sprintf(`{"text": %s, "type": %s}`,
		mustJSON(text), mustJSON(queryType))

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewBufferString(body))
	if err != nil {
		return err
	}

	c.Logger.Printf("QuarterMaster query: %s (type: %s)", text, queryType)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// QHistory retrieves search history
func (c *Client) QHistory(ctx context.Context, limit int, w io.Writer) error {
	url := domain.Endpoint_QHistory
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	values := req.URL.Query()
	values.Add("limit", fmt.Sprintf("%d", limit))
	req.URL.RawQuery = values.Encode()

	c.Logger.Printf("Fetching search history (limit: %d)", limit)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// QHistoryClear clears search history
func (c *Client) QHistoryClear(ctx context.Context, w io.Writer) error {
	url := domain.Endpoint_QHistory
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodDelete, url, nil)
	if err != nil {
		return err
	}

	c.Logger.Printf("Clearing search history")
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// QSMD converts an SMD resistor code to resistance value
func (c *Client) QSMD(ctx context.Context, code string, w io.Writer) error {
	url := domain.Endpoint_QSMD
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	values := req.URL.Query()
	values.Add("code", code)
	req.URL.RawQuery = values.Encode()

	c.Logger.Printf("Converting SMD code: %s", code)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// QResistorColors calculates resistance from color bands
func (c *Client) QResistorColors(ctx context.Context, bands string, w io.Writer) error {
	url := domain.Endpoint_QResistorColors
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	values := req.URL.Query()
	values.Add("bands", bands)
	req.URL.RawQuery = values.Encode()

	c.Logger.Printf("Calculating resistor colors: %s", bands)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// mustJSON marshals a string to JSON (with proper escaping)
func mustJSON(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// =============================================================================
// Stub implementations for remaining methods
// =============================================================================

// DFMSubmit submits a DFM analysis referencing a BOM and/or project
func (c *Client) DFMSubmit(ctx context.Context, bomID, projectID string, w io.Writer) error {
	url := domain.Endpoint_ManufacturingDFM
	c.Logger.Printf("Request URL: %s", url)

	payload := map[string]string{}
	if bomID != "" {
		payload["bom_id"] = bomID
	}
	if projectID != "" {
		payload["project_id"] = projectID
	}

	jsonBody, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("error marshaling request: %w", err)
	}

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(jsonBody))
	if err != nil {
		return err
	}

	c.Logger.Printf("Submitting DFM analysis (bom_id=%s, project_id=%s)", bomID, projectID)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

func (c *Client) DFM(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Fabricate(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) AOI(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) QC(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Publish(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

// Stackup generates a stackup PDF from a gerber ZIP file
func (c *Client) Stackup(ctx context.Context, gerberZip string, opts types.StackupOptions, w io.Writer) error {
	fileContent, err := os.ReadFile(gerberZip)
	if err != nil {
		return fmt.Errorf("error reading file: %w", err)
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	baseName := filepath.Base(gerberZip)
	part, err := writer.CreateFormFile("file", baseName)
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := part.Write(fileContent); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	if opts.BoardName != "" {
		_ = writer.WriteField("board_name", opts.BoardName)
	}
	if opts.Scale > 0 {
		_ = writer.WriteField("scale", fmt.Sprintf("%d", opts.Scale))
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("error closing writer: %w", err)
	}

	url := domain.Endpoint_ManufacturingStackup
	c.Logger.Printf("Request URL: %s", url)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, body)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	c.Logger.Printf("Generating stackup PDF for: %s", baseName)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	return c.writePDFResponse(res, opts.Output, baseName, "stackup", w)
}

// StackupDiff generates a layer-by-layer diff PDF between two gerber revisions
func (c *Client) StackupDiff(ctx context.Context, gerberA, gerberB string, opts types.StackupDiffOptions, w io.Writer) error {
	fileContentA, err := os.ReadFile(gerberA)
	if err != nil {
		return fmt.Errorf("error reading file %s: %w", gerberA, err)
	}
	fileContentB, err := os.ReadFile(gerberB)
	if err != nil {
		return fmt.Errorf("error reading file %s: %w", gerberB, err)
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	partA, err := writer.CreateFormFile("gerbers_a", filepath.Base(gerberA))
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := partA.Write(fileContentA); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	partB, err := writer.CreateFormFile("gerbers_b", filepath.Base(gerberB))
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := partB.Write(fileContentB); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	if opts.NameA != "" {
		_ = writer.WriteField("name_a", opts.NameA)
	}
	if opts.NameB != "" {
		_ = writer.WriteField("name_b", opts.NameB)
	}
	if opts.DPI > 0 {
		_ = writer.WriteField("dpi", fmt.Sprintf("%d", opts.DPI))
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("error closing writer: %w", err)
	}

	url := domain.Endpoint_ManufacturingStackupDiff
	c.Logger.Printf("Request URL: %s", url)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, body)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	c.Logger.Printf("Generating stackup diff: %s vs %s", filepath.Base(gerberA), filepath.Base(gerberB))
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	return c.writePDFResponse(res, opts.Output, filepath.Base(gerberA), "stackup-diff", w)
}

// writePDFResponse writes a binary PDF response to a file or writer.
// It uses the output path if provided, otherwise derives a filename from the
// Content-Disposition header or falls back to a default name.
func (c *Client) writePDFResponse(res *http.Response, outputPath, baseName, suffix string, w io.Writer) error {
	if outputPath != "" {
		f, err := os.Create(outputPath)
		if err != nil {
			return fmt.Errorf("error creating output file: %w", err)
		}
		defer f.Close()

		n, err := io.Copy(f, res.Body)
		if err != nil {
			return fmt.Errorf("error writing PDF: %w", err)
		}
		fmt.Fprintf(w, "Saved %s (%d bytes)\n", outputPath, n)
		return nil
	}

	// Derive filename from Content-Disposition or fall back to default
	fileName := ""
	if cd := res.Header.Get("Content-Disposition"); cd != "" {
		// Parse "attachment; filename=xyz.pdf"
		for _, part := range splitContentDisposition(cd) {
			if len(part) > 9 && part[:9] == "filename=" {
				fileName = part[9:]
				// Strip quotes
				if len(fileName) >= 2 && fileName[0] == '"' && fileName[len(fileName)-1] == '"' {
					fileName = fileName[1 : len(fileName)-1]
				}
				break
			}
		}
	}
	if fileName == "" {
		ext := filepath.Ext(baseName)
		nameWithoutExt := baseName[:len(baseName)-len(ext)]
		fileName = nameWithoutExt + "-" + suffix + ".pdf"
	}

	f, err := os.Create(fileName)
	if err != nil {
		return fmt.Errorf("error creating output file: %w", err)
	}
	defer f.Close()

	n, err := io.Copy(f, res.Body)
	if err != nil {
		return fmt.Errorf("error writing PDF: %w", err)
	}
	fmt.Fprintf(w, "Saved %s (%d bytes)\n", fileName, n)
	return nil
}

// splitContentDisposition splits a Content-Disposition header value by semicolons,
// trimming whitespace from each part.
func splitContentDisposition(cd string) []string {
	var parts []string
	for _, p := range bytes.Split([]byte(cd), []byte(";")) {
		trimmed := bytes.TrimSpace(p)
		if len(trimmed) > 0 {
			parts = append(parts, string(trimmed))
		}
	}
	return parts
}

func (c *Client) Inventory(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Cart(ctx context.Context, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Buy(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) RFQ(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Wishlist(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Tracker(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Box(ctx context.Context, boxID string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Balance(ctx context.Context, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

// Price estimates pricing for a part at a given quantity
func (c *Client) Price(ctx context.Context, partNumber string, opts types.PriceOptions, w io.Writer) error {
	url := domain.Endpoint_CostsEstimate
	c.Logger.Printf("Request URL: %s", url)

	quantity := opts.Quantity
	if quantity <= 0 {
		quantity = 1
	}
	currency := opts.Currency
	if currency == "" {
		currency = "USD"
	}

	payload := map[string]interface{}{
		"parts": []map[string]interface{}{
			{
				"part_number": partNumber,
				"quantity":    quantity,
			},
		},
		"currency": currency,
	}

	jsonBody, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("error marshaling request: %w", err)
	}

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(jsonBody))
	if err != nil {
		return err
	}

	c.Logger.Printf("Estimating price for %s (qty: %d, currency: %s)", partNumber, quantity, currency)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// CreditsBalance fetches the current sourcing credit balance
func (c *Client) CreditsBalance(ctx context.Context, jsonOutput bool, w io.Writer) error {
	url := domain.Endpoint_CreditsBalance
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	c.Logger.Printf("Fetching credit balance")
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return fmt.Errorf("failed to fetch credit balance: %w", err)
	}

	data, err := io.ReadAll(res.Body)
	if err != nil {
		return fmt.Errorf("error reading response: %w", err)
	}

	if jsonOutput {
		_, err = w.Write(data)
		if err == nil {
			fmt.Fprintln(w)
		}
		return err
	}

	// Try to format the response nicely
	var resp struct {
		Status string `json:"status"`
		Data   struct {
			Balance  float64 `json:"balance"`
			Currency string  `json:"currency"`
			Plan     string  `json:"plan"`
		} `json:"data"`
	}

	if err := json.Unmarshal(data, &resp); err != nil {
		// If we can't parse it, just output the raw response
		_, err = w.Write(data)
		if err == nil {
			fmt.Fprintln(w)
		}
		return err
	}

	currency := resp.Data.Currency
	if currency == "" {
		currency = "USD"
	}

	fmt.Fprintf(w, "Credit Balance: %.2f %s\n", resp.Data.Balance, currency)
	if resp.Data.Plan != "" {
		fmt.Fprintf(w, "Plan: %s\n", resp.Data.Plan)
	}

	return nil
}

func (c *Client) COGs(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Expense(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Note(ctx context.Context, note string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Todo(ctx context.Context, todoItem string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Report(ctx context.Context, reportType string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Init(ctx context.Context, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Log(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Status(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Clean(ctx context.Context, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Scan(ctx context.Context, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Label(ctx context.Context, partNumber string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Detect(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Guide(ctx context.Context, topic string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Docs(ctx context.Context, topic string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Pull(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Push(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Tag(ctx context.Context, tag string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

// Release uploads gerbers and creates a manufacturing-ready release package.
// It POSTs the file to the publish endpoint, then polls for job completion.
func (c *Client) Release(ctx context.Context, input string, opts types.ReleaseOptions, w io.Writer) error {
	fileContent, err := os.ReadFile(input)
	if err != nil {
		return fmt.Errorf("error reading file: %w", err)
	}

	// Create multipart form
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", filepath.Base(input))
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := part.Write(fileContent); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	if opts.Version != "" {
		_ = writer.WriteField("version", opts.Version)
	}
	if opts.Notes != "" {
		_ = writer.WriteField("release_notes", opts.Notes)
	}
	if opts.IncludeBOM {
		_ = writer.WriteField("include_bom", "true")
	}
	if opts.IncludeAsm {
		_ = writer.WriteField("include_assembly", "true")
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("error closing writer: %w", err)
	}

	url := domain.Endpoint_ManufacturingPublish
	c.Logger.Printf("Request URL: %s", url)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, body)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	c.Logger.Printf("Uploading release package: %s", filepath.Base(input))
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	// Parse initial response for job ID
	var releaseResp types.ReleaseResponse
	if err := json.NewDecoder(res.Body).Decode(&releaseResp); err != nil {
		return fmt.Errorf("error parsing response: %w", err)
	}

	jobID := releaseResp.Data.JobID
	if jobID == "" {
		return fmt.Errorf("no job ID returned from API")
	}

	c.Logger.Printf("Job ID: %s", jobID)

	// Poll for completion
	pollInterval := 2 * time.Second
	pollTimeout := 5 * time.Minute

	pollCtx, cancel := context.WithTimeout(ctx, pollTimeout)
	defer cancel()

	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-pollCtx.Done():
			return fmt.Errorf("timeout waiting for release processing")
		case <-ticker.C:
			statusURL := fmt.Sprintf(domain.Endpoint_ManufacturingStatus, jobID)
			statusReq, err := c.newAuthenticatedRequestWithContext(pollCtx, http.MethodGet, statusURL, nil)
			if err != nil {
				return err
			}

			statusRes, err := c.Client.Do(statusReq)
			if err != nil {
				return fmt.Errorf("error checking status: %w", err)
			}

			var status types.ReleaseStatusResponse
			if err := json.NewDecoder(statusRes.Body).Decode(&status); err != nil {
				statusRes.Body.Close()
				return fmt.Errorf("error parsing status: %w", err)
			}
			statusRes.Body.Close()

			switch status.Status {
			case "completed":
				fmt.Fprintf(w, "Gerbers validated. %d DRC errors.\n", status.Data.DRCErrors)
				if status.Data.PackageURL != "" {
					fmt.Fprintf(w, "Package: %s\n", status.Data.PackageURL)
				}
				fmt.Fprintln(w, "validated. quoted. ordered.")
				return nil
			case "error":
				return fmt.Errorf("release processing failed: %s", status.Error)
			default:
				c.Logger.Printf("Status: %s (progress: %d%%)", status.Status, status.Progress)
			}
		}
	}
}

func (c *Client) Test(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

// =============================================================================
// EDA — ERC, DRC, Altium Import (via convert.source.parts)
// =============================================================================

// edaUpload uploads a file (and optional secondary file) to a convert-service
// endpoint and streams the response body to w.
func (c *Client) edaUpload(ctx context.Context, endpoint, filePath string, formFields map[string]string, extraFiles map[string]string, w io.Writer) error {
	fileContent, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("error reading file: %w", err)
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	// Add primary file
	part, err := writer.CreateFormFile("file", filepath.Base(filePath))
	if err != nil {
		return fmt.Errorf("error creating form file: %w", err)
	}
	if _, err := part.Write(fileContent); err != nil {
		return fmt.Errorf("error writing file to form: %w", err)
	}

	// Add optional extra files (e.g. rules_file)
	for fieldName, path := range extraFiles {
		if path == "" {
			continue
		}
		extraContent, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("error reading %s: %w", fieldName, err)
		}
		extraPart, err := writer.CreateFormFile(fieldName, filepath.Base(path))
		if err != nil {
			return fmt.Errorf("error creating form file %s: %w", fieldName, err)
		}
		if _, err := extraPart.Write(extraContent); err != nil {
			return fmt.Errorf("error writing %s to form: %w", fieldName, err)
		}
	}

	// Add form fields
	for key, value := range formFields {
		if value != "" {
			_ = writer.WriteField(key, value)
		}
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("error closing multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, body)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}

	c.Logger.Printf("Request URL: %s", endpoint)
	c.Logger.Printf("Uploading: %s (%d bytes)", filepath.Base(filePath), len(fileContent))

	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if err := c.handleHTTPResponse(res); err != nil {
		return err
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// ERC runs Electrical Rules Check on a KiCad schematic.
func (c *Client) ERC(ctx context.Context, fileName string, opts types.ERCOptions, w io.Writer) error {
	fields := map[string]string{"severity": opts.Severity}
	extras := map[string]string{"rules_file": opts.RulesFile}
	return c.edaUpload(ctx, domain.Endpoint_ERC, fileName, fields, extras, w)
}

// DRC runs Design Rules Check on a KiCad PCB.
func (c *Client) DRC(ctx context.Context, fileName string, opts types.DRCOptions, w io.Writer) error {
	fields := map[string]string{"severity": opts.Severity}
	extras := map[string]string{"rules_file": opts.RulesFile}
	return c.edaUpload(ctx, domain.Endpoint_DRC, fileName, fields, extras, w)
}

// ImportAltium converts an Altium .SchDoc to KiCad .kicad_sch.
// If outputPath is non-empty the converted file is saved there; otherwise the
// response is streamed to w.
func (c *Client) ImportAltium(ctx context.Context, fileName string, outputPath string, w io.Writer) error {
	var buf bytes.Buffer
	if err := c.edaUpload(ctx, domain.Endpoint_ImportAltium, fileName, nil, nil, &buf); err != nil {
		return err
	}

	if outputPath != "" {
		if err := os.WriteFile(outputPath, buf.Bytes(), 0644); err != nil {
			return fmt.Errorf("error writing output file: %w", err)
		}
		fmt.Fprintf(w, "Saved: %s\n", outputPath)
		return nil
	}

	_, err := io.Copy(w, &buf)
	return err
}

func (c *Client) ImportAltiumBytes(ctx context.Context, fileName string) ([]byte, error) {
	var buf bytes.Buffer
	if err := c.edaUpload(ctx, domain.Endpoint_ImportAltium, fileName, nil, nil, &buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
