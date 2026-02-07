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
	"path/filepath"
	"time"

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
func (c *Client) Add(ctx context.Context, partNumber string, w io.Writer) error {
	url := *c.Endpoint_Add
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodPost, url, nil)
	if err != nil {
		return err
	}

	values := req.URL.Query()
	values.Add("p", partNumber)
	req.URL.RawQuery = values.Encode()

	c.Logger.Printf("Adding part: %s", partNumber)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// Search searches for parts
func (c *Client) Search(ctx context.Context, query string, w io.Writer) error {
	url := *c.Endpoint_Search
	c.Logger.Printf("Request URL: %s", url)

	req, err := c.newAuthenticatedRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	values := req.URL.Query()
	values.Add("q", query)
	values.Add("limit", "25")
	req.URL.RawQuery = values.Encode()

	c.Logger.Printf("Searching for: %s", query)
	res, err := c.Client.Do(req)
	if err != nil {
		return fmt.Errorf("error executing request: %w", err)
	}
	defer res.Body.Close()

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
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

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
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

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
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

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
	}

	_, err = io.Copy(w, res.Body)
	return err
}

// =============================================================================
// BOM Operations
// =============================================================================

// BOM validates a BOM file (legacy)
func (c *Client) BOM(ctx context.Context, fileName string, w io.Writer) error {
	opts := domain.BOMUploadOptions{ExtractLCSC: true}
	return c.BOMUpload(ctx, fileName, opts, w)
}

// BOMUpload uploads a BOM file to the API
func (c *Client) BOMUpload(ctx context.Context, fileName string, opts domain.BOMUploadOptions, w io.Writer) error {
	// Read file
	fileContent, err := io.ReadAll(bytes.NewReader([]byte{})) // Placeholder - needs actual file reading
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

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
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

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
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

			var status domain.BOMStatusResponse
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

	if res.StatusCode > 399 {
		b, _ := io.ReadAll(res.Body)
		return fmt.Errorf("error response: %s", string(b))
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
// Stub implementations for remaining methods
// =============================================================================

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

func (c *Client) Release(ctx context.Context, version string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}

func (c *Client) Test(ctx context.Context, input string, w io.Writer) error {
	fmt.Fprintln(w, "Not implemented yet")
	return nil
}
