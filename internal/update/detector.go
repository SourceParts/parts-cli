package update

import (
	"os"
	"path/filepath"
	"strings"
)

// DetectInstallMethod determines how the CLI was installed
func DetectInstallMethod() (InstallMethod, error) {
	exePath, err := os.Executable()
	if err != nil {
		return InstallManual, err
	}

	// Resolve symlinks to get the real path
	realPath, err := filepath.EvalSymlinks(exePath)
	if err != nil {
		// If we can't resolve symlinks, use the original path
		realPath = exePath
	}

	// Check for Homebrew
	if strings.Contains(realPath, "/homebrew/") ||
		strings.Contains(realPath, "/linuxbrew/") ||
		strings.Contains(realPath, "Cellar/parts") {
		return InstallHomebrew, nil
	}

	// Check for go install (in GOPATH/bin or GOBIN)
	gopath := os.Getenv("GOPATH")
	gobin := os.Getenv("GOBIN")
	if gopath != "" && strings.HasPrefix(realPath, filepath.Join(gopath, "bin")) {
		return InstallGoInstall, nil
	}
	if gobin != "" && strings.HasPrefix(realPath, gobin) {
		return InstallGoInstall, nil
	}

	// Check for apt (Debian/Ubuntu)
	if fileExists("/var/lib/dpkg/info/parts-cli.list") {
		return InstallApt, nil
	}

	// Check for yum/dnf (Red Hat/Fedora/CentOS)
	if (strings.HasPrefix(realPath, "/usr/bin") || strings.HasPrefix(realPath, "/usr/local/bin")) &&
		fileExists("/var/lib/rpm") {
		return InstallYum, nil
	}

	// Default to manual install
	return InstallManual, nil
}

// CanSelfUpdate returns true if the CLI can update itself
func CanSelfUpdate(method InstallMethod) bool {
	return method == InstallManual
}

// GetPackageManagerCommand returns the appropriate update command for the install method
func GetPackageManagerCommand(method InstallMethod) string {
	switch method {
	case InstallHomebrew:
		return "brew upgrade parts-cli"
	case InstallApt:
		return "sudo apt update && sudo apt upgrade parts-cli"
	case InstallYum:
		return "sudo yum update parts-cli"
	case InstallGoInstall:
		return "go install github.com/SourceParts/parts-cli/cmd/parts@latest"
	default:
		return ""
	}
}

// fileExists checks if a file exists
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
