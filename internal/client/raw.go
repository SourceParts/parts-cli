package client

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"

	"github.com/SourceParts/parts-cli/internal/domain"
)

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
