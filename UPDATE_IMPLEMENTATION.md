# Auto-Update Mechanism Implementation

## Summary

Successfully implemented a comprehensive self-update system for the parts-cli that:

- ✅ Respects installation methods (Homebrew, apt, yum, go install, manual)
- ✅ Dual update sources (Source Parts API with GitHub Releases fallback)
- ✅ Safe and atomic binary replacement with rollback capability
- ✅ User-friendly commands with confirmation prompts
- ✅ Optional startup checks (opt-in, configurable interval)
- ✅ Secure configuration storage via system keychain

## Files Created

1. **internal/update/update.go** - Core types and constants
2. **internal/update/detector.go** - Installation method detection
3. **internal/update/checker.go** - Version checking and comparison
4. **internal/update/installer.go** - Binary download and installation
5. **internal/commands/update.go** - Command definitions

## Files Modified

1. **internal/client/keychain.go** - Added update config storage functions
2. **internal/domain/definitions.go** - Added Endpoint_CLIUpdate constant
3. **cmd/parts/main.go** - Registered Update command and added startup check
4. **internal/commands/commands.go** - Fixed duplicate Stackup declaration

## Commands Available

```bash
parts update              # Show help
parts update check        # Check for available updates
parts update apply        # Download and install update
parts update config       # Configure auto-check settings
parts update status       # Show version and config info
```

## Configuration Options

```bash
parts update config --auto-check=true   # Enable startup checks
parts update config --interval=24       # Check every 24 hours
parts update config --prerelease=false  # Exclude prerelease versions
```

## Testing Results

✅ Build successful (15MB binary)
✅ Help output displays correctly
✅ Status command shows version and install method
✅ Config command saves/loads from keychain
✅ Check command connects to GitHub API and displays updates
✅ Startup notification works when auto-check enabled

## Example Output

```
$ parts update status
Version:          0.1.0
Install method:   manual
Self-update:      true
Auto-check:       true
Check interval:   12 hours

$ parts update check
Current version: 0.1.0
Install method:  manual

Checking for updates...
📦 Update available: 0.1.0 → v0.2.0

What's new:
  ## Changelog
  * Refactor API types to internal/api package
  * Add MSI installer workflow for Windows
  * Add GitHub integration commands
  ...

To install this update, run:
  parts update apply
```

## Security Features

- HTTPS-only downloads
- SHA256 checksum verification (when available in release metadata)
- Atomic binary replacement with backup/rollback
- Permission preservation across updates
- No arbitrary code execution (only replaces binary)

## Next Steps

The API endpoint `Endpoint_CLIUpdate` (api.source.parts/v1/cli/update/latest) needs to be implemented on the API side. Until then, the system will use GitHub Releases API as the fallback source.

Expected API response format:
```json
{
  "tag_name": "v0.2.0",
  "name": "Version 0.2.0",
  "body": "Changelog text...",
  "prerelease": false,
  "published_at": "2024-01-01T00:00:00Z",
  "assets": [
    {
      "name": "parts-cli_v0.2.0_linux_amd64.tar.gz",
      "browser_download_url": "https://...",
      "size": 8867328,
      "checksum": "sha256:abc123..."
    }
  ]
}
```
