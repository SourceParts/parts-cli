package commands

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/ghcli"
	"github.com/spf13/cobra"
)

var projectSync = &cobra.Command{
	Use:   "sync",
	Short: "Sync project state with remote repository",
	Long: `Check the remote repository for changes and update the local project config.

Detects if other team members or the client made modifications from another
terminal. Updates .parts/config.yaml with the latest remote SHA and sync
timestamp.

Uses the local 'gh' CLI for GitHub API access — no API keys needed.`,
	Example: `  parts project sync
  parts project sync --save
  parts project sync --pull
  parts project sync --json`,
	RunE: runProjectSync,
}

func init() {
	projectSync.Flags().Bool("save", false, "Save detected repo to .parts/config.yaml")
	projectSync.Flags().Bool("pull", false, "Run git pull if behind remote")
	projectSync.Flags().Bool("json", false, "Output as JSON")

	Project.AddCommand(projectSync)
}

type syncResult struct {
	Repo          string         `json:"repo"`
	Branch        string         `json:"branch"`
	LocalSHA      string         `json:"local_sha"`
	RemoteSHA     string         `json:"remote_sha"`
	Status        string         `json:"status"` // up-to-date, behind, ahead, diverged
	Behind        int            `json:"behind"`
	Ahead         int            `json:"ahead"`
	BehindCommits []syncCommit   `json:"behind_commits,omitempty"`
	LastSynced    string         `json:"last_synced"`
	Pulled        bool           `json:"pulled,omitempty"`
}

type syncCommit struct {
	SHA     string `json:"sha"`
	Message string `json:"message"`
	Author  string `json:"author"`
	Date    string `json:"date"`
}

func runProjectSync(cmd *cobra.Command, args []string) error {
	if !ghcli.Available() {
		return ghcli.ErrGHNotAvailable
	}

	authed, user, err := ghcli.Authenticated()
	if err != nil {
		return err
	}
	if !authed {
		return ghcli.ErrGHNotAuthenticated
	}

	save, _ := cmd.Flags().GetBool("save")
	pull, _ := cmd.Flags().GetBool("pull")
	jsonOut, _ := cmd.Flags().GetBool("json")

	cwd, _ := os.Getwd()
	cfg := ghcli.ReadPartsConfig(cwd)

	repo := ""
	branch := "main"
	if cfg != nil {
		repo = cfg.Repo
		if cfg.DefaultBranch != "" {
			branch = cfg.DefaultBranch
		}
	}

	// Auto-detect repo if not in config
	if repo == "" {
		detected, err := ghcli.RepoFromLocal()
		if err == nil && detected != "" {
			repo = detected
			if save {
				ghcli.WritePartsConfigField(cwd, "repo", repo)
				if !jsonOut {
					fmt.Printf("  Saved repo to .parts/config.yaml: %s\n", repo)
				}
			}
		}
	}
	if repo == "" {
		return fmt.Errorf("no repo configured in .parts/config.yaml and could not auto-detect. Run with --save to save.")
	}

	// Get local SHA
	localSHA, err := gitRevParse("HEAD")
	if err != nil {
		return fmt.Errorf("not in a git repository: %w", err)
	}

	// Get remote SHA via gh api
	remoteSHA, err := ghAPIGetSHA(repo, branch)
	if err != nil {
		return fmt.Errorf("failed to fetch remote: %w", err)
	}

	// Determine status
	result := syncResult{
		Repo:      repo,
		Branch:    branch,
		LocalSHA:  short(localSHA),
		RemoteSHA: short(remoteSHA),
		LastSynced: time.Now().UTC().Format(time.RFC3339),
	}

	if localSHA == remoteSHA {
		result.Status = "up-to-date"
	} else {
		// Fetch to get accurate ahead/behind
		_ = gitFetch()

		ahead, behind := gitAheadBehind(branch)
		result.Ahead = ahead
		result.Behind = behind

		if behind > 0 && ahead > 0 {
			result.Status = "diverged"
		} else if behind > 0 {
			result.Status = "behind"
		} else if ahead > 0 {
			result.Status = "ahead"
		} else {
			result.Status = "up-to-date"
		}

		// Get behind commits
		if behind > 0 {
			result.BehindCommits = gitBehindCommits(branch, behind)
		}
	}

	// Update local sync state (.parts/sync.json — gitignored)
	ghcli.WriteSyncState(cwd, &ghcli.SyncState{
		LastSynced:    result.LastSynced,
		LastRemoteSHA: remoteSHA,
	})

	// Output
	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(result)
	}

	fmt.Printf("Project Sync\n")
	fmt.Printf("  Authenticated: %s\n", user)
	fmt.Printf("  Repository:    %s\n", repo)
	fmt.Printf("  Branch:        %s\n", branch)
	fmt.Printf("  Local:         %s\n", result.LocalSHA)
	fmt.Printf("  Remote:        %s\n", result.RemoteSHA)
	fmt.Printf("  Status:        %s", result.Status)
	if result.Behind > 0 {
		fmt.Printf(" (%d behind)", result.Behind)
	}
	if result.Ahead > 0 {
		fmt.Printf(" (%d ahead)", result.Ahead)
	}
	fmt.Println()

	if len(result.BehindCommits) > 0 {
		fmt.Println()
		fmt.Println("  Remote commits not yet pulled:")
		for _, c := range result.BehindCommits {
			fmt.Printf("    %s %s (%s)\n", c.SHA, c.Message, c.Author)
		}
	}

	if pull && result.Behind > 0 {
		fmt.Println()
		fmt.Println("  Pulling...")
		if err := gitPull(); err != nil {
			return fmt.Errorf("git pull failed: %w", err)
		}
		result.Pulled = true
		fmt.Println("  Pulled successfully.")
	} else if result.Behind > 0 && !pull {
		fmt.Printf("\n  Run 'parts project sync --pull' to pull remote changes.\n")
	}

	fmt.Printf("\n  Config updated: last_synced = %s\n", result.LastSynced)
	return nil
}

func gitRevParse(ref string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "git", "rev-parse", ref).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func ghAPIGetSHA(repo, branch string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "gh", "api", fmt.Sprintf("repos/%s/commits/%s", repo, branch), "--jq", ".sha").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func gitFetch() error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "git", "fetch", "origin").Run()
}

func gitAheadBehind(branch string) (ahead, behind int) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "git", "rev-list", "--left-right", "--count", fmt.Sprintf("HEAD...origin/%s", branch)).Output()
	if err != nil {
		return 0, 0
	}
	parts := strings.Fields(strings.TrimSpace(string(out)))
	if len(parts) == 2 {
		fmt.Sscanf(parts[0], "%d", &ahead)
		fmt.Sscanf(parts[1], "%d", &behind)
	}
	return
}

func gitBehindCommits(branch string, limit int) []syncCommit {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	format := "--format=%H\t%s\t%an\t%ai"
	out, err := exec.CommandContext(ctx, "git", "log", format, fmt.Sprintf("HEAD..origin/%s", branch), fmt.Sprintf("-%d", limit)).Output()
	if err != nil {
		return nil
	}
	var commits []syncCommit
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 4)
		if len(parts) < 4 {
			continue
		}
		commits = append(commits, syncCommit{
			SHA:     short(parts[0]),
			Message: parts[1],
			Author:  parts[2],
			Date:    parts[3],
		})
	}
	return commits
}

func gitPull() error {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", "pull", "origin")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func short(sha string) string {
	if len(sha) > 7 {
		return sha[:7]
	}
	return sha
}
