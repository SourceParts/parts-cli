// Package ghcli wraps the GitHub CLI (gh) for issue operations.
// All functions check that gh is installed and authenticated before
// executing. If gh is not available, ErrGHNotAvailable is returned.
package ghcli

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ErrGHNotAvailable is returned when the gh CLI is not installed.
var ErrGHNotAvailable = errors.New("gh CLI is not installed. Install it: brew install gh (macOS), https://cli.github.com (Linux/Windows)")

// ErrGHNotAuthenticated is returned when gh is installed but not logged in.
var ErrGHNotAuthenticated = errors.New("gh is not authenticated. Run: gh auth login")

const execTimeout = 30 * time.Second

// Available returns true if the gh binary is in PATH.
func Available() bool {
	_, err := exec.LookPath("gh")
	return err == nil
}

// Authenticated checks if gh is logged in. Returns (ok, username, error).
func Authenticated() (bool, string, error) {
	if !Available() {
		return false, "", ErrGHNotAvailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "gh", "auth", "status").CombinedOutput()
	if err != nil {
		return false, "", nil
	}
	// Parse "Logged in to github.com account <user>" from output
	user := ""
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, "account") {
			parts := strings.Fields(line)
			for i, w := range parts {
				if w == "account" && i+1 < len(parts) {
					user = strings.TrimRight(parts[i+1], "()")
					break
				}
			}
		}
	}
	return true, user, nil
}

// RepoFromLocal detects the current repo via gh repo view.
func RepoFromLocal() (string, error) {
	if !Available() {
		return "", ErrGHNotAvailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").Output()
	if err != nil {
		return "", fmt.Errorf("failed to detect repo: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

// CreateIssue creates a new GitHub Issue. Returns (number, url, error).
func CreateIssue(repo, title, body string, labels []string, milestone string) (int, string, error) {
	if !Available() {
		return 0, "", ErrGHNotAvailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()

	args := []string{"issue", "create", "--repo", repo, "--title", title, "--body", body}
	for _, l := range labels {
		args = append(args, "--label", l)
	}
	if milestone != "" {
		args = append(args, "--milestone", milestone)
	}

	out, err := exec.CommandContext(ctx, "gh", args...).CombinedOutput()
	if err != nil {
		return 0, "", fmt.Errorf("gh issue create failed: %s\n%s", err, string(out))
	}

	url := strings.TrimSpace(string(out))
	num := parseIssueNumber(url)
	return num, url, nil
}

type issueJSON struct {
	Number int    `json:"number"`
	Title  string `json:"title"`
	URL    string `json:"url"`
}

// FindIssueByTitle searches for an open issue matching a title pattern.
// Returns (number, url, error). Returns (0, "", nil) if not found.
func FindIssueByTitle(repo, titlePattern string, labels []string) (int, string, error) {
	if !Available() {
		return 0, "", ErrGHNotAvailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()

	args := []string{"issue", "list", "--repo", repo, "--search", titlePattern, "--json", "number,title,url", "--limit", "10"}
	for _, l := range labels {
		args = append(args, "--label", l)
	}

	out, err := exec.CommandContext(ctx, "gh", args...).Output()
	if err != nil {
		return 0, "", fmt.Errorf("gh issue list failed: %w", err)
	}

	var issues []issueJSON
	if err := json.Unmarshal(out, &issues); err != nil {
		return 0, "", fmt.Errorf("failed to parse issue list: %w", err)
	}

	// Find exact match by title pattern (e.g. "[ECN-046]")
	for _, iss := range issues {
		if strings.Contains(iss.Title, titlePattern) {
			return iss.Number, iss.URL, nil
		}
	}
	return 0, "", nil
}

// UpdateIssue updates an existing issue's body and labels.
func UpdateIssue(repo string, num int, body string, labels []string) (string, error) {
	if !Available() {
		return "", ErrGHNotAvailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()

	args := []string{"issue", "edit", strconv.Itoa(num), "--repo", repo, "--body", body}
	for _, l := range labels {
		args = append(args, "--add-label", l)
	}

	out, err := exec.CommandContext(ctx, "gh", args...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("gh issue edit failed: %s\n%s", err, string(out))
	}
	return strings.TrimSpace(string(out)), nil
}

// AddComment adds a comment to an existing issue.
func AddComment(repo string, num int, comment string) error {
	if !Available() {
		return ErrGHNotAvailable
	}
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()

	args := []string{"issue", "comment", strconv.Itoa(num), "--repo", repo, "--body", comment}
	out, err := exec.CommandContext(ctx, "gh", args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("gh issue comment failed: %s\n%s", err, string(out))
	}
	return nil
}

var issueNumRe = regexp.MustCompile(`/issues/(\d+)`)

func parseIssueNumber(url string) int {
	m := issueNumRe.FindStringSubmatch(url)
	if len(m) < 2 {
		return 0
	}
	n, _ := strconv.Atoi(m[1])
	return n
}
