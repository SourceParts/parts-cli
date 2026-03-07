package update

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/schollz/progressbar/v3"
)

// DownloadAndInstall downloads and installs a new version of the CLI
func DownloadAndInstall(ctx context.Context, asset *Asset, currentVersion string, client *http.Client) error {
	// Get current executable path
	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get executable path: %w", err)
	}

	// Resolve symlinks to get the real path
	realPath, err := filepath.EvalSymlinks(exePath)
	if err != nil {
		realPath = exePath
	}

	// Get current file permissions
	info, err := os.Stat(realPath)
	if err != nil {
		return fmt.Errorf("failed to stat executable: %w", err)
	}
	fileMode := info.Mode()

	// Create temp file for download
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

	// Extract binary from archive
	binaryPath, err := extractBinary(tmpPath)
	if err != nil {
		return fmt.Errorf("failed to extract binary: %w", err)
	}
	defer os.Remove(binaryPath)

	// Create versioned backup
	backupPath := realPath + ".backup." + currentVersion
	if err := copyFile(realPath, backupPath); err != nil {
		return fmt.Errorf("failed to create backup: %w", err)
	}
	// DON'T defer os.Remove(backupPath) - keep it for rollback

	// Copy new binary to final location
	if err := copyFile(binaryPath, realPath); err != nil {
		// Rollback: restore from backup
		if restoreErr := copyFile(backupPath, realPath); restoreErr != nil {
			return fmt.Errorf("failed to install update and rollback failed: %w (rollback error: %v)", err, restoreErr)
		}
		return fmt.Errorf("failed to install update (rolled back): %w", err)
	}

	// Restore permissions
	if err := os.Chmod(realPath, fileMode); err != nil {
		return fmt.Errorf("failed to restore permissions: %w", err)
	}

	// After success, clean up old backups (keep last 3)
	cleanupOldBackups(realPath, 3)

	return nil
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
