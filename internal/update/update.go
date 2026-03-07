package update

import (
	"time"
)

// InstallMethod represents how the CLI was installed
type InstallMethod int

const (
	InstallManual InstallMethod = iota
	InstallHomebrew
	InstallApt
	InstallYum
	InstallGoInstall
)

// String returns the human-readable name of the install method
func (m InstallMethod) String() string {
	switch m {
	case InstallManual:
		return "manual"
	case InstallHomebrew:
		return "Homebrew"
	case InstallApt:
		return "apt"
	case InstallYum:
		return "yum"
	case InstallGoInstall:
		return "go install"
	default:
		return "unknown"
	}
}

// Asset represents a downloadable release asset
type Asset struct {
	Name        string `json:"name"`
	DownloadURL string `json:"browser_download_url"`
	Size        int64  `json:"size"`
	Checksum    string `json:"checksum,omitempty"`
}

// ReleaseInfo contains information about a software release
type ReleaseInfo struct {
	Version    string   `json:"tag_name"`
	Name       string   `json:"name"`
	Changelog  string   `json:"body"`
	Assets     []Asset  `json:"assets"`
	Prerelease bool     `json:"prerelease"`
	PublishedAt string  `json:"published_at"`
}

// UpdateConfig stores user preferences for update checking
type UpdateConfig struct {
	AutoCheck     bool      `json:"auto_check"`
	Interval      int       `json:"interval"`        // hours between checks
	LastCheckTime time.Time `json:"last_check_time"`
	SkipVersion   string    `json:"skip_version,omitempty"`
	Prerelease    bool      `json:"prerelease"`
}

// CheckResult contains the result of an update check
type CheckResult struct {
	UpdateAvailable bool
	CurrentVersion  string
	LatestVersion   string
	Release         *ReleaseInfo
	InstallMethod   InstallMethod
	CanSelfUpdate   bool
}

// DefaultConfig returns the default update configuration
func DefaultConfig() *UpdateConfig {
	return &UpdateConfig{
		AutoCheck:     false,
		Interval:      24, // 24 hours
		LastCheckTime: time.Time{},
		SkipVersion:   "",
		Prerelease:    false,
	}
}
