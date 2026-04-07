package storage

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	net_http "net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const cacheDir = ".cache/parts/datasheets"

// DatasheetAlias maps a friendly name to a content-addressed datasheet.
type DatasheetAlias struct {
	ContentHash string `json:"content_hash"`
	Filename    string `json:"filename"`
	Created     string `json:"created"`
}

var aliasNameRe = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.\-]*$`)
var hexOnly16Re = regexp.MustCompile(`^[0-9a-fA-F]{16}$`)

func aliasFilePath() string {
	return filepath.Join(datasheetCacheRoot(), "aliases.json")
}

// LoadAliases reads aliases.json, returning an empty map if the file is missing.
func LoadAliases() (map[string]DatasheetAlias, error) {
	data, err := os.ReadFile(aliasFilePath())
	if err != nil {
		if os.IsNotExist(err) {
			return make(map[string]DatasheetAlias), nil
		}
		return nil, fmt.Errorf("read aliases: %w", err)
	}
	var aliases map[string]DatasheetAlias
	if err := json.Unmarshal(data, &aliases); err != nil {
		return nil, fmt.Errorf("parse aliases: %w", err)
	}
	if aliases == nil {
		aliases = make(map[string]DatasheetAlias)
	}
	return aliases, nil
}

// SaveAliases atomically writes aliases to aliases.json.
func SaveAliases(aliases map[string]DatasheetAlias) error {
	dir := datasheetCacheRoot()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("create cache dir: %w", err)
	}
	data, err := json.MarshalIndent(aliases, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal aliases: %w", err)
	}
	tmp := aliasFilePath() + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return fmt.Errorf("write tmp aliases: %w", err)
	}
	if err := os.Rename(tmp, aliasFilePath()); err != nil {
		return fmt.Errorf("rename aliases: %w", err)
	}
	return nil
}

// ValidateAliasName checks that a name is valid for use as an alias.
func ValidateAliasName(name string) error {
	if name == "" {
		return fmt.Errorf("alias name cannot be empty")
	}
	if len(name) > 64 {
		return fmt.Errorf("alias name too long (max 64 chars)")
	}
	if !aliasNameRe.MatchString(name) {
		return fmt.Errorf("alias name must match [a-zA-Z0-9][a-zA-Z0-9_.-]*")
	}
	if hexOnly16Re.MatchString(name) {
		return fmt.Errorf("alias name must not be a 16-char hex string (ambiguous with content hashes)")
	}
	return nil
}

// SetAlias creates or updates an alias mapping.
func SetAlias(name, contentHash, filename string) error {
	if err := ValidateAliasName(name); err != nil {
		return err
	}
	aliases, err := LoadAliases()
	if err != nil {
		return err
	}
	aliases[name] = DatasheetAlias{
		ContentHash: contentHash,
		Filename:    filename,
		Created:     time.Now().UTC().Format(time.RFC3339),
	}
	return SaveAliases(aliases)
}

// RemoveAlias deletes an alias by name.
func RemoveAlias(name string) error {
	aliases, err := LoadAliases()
	if err != nil {
		return err
	}
	if _, ok := aliases[name]; !ok {
		return fmt.Errorf("alias %q not found", name)
	}
	delete(aliases, name)
	return SaveAliases(aliases)
}

// ResolveAlias looks up an alias and returns the content hash and filename.
func ResolveAlias(name string) (contentHash, filename string, ok bool) {
	aliases, err := LoadAliases()
	if err != nil {
		return "", "", false
	}
	a, found := aliases[name]
	if !found {
		return "", "", false
	}
	return a.ContentHash, a.Filename, true
}

// CachedDatasheet describes a file in the local cache.
type CachedDatasheet struct {
	ContentHash string
	Filename    string
	Path        string
	Size        int64
}

// datasheetCacheRoot returns ~/.cache/parts/datasheets.
func datasheetCacheRoot() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, cacheDir)
}

// DatasheetCachePath returns the local cache path for a given content hash and filename.
func DatasheetCachePath(contentHash, filename string) string {
	return filepath.Join(datasheetCacheRoot(), "sha256_"+contentHash, filename)
}

// ContentHash returns the first 16 hex characters of the SHA256 of the file at path.
func ContentHash(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open file for hashing: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hash file: %w", err)
	}
	return fmt.Sprintf("%x", h.Sum(nil)[:8]), nil // first 16 hex chars
}

// CacheDatasheet copies a local file into the cache using its content hash.
// Returns the cached path and content hash.
func CacheDatasheet(localPath string) (cachedPath string, contentHash string, err error) {
	hash, err := ContentHash(localPath)
	if err != nil {
		return "", "", err
	}

	dst := DatasheetCachePath(hash, filepath.Base(localPath))
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return "", "", fmt.Errorf("create cache dir: %w", err)
	}

	src, err := os.Open(localPath)
	if err != nil {
		return "", "", fmt.Errorf("open source: %w", err)
	}
	defer src.Close()

	out, err := os.Create(dst)
	if err != nil {
		return "", "", fmt.Errorf("create cache file: %w", err)
	}
	defer out.Close()

	if _, err := io.Copy(out, src); err != nil {
		return "", "", fmt.Errorf("copy to cache: %w", err)
	}

	return dst, hash, nil
}

// GetCachedDatasheet checks if a file exists in the local cache.
func GetCachedDatasheet(contentHash, filename string) (string, bool) {
	p := DatasheetCachePath(contentHash, filename)
	if _, err := os.Stat(p); err == nil {
		return p, true
	}
	return "", false
}

// ListCachedDatasheets returns all cached datasheet files.
func ListCachedDatasheets() ([]CachedDatasheet, error) {
	root := datasheetCacheRoot()
	if _, err := os.Stat(root); os.IsNotExist(err) {
		return nil, nil
	}

	var results []CachedDatasheet
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, fmt.Errorf("read cache dir: %w", err)
	}

	for _, dir := range entries {
		if !dir.IsDir() || !strings.HasPrefix(dir.Name(), "sha256_") {
			continue
		}
		hash := strings.TrimPrefix(dir.Name(), "sha256_")
		subDir := filepath.Join(root, dir.Name())

		files, err := os.ReadDir(subDir)
		if err != nil {
			continue
		}
		for _, f := range files {
			if f.IsDir() {
				continue
			}
			info, _ := f.Info()
			size := int64(0)
			if info != nil {
				size = info.Size()
			}
			results = append(results, CachedDatasheet{
				ContentHash: hash,
				Filename:    f.Name(),
				Path:        filepath.Join(subDir, f.Name()),
				Size:        size,
			})
		}
	}
	return results, nil
}

// PageSpec represents parsed page numbers from user input.
type PageSpec struct {
	Pages []int
}

// ParsePageSpec parses a page specification string into sorted, deduplicated page numbers.
// Supports: single page ("29"), comma-separated ("29,143"), ranges ("1-5"), and combinations ("1-3,7,10-12").
func ParsePageSpec(spec string) (PageSpec, error) {
	if spec == "" {
		return PageSpec{}, fmt.Errorf("page specification cannot be empty")
	}

	seen := make(map[int]bool)
	parts := strings.Split(spec, ",")

	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		if strings.Contains(part, "-") {
			bounds := strings.SplitN(part, "-", 2)
			start, err := strconv.Atoi(strings.TrimSpace(bounds[0]))
			if err != nil {
				return PageSpec{}, fmt.Errorf("invalid page number %q: %w", bounds[0], err)
			}
			end, err := strconv.Atoi(strings.TrimSpace(bounds[1]))
			if err != nil {
				return PageSpec{}, fmt.Errorf("invalid page number %q: %w", bounds[1], err)
			}
			if start > end {
				return PageSpec{}, fmt.Errorf("invalid range %d-%d: start must be <= end", start, end)
			}
			if end-start > 100 {
				return PageSpec{}, fmt.Errorf("range %d-%d too large (max 100 pages per range)", start, end)
			}
			for i := start; i <= end; i++ {
				seen[i] = true
			}
		} else {
			page, err := strconv.Atoi(part)
			if err != nil {
				return PageSpec{}, fmt.Errorf("invalid page number %q: %w", part, err)
			}
			seen[page] = true
		}
	}

	if len(seen) == 0 {
		return PageSpec{}, fmt.Errorf("no valid page numbers in specification")
	}

	pages := make([]int, 0, len(seen))
	for p := range seen {
		if p < 1 {
			return PageSpec{}, fmt.Errorf("page numbers must be >= 1, got %d", p)
		}
		pages = append(pages, p)
	}
	sort.Ints(pages)

	return PageSpec{Pages: pages}, nil
}

// ReadPages renders specified pages from a cached PDF as PNG images.
// Tries the API first (GET /v1/datasheets/<alias>/pages/<page>/image),
// falls back to local pdftoppm if the API is unavailable.
// Returns paths to the rendered PNG files.
func ReadPages(contentHash, filename string, spec PageSpec, outputDir string) ([]string, error) {
	_, ok := GetCachedDatasheet(contentHash, filename)
	if !ok {
		return nil, fmt.Errorf("datasheet sha256_%s/%s not found in cache", contentHash, filename)
	}

	// Create output directory
	var err error
	if outputDir == "" {
		outputDir, err = os.MkdirTemp("", "parts-datasheet-*")
		if err != nil {
			return nil, fmt.Errorf("create temp dir: %w", err)
		}
	} else {
		if err := os.MkdirAll(outputDir, 0755); err != nil {
			return nil, fmt.Errorf("create output dir: %w", err)
		}
	}

	prefix := strings.TrimSuffix(filename, filepath.Ext(filename))

	// Try API first
	paths, apiErr := readPagesFromAPI(contentHash, filename, spec, outputDir, prefix)
	if apiErr == nil {
		return paths, nil
	}

	// Fall back to local pdftoppm
	return readPagesLocal(contentHash, filename, spec, outputDir, prefix)
}

// readPagesFromAPI fetches rendered page images from the Source Parts API.
func readPagesFromAPI(contentHash, filename string, spec PageSpec, outputDir, prefix string) ([]string, error) {
	apiBase := os.Getenv("PARTS_API_URL")
	if apiBase == "" {
		apiBase = "https://api.source.parts"
	}

	apiKey := os.Getenv("PARTS_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("no API key available")
	}

	// Use content hash as the SKU identifier for the API
	sku := contentHash

	var paths []string
	client := &net_http.Client{Timeout: 30 * time.Second}

	for _, page := range spec.Pages {
		url := fmt.Sprintf("%s/v1/datasheets/%s/pages/%d/image?dpi=200", apiBase, sku, page)
		req, err := net_http.NewRequest("GET", url, nil)
		if err != nil {
			return paths, fmt.Errorf("create request: %w", err)
		}
		req.Header.Set("Authorization", "Bearer "+apiKey)

		resp, err := client.Do(req)
		if err != nil {
			return paths, fmt.Errorf("API request failed: %w", err)
		}

		if resp.StatusCode != 200 {
			resp.Body.Close()
			return paths, fmt.Errorf("API returned %d for page %d", resp.StatusCode, page)
		}

		outPath := filepath.Join(outputDir, fmt.Sprintf("%s_p%d.png", prefix, page))
		outFile, err := os.Create(outPath)
		if err != nil {
			resp.Body.Close()
			return paths, fmt.Errorf("create output file: %w", err)
		}

		_, err = io.Copy(outFile, resp.Body)
		resp.Body.Close()
		outFile.Close()
		if err != nil {
			return paths, fmt.Errorf("save page %d: %w", page, err)
		}

		paths = append(paths, outPath)
	}

	return paths, nil
}

// readPagesLocal renders pages using local pdftoppm (poppler).
func readPagesLocal(contentHash, filename string, spec PageSpec, outputDir, prefix string) ([]string, error) {
	pdfPath, ok := GetCachedDatasheet(contentHash, filename)
	if !ok {
		return nil, fmt.Errorf("datasheet sha256_%s/%s not found in cache", contentHash, filename)
	}

	pdftoppmPath, err := exec.LookPath("pdftoppm")
	if err != nil {
		return nil, fmt.Errorf("pdftoppm not found in PATH — install poppler:\n  brew install poppler\n\nOr set PARTS_API_KEY to use the API instead.")
	}

	var paths []string
	for _, page := range spec.Pages {
		outPrefix := filepath.Join(outputDir, fmt.Sprintf("%s_p%d", prefix, page))
		cmd := exec.Command(pdftoppmPath, "-png", "-r", "200",
			"-f", strconv.Itoa(page), "-l", strconv.Itoa(page),
			pdfPath, outPrefix)
		if out, err := cmd.CombinedOutput(); err != nil {
			return paths, fmt.Errorf("pdftoppm page %d: %w\n%s", page, err, string(out))
		}

		matches, _ := filepath.Glob(outPrefix + "*.png")
		if len(matches) == 0 {
			return paths, fmt.Errorf("pdftoppm produced no output for page %d", page)
		}
		paths = append(paths, matches[0])
	}

	return paths, nil
}
