package update

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/domain"
)

// SemVer represents a semantic version
type SemVer struct {
	Major      int
	Minor      int
	Patch      int
	Prerelease string
	Build      string
}

// ParseSemVer parses a semantic version string (e.g., "v1.2.3-beta.1+build")
func ParseSemVer(version string) (*SemVer, error) {
	// Remove leading 'v' if present
	version = strings.TrimPrefix(version, "v")

	// Split build metadata
	parts := strings.SplitN(version, "+", 2)
	var build string
	if len(parts) == 2 {
		build = parts[1]
	}
	version = parts[0]

	// Split prerelease
	parts = strings.SplitN(version, "-", 2)
	var prerelease string
	if len(parts) == 2 {
		prerelease = parts[1]
	}
	version = parts[0]

	// Parse major.minor.patch
	versionParts := strings.Split(version, ".")
	if len(versionParts) < 2 {
		return nil, fmt.Errorf("invalid version format: %s", version)
	}

	major, err := strconv.Atoi(versionParts[0])
	if err != nil {
		return nil, fmt.Errorf("invalid major version: %w", err)
	}

	minor, err := strconv.Atoi(versionParts[1])
	if err != nil {
		return nil, fmt.Errorf("invalid minor version: %w", err)
	}

	patch := 0
	if len(versionParts) >= 3 {
		patch, err = strconv.Atoi(versionParts[2])
		if err != nil {
			return nil, fmt.Errorf("invalid patch version: %w", err)
		}
	}

	return &SemVer{
		Major:      major,
		Minor:      minor,
		Patch:      patch,
		Prerelease: prerelease,
		Build:      build,
	}, nil
}

// Compare compares two semantic versions
// Returns: -1 if this < other, 0 if equal, 1 if this > other
func (v *SemVer) Compare(other *SemVer) int {
	if v.Major != other.Major {
		if v.Major < other.Major {
			return -1
		}
		return 1
	}
	if v.Minor != other.Minor {
		if v.Minor < other.Minor {
			return -1
		}
		return 1
	}
	if v.Patch != other.Patch {
		if v.Patch < other.Patch {
			return -1
		}
		return 1
	}

	// Prerelease comparison: version without prerelease > version with prerelease
	if v.Prerelease == "" && other.Prerelease != "" {
		return 1
	}
	if v.Prerelease != "" && other.Prerelease == "" {
		return -1
	}
	if v.Prerelease != other.Prerelease {
		return strings.Compare(v.Prerelease, other.Prerelease)
	}

	return 0
}

// IsNewer returns true if this version is newer than the other
func (v *SemVer) IsNewer(other *SemVer) bool {
	return v.Compare(other) > 0
}

// String returns the version as a string
func (v *SemVer) String() string {
	s := fmt.Sprintf("%d.%d.%d", v.Major, v.Minor, v.Patch)
	if v.Prerelease != "" {
		s += "-" + v.Prerelease
	}
	if v.Build != "" {
		s += "+" + v.Build
	}
	return s
}

// CheckForUpdate checks if a new version is available
func CheckForUpdate(ctx context.Context, currentVersion string, client *http.Client) (*CheckResult, error) {
	// Detect installation method
	installMethod, err := DetectInstallMethod()
	if err != nil {
		return nil, fmt.Errorf("failed to detect install method: %w", err)
	}

	// Parse current version
	current, err := ParseSemVer(currentVersion)
	if err != nil {
		return nil, fmt.Errorf("failed to parse current version: %w", err)
	}

	// Try Source Parts API first
	release, err := fetchFromSourcePartsAPI(ctx, client)
	if err != nil {
		// Fallback to GitHub Releases API
		release, err = fetchFromGitHubAPI(ctx, client)
		if err != nil {
			return nil, fmt.Errorf("failed to check for updates: %w", err)
		}
	}

	// Parse latest version
	latest, err := ParseSemVer(release.Version)
	if err != nil {
		return nil, fmt.Errorf("failed to parse latest version: %w", err)
	}

	return &CheckResult{
		UpdateAvailable: latest.IsNewer(current),
		CurrentVersion:  currentVersion,
		LatestVersion:   release.Version,
		Release:         release,
		InstallMethod:   installMethod,
		CanSelfUpdate:   CanSelfUpdate(installMethod),
	}, nil
}

// fetchFromSourcePartsAPI fetches release info from Source Parts API
func fetchFromSourcePartsAPI(ctx context.Context, client *http.Client) (*ReleaseInfo, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", domain.Endpoint_CLIUpdate, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d", resp.StatusCode)
	}

	var release ReleaseInfo
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &release, nil
}

// fetchFromGitHubAPI fetches release info from GitHub Releases API
func fetchFromGitHubAPI(ctx context.Context, client *http.Client) (*ReleaseInfo, error) {
	const githubAPI = "https://api.github.com/repos/SourceParts/parts-cli/releases/latest"

	req, err := http.NewRequestWithContext(ctx, "GET", githubAPI, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "parts-cli/"+domain.Version)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API returned status %d", resp.StatusCode)
	}

	var release ReleaseInfo
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &release, nil
}

// FindAssetForPlatform finds the appropriate asset for the current platform
func FindAssetForPlatform(assets []Asset) *Asset {
	goos := runtime.GOOS
	goarch := runtime.GOARCH

	// Normalize arch names (amd64 vs x86_64)
	archVariants := []string{goarch}
	if goarch == "amd64" {
		archVariants = append(archVariants, "x86_64")
	} else if goarch == "arm64" {
		archVariants = append(archVariants, "aarch64")
	}

	// Look for matching asset
	for _, asset := range assets {
		name := strings.ToLower(asset.Name)

		// Check if asset matches OS
		if !strings.Contains(name, goos) {
			continue
		}

		// Check if asset matches architecture
		matchesArch := false
		for _, arch := range archVariants {
			if strings.Contains(name, arch) {
				matchesArch = true
				break
			}
		}
		if !matchesArch {
			continue
		}

		// Prefer tar.gz archives
		if strings.HasSuffix(name, ".tar.gz") {
			return &asset
		}
	}

	return nil
}

// ShouldCheck returns true if enough time has elapsed since the last check
func ShouldCheck(config *UpdateConfig) bool {
	if !config.AutoCheck {
		return false
	}

	if config.LastCheckTime.IsZero() {
		return true
	}

	elapsed := time.Since(config.LastCheckTime)
	interval := time.Duration(config.Interval) * time.Hour

	return elapsed >= interval
}
