package update

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/schollz/progressbar/v3"
)

const (
	stagedDirName  = "staged"
	stagedMetaFile = "staged.json"
)

// StagedUpdate describes a downloaded update waiting to be applied.
type StagedUpdate struct {
	Version   string    `json:"version"`
	StagedAt  time.Time `json:"staged_at"`
	BinaryPath string   `json:"binary_path"`
}

// stagingDir returns ~/.config/parts/staged/
func stagingDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		home, _ := os.UserHomeDir()
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, "parts", stagedDirName)
}

// DownloadAndInstall downloads a new version and stages it for the next run.
// The staged binary is applied automatically on the next CLI invocation via
// ApplyStagedUpdate(). This avoids overwriting the currently running binary.
func DownloadAndInstall(ctx context.Context, asset *Asset, currentVersion string, client *http.Client) error {
	stageDir := stagingDir()
	if err := os.MkdirAll(stageDir, 0700); err != nil {
		return fmt.Errorf("failed to create staging dir: %w", err)
	}

	// Create temp file for the archive download
	tmpFile, err := os.CreateTemp("", "parts-update-*.tar.gz")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	// Download asset
	if err := downloadAsset(ctx, asset, tmpFile, client); err != nil {
		tmpFile.Close()
		return fmt.Errorf("failed to download update: %w", err)
	}
	tmpFile.Close()

	// Verify checksum if provided
	if asset.Checksum != "" {
		if err := verifyChecksum(tmpPath, asset.Checksum); err != nil {
			return fmt.Errorf("checksum verification failed: %w", err)
		}
	}

	// Extract binary from archive into staging dir
	binaryPath, err := extractBinary(tmpPath)
	if err != nil {
		return fmt.Errorf("failed to extract binary: %w", err)
	}

	// Move extracted binary to staging dir
	stagedBinary := filepath.Join(stageDir, "parts")
	if err := os.Rename(binaryPath, stagedBinary); err != nil {
		// Rename fails across filesystems — fall back to copy+delete
		if err := copyFile(binaryPath, stagedBinary); err != nil {
			os.Remove(binaryPath)
			return fmt.Errorf("failed to stage binary: %w", err)
		}
		os.Remove(binaryPath)
	}
	if err := os.Chmod(stagedBinary, 0755); err != nil {
		return fmt.Errorf("failed to chmod staged binary: %w", err)
	}

	// Parse the version from the release tag
	version := strings.TrimPrefix(asset.Name, "parts-cli_")
	version = strings.Split(version, "_")[0] // e.g. "0.9.0" from "parts-cli_0.9.0_darwin_arm64.tar.gz"

	// Write staging metadata
	meta := StagedUpdate{
		Version:    version,
		StagedAt:   time.Now().UTC(),
		BinaryPath: stagedBinary,
	}
	metaData, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to encode staging metadata: %w", err)
	}
	metaPath := filepath.Join(stageDir, stagedMetaFile)
	if err := os.WriteFile(metaPath, metaData, 0600); err != nil {
		return fmt.Errorf("failed to write staging metadata: %w", err)
	}

	return nil
}

// ApplyStagedUpdate checks for a staged update and applies it by replacing
// the current binary. Call this at the very start of main(), before any
// real work. Returns the new version string if an update was applied, or
// empty string if there was nothing to apply.
func ApplyStagedUpdate() string {
	stageDir := stagingDir()
	metaPath := filepath.Join(stageDir, stagedMetaFile)

	data, err := os.ReadFile(metaPath)
	if err != nil {
		return "" // no staged update
	}

	var meta StagedUpdate
	if err := json.Unmarshal(data, &meta); err != nil {
		// Corrupted metadata — clean up
		os.RemoveAll(stageDir)
		return ""
	}

	// Verify staged binary exists
	if _, err := os.Stat(meta.BinaryPath); err != nil {
		os.RemoveAll(stageDir)
		return ""
	}

	// Get current executable path
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	realPath, err := filepath.EvalSymlinks(exePath)
	if err != nil {
		realPath = exePath
	}

	// Get current permissions
	info, err := os.Stat(realPath)
	if err != nil {
		return ""
	}
	fileMode := info.Mode()

	// Create backup of current binary
	backupPath := realPath + ".backup.pre-" + meta.Version
	if err := copyFile(realPath, backupPath); err != nil {
		// Can't backup — abort
		return ""
	}

	// Replace current binary with staged binary
	if err := copyFile(meta.BinaryPath, realPath); err != nil {
		// Failed — restore from backup
		_ = copyFile(backupPath, realPath)
		return ""
	}

	// Restore permissions
	_ = os.Chmod(realPath, fileMode)

	// Clean up staging dir
	os.RemoveAll(stageDir)

	// Clean up old backups (keep last 3)
	cleanupOldBackups(realPath, 3)

	return meta.Version
}

