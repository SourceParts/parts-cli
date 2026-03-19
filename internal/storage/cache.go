package storage

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
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
