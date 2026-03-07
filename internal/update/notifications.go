package update

import (
	"fmt"

	"github.com/gen2brain/beeep"
)

// NotifyUpdateAvailable sends a desktop notification for available update
func NotifyUpdateAvailable(currentVersion, latestVersion string) error {
	title := "Parts CLI Update Available"
	message := fmt.Sprintf("Version %s is available (you have %s)", latestVersion, currentVersion)
	return beeep.Notify(title, message, "")
}

// NotifyUpdateSuccess sends a desktop notification for successful update
func NotifyUpdateSuccess(version string) error {
	title := "Parts CLI Updated"
	message := fmt.Sprintf("Successfully updated to version %s", version)
	return beeep.Notify(title, message, "")
}

// NotifyUpdateFailed sends a desktop notification for failed update
func NotifyUpdateFailed(err error) error {
	title := "Parts CLI Update Failed"
	message := fmt.Sprintf("Update failed: %v", err)
	return beeep.Alert(title, message, "")
}

// NotifyRollbackSuccess sends a desktop notification for successful rollback
func NotifyRollbackSuccess(version string) error {
	title := "Parts CLI Rolled Back"
	message := fmt.Sprintf("Successfully rolled back to version %s", version)
	return beeep.Notify(title, message, "")
}