// downloadAsset downloads an asset to the provided writer
func downloadAsset(ctx context.Context, asset *Asset, writer io.Writer, client *http.Client) error {
	req, err := http.NewRequestWithContext(ctx, "GET", asset.DownloadURL, nil)
	if err != nil {
		return err
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed with status %d", resp.StatusCode)
	}

	// Create progress bar
	bar := progressbar.DefaultBytes(
		asset.Size,
		"Downloading",
	)

	// Wrap writer with progress bar
	_, err = io.Copy(io.MultiWriter(writer, bar), resp.Body)
	return err
}

// extractBinary extracts the binary from a tar.gz archive
func extractBinary(archivePath string) (string, error) {
	file, err := os.Open(archivePath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		return "", fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	// Find the binary in the archive (look for file named "parts")
	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", fmt.Errorf("failed to read tar: %w", err)
		}

		// Look for the binary file
		if header.Typeflag == tar.TypeReg {
			baseName := filepath.Base(header.Name)
			if baseName == "parts" || strings.HasPrefix(baseName, "parts") {
				// Extract to temp file
				tmpFile, err := os.CreateTemp("", "parts-binary-*")
				if err != nil {
					return "", fmt.Errorf("failed to create temp file: %w", err)
				}
				tmpPath := tmpFile.Name()

				if _, err := io.Copy(tmpFile, tr); err != nil {
					tmpFile.Close()
					os.Remove(tmpPath)
					return "", fmt.Errorf("failed to extract binary: %w", err)
				}
				tmpFile.Close()

				// Make executable
				if err := os.Chmod(tmpPath, 0755); err != nil {
					os.Remove(tmpPath)
					return "", fmt.Errorf("failed to make binary executable: %w", err)
				}

				return tmpPath, nil
			}
		}
	}

	return "", fmt.Errorf("binary not found in archive")
}

// verifyChecksum verifies the SHA256 checksum of a file
func verifyChecksum(filePath, expectedSum string) error {
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return err
	}

	actualSum := hex.EncodeToString(hash.Sum(nil))
	if actualSum != expectedSum {
		return fmt.Errorf("checksum mismatch: expected %s, got %s", expectedSum, actualSum)
	}

	return nil
}

// copyFile copies a file from src to dst
func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()

	if _, err := io.Copy(destFile, sourceFile); err != nil {
		return err
	}

	// Sync to ensure data is written to disk
	return destFile.Sync()
}

// cleanupOldBackups removes old backup files, keeping only the most recent N backups
func cleanupOldBackups(exePath string, keepCount int) error {
	dir := filepath.Dir(exePath)
	base := filepath.Base(exePath)

	// Find all backup files
	pattern := filepath.Join(dir, base+".backup.*")
	backups, err := filepath.Glob(pattern)
	if err != nil {
		return err
	}

	// Sort by modification time (newest first)
	sort.Slice(backups, func(i, j int) bool {
		infoI, _ := os.Stat(backups[i])
		infoJ, _ := os.Stat(backups[j])
		return infoI.ModTime().After(infoJ.ModTime())
	})

	// Remove old backups beyond keepCount
	for i := keepCount; i < len(backups); i++ {
		os.Remove(backups[i])
	}

	return nil
}

// ListBackups returns a list of available backup versions
func ListBackups(exePath string) ([]string, error) {
	dir := filepath.Dir(exePath)
	base := filepath.Base(exePath)
	pattern := filepath.Join(dir, base+".backup.*")
	return filepath.Glob(pattern)
}

// RestoreBackup restores a backup file to the executable path
func RestoreBackup(exePath, backupPath string) error {
	info, err := os.Stat(exePath)
	if err != nil {
		return err
	}
	fileMode := info.Mode()

	if err := copyFile(backupPath, exePath); err != nil {
		return err
	}

	return os.Chmod(exePath, fileMode)
}
