package commands

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/SourceParts/parts-cli/internal/auth"
	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/ghcli"
	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/spf13/cobra"
)

// Valid report types accepted by the notify/report endpoint
var validReportTypes = map[string]bool{
	"ecn":               true,
	"schematic_review":  true,
	"dfm":               true,
	"dvt":               true,
	"dfm_review":        true,
	"dvt_scan":          true,
	"stackup_diff":      true,
	"rtm":               true,
}

// Valid SOP types accepted by the notify/sop endpoint
var validSOPTypes = map[string]bool{
	"assembly": true,
	"testing":  true,
}

// Github is the parent command for GitHub Actions integration
var Github = &cobra.Command{
	Use:   "github",
	Short: "GitHub Actions integration commands",
	Long: `Commands designed for use in GitHub Actions workflows.

These commands communicate with the Source Parts webhook endpoints
using a GitHub API key (not the same as your parts auth token).

Set the API key via:
  - PARTS_GITHUB_API_KEY environment variable
  - GITHUB_API_KEY environment variable
  - --api-key flag`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cmd.Help()
	},
	Example: domain.BinaryName + ` github report --type ecn --file ECN_Log_V1.0.md -p "My Board" -c "John" -e "john@example.com"
` + domain.BinaryName + ` github commit -p "My Board" -c "John" -e "john@example.com" -s dfm`,
}

// githubReport sends a report notification with PDF generation
var githubReport = &cobra.Command{
	Use:   "report",
	Short: "Send a report notification with PDF generation",
	Long: `Send a report notification to the Source Parts webhook endpoint.

Reads a markdown file, extracts metadata, and sends it for PDF generation
and email delivery. Supports ECN logs, schematic reviews, DFM reports, and more.

The API key is resolved in order:
  1. --api-key flag
  2. PARTS_GITHUB_API_KEY env var
  3. GITHUB_API_KEY env var`,
	Example: domain.BinaryName + ` github report \
  --type ecn \
  --file Reports/ECN_Log_V1.0.md \
  --project "nRF54H20 Main Board" \
  --client "Zach Eisenhauer" \
  --email "zacheisenhauer@gmail.com"`,
	RunE: runGithubReport,
}

// githubCommit sends a commit notification
var githubCommit = &cobra.Command{
	Use:   "commit",
	Short: "Send a commit notification email",
	Long: `Send a commit notification to the Source Parts DFM notify endpoint.

Automatically reads commit data from GitHub Actions environment variables
(COMMITS_JSON, GITHUB_REPOSITORY, GITHUB_REF_NAME, GITHUB_SHA).

For multi-commit pushes, set COMMITS_JSON to the GitHub event commits array.
For single commits, use --message and --sha flags or rely on env vars.`,
	Example: domain.BinaryName + ` github commit \
  --project "nRF54H20 Main Board" \
  --client "Zach Eisenhauer" \
  --email "zacheisenhauer@gmail.com" \
  --service dfm`,
	RunE: runGithubCommit,
}

// githubSOP sends an SOP notification with PDF generation
var githubSOP = &cobra.Command{
	Use:   "sop",
	Short: "Send an SOP notification with PDF generation",
	Long: `Send a Standard Operating Procedure notification to the Source Parts webhook.

Reads a markdown file, extracts metadata, and sends it for PDF generation
and email delivery. Currently supports assembly specifications.

The API key is resolved in order:
  1. --api-key flag
  2. PARTS_GITHUB_API_KEY env var
  3. GITHUB_API_KEY env var`,
	Example: domain.BinaryName + ` github sop \
  --type assembly \
  --file Reports/EVT2_Assembly_Spec.md \
  --project "nRF54H20 Main Board" \
  --client "Zach Eisenhauer" \
  --email "zacheisenhauer@gmail.com"`,
	RunE: runGithubSOP,
}

// githubIssue creates or updates a GitHub Issue from an ECN file
var githubIssue = &cobra.Command{
	Use:   "issue",
	Short: "Create or update a GitHub Issue from an ECN file",
	Long: `Create or update a GitHub Issue on the project repository from an ECN
markdown file. Uses the local 'gh' CLI for authentication — no API keys needed.

Reads YAML frontmatter from the ECN file to extract title, severity, status,
type, and other metadata. Labels are auto-generated from the frontmatter.

If --update is set and an issue with a matching ECN ID exists, it updates
that issue instead of creating a duplicate.

Requires: gh CLI installed and authenticated (gh auth login)`,
	Example: domain.BinaryName + ` github issue --file ECO/ECN-046.md --repo owner/repo
` + domain.BinaryName + ` github issue --file ECO/ECN-046.md --repo owner/repo --update
` + domain.BinaryName + ` github issue --file ECO/ECN-046.md --repo owner/repo --dry-run`,
	RunE: runGithubIssue,
}

func init() {
	// Report flags
	githubReport.Flags().StringP("type", "t", "", "Report type: ecn, schematic_review, dfm, dvt, dfm_review, dvt_scan, stackup_diff, rtm")
	githubReport.Flags().StringP("file", "f", "", "Path to markdown report file")
	githubReport.Flags().StringP("project", "p", "", "Project name")
	githubReport.Flags().StringP("client", "c", "", "Client full name")
	githubReport.Flags().StringP("email", "e", "", "Client email address")
	githubReport.Flags().String("cc", "", "CC email address")
	githubReport.Flags().String("bcc", "", "BCC email address")
	githubReport.Flags().StringP("api-key", "k", "", "API key (overrides env var)")
	githubReport.Flags().String("version", "", "File version (auto-extracted from filename if omitted)")
	githubReport.Flags().String("repository", "", "Repository name (default: GITHUB_REPOSITORY env or \"unknown\")")
	githubReport.Flags().String("branch", "", "Branch name (default: GITHUB_REF_NAME env or \"main\")")
	githubReport.Flags().StringP("summary", "s", "", "Engineer's notes / summary text")
	githubReport.Flags().String("thread-id", "", "Thread ID for email conversation threading")

	_ = githubReport.MarkFlagRequired("type")
	_ = githubReport.MarkFlagRequired("file")
	_ = githubReport.MarkFlagRequired("project")
	_ = githubReport.MarkFlagRequired("client")
	_ = githubReport.MarkFlagRequired("email")

	// Commit flags
	githubCommit.Flags().StringP("project", "p", "", "Project name")
	githubCommit.Flags().StringP("client", "c", "", "Client full name")
	githubCommit.Flags().StringP("email", "e", "", "Client email address")
	githubCommit.Flags().String("cc", "", "CC email address")
	githubCommit.Flags().String("bcc", "", "BCC email addresses (comma-separated)")
	githubCommit.Flags().StringP("service", "s", "", "Service type (e.g. dfm)")
	githubCommit.Flags().StringP("api-key", "k", "", "API key (overrides env var)")
	githubCommit.Flags().StringP("message", "m", "", "Single commit message (fallback if no COMMITS_JSON)")
	githubCommit.Flags().String("sha", "", "Single commit SHA")
	githubCommit.Flags().String("url", "", "Single commit URL")
	githubCommit.Flags().String("author", "", "Commit author name")

	_ = githubCommit.MarkFlagRequired("project")
	_ = githubCommit.MarkFlagRequired("client")
	_ = githubCommit.MarkFlagRequired("email")
	_ = githubCommit.MarkFlagRequired("service")

	// SOP flags
	githubSOP.Flags().StringP("type", "t", "assembly", "SOP type: assembly, testing")
	githubSOP.Flags().StringP("file", "f", "", "Path to markdown SOP file")
	githubSOP.Flags().StringP("project", "p", "", "Project name")
	githubSOP.Flags().StringP("client", "c", "", "Client full name")
	githubSOP.Flags().StringP("email", "e", "", "Client email address")
	githubSOP.Flags().String("cc", "", "CC email address")
	githubSOP.Flags().String("bcc", "", "BCC email addresses (comma-separated)")
	githubSOP.Flags().StringP("api-key", "k", "", "API key (overrides env var)")
	githubSOP.Flags().String("thread-id", "", "Email thread identifier for conversation threading")
	githubSOP.Flags().String("version", "", "File version (auto-extracted from filename if omitted)")
	githubSOP.Flags().String("repository", "", "Repository name (default: GITHUB_REPOSITORY env or \"unknown\")")
	githubSOP.Flags().String("branch", "", "Branch name (default: GITHUB_REF_NAME env or \"main\")")
	githubSOP.Flags().StringP("summary", "s", "", "Engineer's notes / summary text")

	_ = githubSOP.MarkFlagRequired("file")
	_ = githubSOP.MarkFlagRequired("project")
	_ = githubSOP.MarkFlagRequired("client")
	_ = githubSOP.MarkFlagRequired("email")

	// Issue flags
	githubIssue.Flags().StringP("file", "f", "", "Path to ECN markdown file")
	githubIssue.Flags().StringP("repo", "r", "", "Target GitHub repository (owner/repo). Auto-detects from GITHUB_REPOSITORY or local gh repo.")
	githubIssue.Flags().Bool("update", false, "Update existing issue if found by ECN ID")
	githubIssue.Flags().Bool("dry-run", false, "Print what would be done without creating/updating")
	githubIssue.Flags().String("milestone", "", "Assign to milestone (by name)")
	githubIssue.Flags().StringSlice("extra-labels", nil, "Additional labels beyond auto-generated ones")
	githubIssue.Flags().Bool("comment", false, "Add update as comment instead of replacing body")

	_ = githubIssue.MarkFlagRequired("file")

	Github.AddCommand(githubReport)
	Github.AddCommand(githubCommit)
	Github.AddCommand(githubSOP)
	Github.AddCommand(githubIssue)
}

// resolveAPIKey resolves the GitHub API key from flag, then env vars.
// The resolved value is passed through auth.CleanCredential so quoted /
// newline-padded values copied straight from .env files still match the
// server-side comparison byte-for-byte.
func resolveAPIKey(cmd *cobra.Command) (string, error) {
	key, _ := cmd.Flags().GetString("api-key")
	if key != "" {
		return auth.CleanCredential(key), nil
	}
	if key = os.Getenv("PARTS_GITHUB_API_KEY"); key != "" {
		return auth.CleanCredential(key), nil
	}
	if key = os.Getenv("GITHUB_API_KEY"); key != "" {
		return auth.CleanCredential(key), nil
	}
	return "", fmt.Errorf("no API key found. Set --api-key, PARTS_GITHUB_API_KEY, or GITHUB_API_KEY")
}

// envOrDefault returns the env var value or the default
func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// extractVersion extracts a version string like "V1.0" from a filename
func extractVersion(filename string) string {
	re := regexp.MustCompile(`(?i)V(\d+\.\d+)`)
	m := re.FindStringSubmatch(filename)
	if len(m) >= 2 {
		return "V" + m[1]
	}
	return ""
}

// extractIssuesCount extracts issue counts based on report type
func extractIssuesCount(reportType, content string) int {
	switch reportType {
	case "ecn":
		// Look for summary statistics table: | **Total** | **17** |
		re := regexp.MustCompile(`\|\s*\*\*Total\*\*\s*\|\s*\*\*(\d+)\*\*`)
		m := re.FindStringSubmatch(content)
		if len(m) >= 2 {
			n, err := strconv.Atoi(m[1])
			if err == nil {
				return n
			}
		}
		// Fallback: count ECN headers (### ECN-NNN: ...)
		ecnRe := regexp.MustCompile(`(?m)^### ECN-\d+:`)
		return len(ecnRe.FindAllString(content, -1))

	case "schematic_review":
		// Count ### SCH-NNN: headers
		schRe := regexp.MustCompile(`(?m)^### SCH-\d+:`)
		return len(schRe.FindAllString(content, -1))

	case "stackup_diff":
		// Count version sections (## V1 —, ## V2 —, etc.)
		versionRe := regexp.MustCompile(`(?m)^## V\d+\s*[—\-]`)
		return len(versionRe.FindAllString(content, -1))
	}

	return 0
}

// postWebhook sends a JSON payload to a webhook endpoint with the GitHub API key
func postWebhook(endpoint, apiKey string, payload interface{}) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-github-api-key", apiKey)
	req.Header.Set("User-Agent", "PARTS-CLI")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		var errResp struct {
			Error   string `json:"error"`
			Details string `json:"details"`
			Message string `json:"message"`
		}
		if json.Unmarshal(respBody, &errResp) == nil && errResp.Error != "" {
			msg := errResp.Error
			if errResp.Details != "" {
				msg += ": " + errResp.Details
			}
			return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, msg)
		}
		return nil, fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
	}

	return respBody, nil
}

func runGithubReport(cmd *cobra.Command, args []string) error {
	apiKey, err := resolveAPIKey(cmd)
	if err != nil {
		return err
	}

	reportType, _ := cmd.Flags().GetString("type")
	filePath, _ := cmd.Flags().GetString("file")
	project, _ := cmd.Flags().GetString("project")
	clientName, _ := cmd.Flags().GetString("client")
	email, _ := cmd.Flags().GetString("email")
	cc, _ := cmd.Flags().GetString("cc")
	bcc, _ := cmd.Flags().GetString("bcc")
	version, _ := cmd.Flags().GetString("version")
	repository, _ := cmd.Flags().GetString("repository")
	branch, _ := cmd.Flags().GetString("branch")
	summary, _ := cmd.Flags().GetString("summary")
	threadID, _ := cmd.Flags().GetString("thread-id")

	// Validate report type
	if !validReportTypes[reportType] {
		valid := make([]string, 0, len(validReportTypes))
		for k := range validReportTypes {
			valid = append(valid, k)
		}
		return fmt.Errorf("invalid report type %q. Valid types: %s", reportType, strings.Join(valid, ", "))
	}

	// Read markdown file
	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read report file: %w", err)
	}
	if len(strings.TrimSpace(string(content))) == 0 {
		return fmt.Errorf("report file is empty: %s", filePath)
	}

	// Try to extract ECN frontmatter for structured metadata
	// Don't fail on parse error — frontmatter is optional for non-ECN reports
	fm, _, _ := parseECNFrontmatter(string(content))

	// Resolve defaults
	fileName := filepath.Base(filePath)
	if version == "" {
		version = extractVersion(fileName)
	}
	if repository == "" {
		repository = envOrDefault("GITHUB_REPOSITORY", "unknown")
	}
	if branch == "" {
		branch = envOrDefault("GITHUB_REF_NAME", "main")
	}

	pipelineSource := "manual"
	if os.Getenv("CI") != "" || os.Getenv("GITHUB_ACTIONS") != "" {
		pipelineSource = "github_actions"
	}

	issuesCount := extractIssuesCount(reportType, string(content))

	payload := types.ReportNotifyRequest{
		ReportType:      reportType,
		Repository:      repository,
		Branch:          branch,
		CommitSha:       os.Getenv("GITHUB_SHA"),
		PipelineSource:  pipelineSource,
		PipelineID:      os.Getenv("GITHUB_RUN_ID"),
		PipelineURL:     os.Getenv("GITHUB_SERVER_URL") + "/" + repository + "/actions/runs/" + os.Getenv("GITHUB_RUN_ID"),
		Status:          "completed",
		FileVersion:     version,
		FilePath:        filePath,
		FileName:        fileName,
		ProjectName:     project,
		ClientEmail:     email,
		ClientCCEmail:   cc,
		ClientBCCEmail:  bcc,
		ClientName:      clientName,
		IssuesCount:     issuesCount,
		Summary:         summary,
		ThreadID:        threadID,
		MarkdownContent: string(content),
	}

	// Populate ECN frontmatter fields if parsed successfully
	if fm != nil {
		payload.ECNID = fm.ID
		payload.ECNTitle = fm.Title
		payload.ECNSeverity = fm.Severity
		payload.ECNStatus = fm.Status
		payload.ECNType = fm.Type
		payload.ECNDisposition = fm.Disposition
		payload.ECNAuthor = fm.Author
		payload.ECNUpdatedDate = fm.UpdatedDate
		if threadID == "" && fm.ThreadID != "" {
			payload.ThreadID = fm.ThreadID
		}
	}

	// Display info
	fmt.Printf("Sending %s report notification...\n", reportType)
	fmt.Printf("  Project:    %s\n", project)
	fmt.Printf("  Client:     %s <%s>\n", clientName, email)
	if cc != "" {
		fmt.Printf("  CC:         %s\n", cc)
	}
	if bcc != "" {
		fmt.Printf("  BCC:        %s\n", bcc)
	}
	fmt.Printf("  File:       %s\n", fileName)
	if version != "" {
		fmt.Printf("  Version:    %s\n", version)
	}
	fmt.Printf("  Repository: %s\n", repository)
	fmt.Printf("  Branch:     %s\n", branch)
	if issuesCount > 0 {
		fmt.Printf("  Issues:     %d\n", issuesCount)
	}
	fmt.Printf("  Source:     %s\n", pipelineSource)
	fmt.Println()

	respBody, err := postWebhook(domain.Endpoint_ReportNotify, apiKey, payload)
	if err != nil {
		return fmt.Errorf("failed to send report notification: %w", err)
	}

	var resp types.ReportNotifyResponse
	if err := json.Unmarshal(respBody, &resp); err != nil {
		// Non-JSON response, still succeeded
		fmt.Println("Report notification sent successfully!")
		return nil
	}

	if !resp.Success && resp.Error != "" {
		return fmt.Errorf("server error: %s", resp.Error)
	}

	fmt.Println("Report notification sent successfully!")
	if resp.PDFGenerated {
		fmt.Println("  PDF:        Generated")
	}
	if resp.EmailID != "" {
		fmt.Printf("  Email ID:   %s\n", resp.EmailID)
	}
	if len(resp.Recipients) > 0 {
		fmt.Printf("  Recipients: %s\n", strings.Join(resp.Recipients, ", "))
	}
	if resp.IsRevision {
		fmt.Printf("  Revision:   Updated from %s\n", resp.PreviousVersion)
	}

	return nil
}

func runGithubCommit(cmd *cobra.Command, args []string) error {
	apiKey, err := resolveAPIKey(cmd)
	if err != nil {
		return err
	}

	project, _ := cmd.Flags().GetString("project")
	clientName, _ := cmd.Flags().GetString("client")
	email, _ := cmd.Flags().GetString("email")
	cc, _ := cmd.Flags().GetString("cc")
	bcc, _ := cmd.Flags().GetString("bcc")
	service, _ := cmd.Flags().GetString("service")

	repository := envOrDefault("GITHUB_REPOSITORY", "unknown")
	branch := envOrDefault("GITHUB_REF_NAME", "main")

	// Try multi-commit from COMMITS_JSON first
	commitsJSON := os.Getenv("COMMITS_JSON")
	if commitsJSON != "" {
		var ghCommits []types.GitHubCommitJSON
		if err := json.Unmarshal([]byte(commitsJSON), &ghCommits); err != nil {
			return fmt.Errorf("failed to parse COMMITS_JSON: %w", err)
		}

		if len(ghCommits) > 0 {
			commits := make([]types.CommitInfo, len(ghCommits))
			for i, gc := range ghCommits {
				commits[i] = types.CommitInfo{
					SHA:         gc.ID,
					Message:     gc.Message,
					AuthorName:  gc.Author.Name,
					AuthorEmail: gc.Author.Email,
					URL:         gc.URL,
					Timestamp:   gc.Timestamp,
				}
			}

			payload := types.CommitNotifyMultiRequest{
				Commits:        commits,
				BeforeSHA:      os.Getenv("GITHUB_EVENT_BEFORE"),
				AfterSHA:       os.Getenv("GITHUB_SHA"),
				Repository:     repository,
				Branch:         branch,
				ClientName:     clientName,
				ClientEmail:    email,
				ClientCCEmail:  cc,
				ClientBCCEmail: bcc,
				ProjectName:    project,
				ServiceType:    service,
			}

			fmt.Printf("Sending commit notification (%d commits)...\n", len(commits))
			fmt.Printf("  Project:    %s\n", project)
			fmt.Printf("  Client:     %s <%s>\n", clientName, email)
			if cc != "" {
				fmt.Printf("  CC:         %s\n", cc)
			}
			if bcc != "" {
				fmt.Printf("  BCC:        %s\n", bcc)
			}
			fmt.Printf("  Service:    %s\n", service)
			fmt.Printf("  Repository: %s\n", repository)
			fmt.Printf("  Branch:     %s\n", branch)
			for _, c := range commits {
				short := c.SHA
				if len(short) > 7 {
					short = short[:7]
				}
				msg := c.Message
				if nl := strings.IndexByte(msg, '\n'); nl > 0 {
					msg = msg[:nl]
				}
				if len(msg) > 72 {
					msg = msg[:69] + "..."
				}
				fmt.Printf("  %s %s\n", short, msg)
			}
			fmt.Println()

			respBody, err := postWebhook(domain.Endpoint_CommitNotify, apiKey, payload)
			if err != nil {
				return fmt.Errorf("failed to send commit notification: %w", err)
			}

			fmt.Println("Commit notification sent successfully!")
			_ = respBody
			return nil
		}
	}

	// Single commit fallback
	message, _ := cmd.Flags().GetString("message")
	sha, _ := cmd.Flags().GetString("sha")
	commitURL, _ := cmd.Flags().GetString("url")
	author, _ := cmd.Flags().GetString("author")

	if sha == "" {
		sha = os.Getenv("GITHUB_SHA")
	}
	if message == "" {
		return fmt.Errorf("no commit data available. Set COMMITS_JSON env var or use --message flag")
	}
	if author == "" {
		author = envOrDefault("GITHUB_ACTOR", "unknown")
	}

	payload := types.CommitNotifySingleRequest{
		CommitMessage:  message,
		CommitSHA:      sha,
		CommitURL:      commitURL,
		AuthorName:     author,
		Repository:     repository,
		Branch:         branch,
		Timestamp:      time.Now().UTC().Format(time.RFC3339),
		ClientName:     clientName,
		ClientEmail:    email,
		ClientCCEmail:  cc,
		ClientBCCEmail: bcc,
		ProjectName:    project,
		ServiceType:    service,
	}

	fmt.Println("Sending commit notification...")
	fmt.Printf("  Project:    %s\n", project)
	fmt.Printf("  Client:     %s <%s>\n", clientName, email)
	if cc != "" {
		fmt.Printf("  CC:         %s\n", cc)
	}
	if bcc != "" {
		fmt.Printf("  BCC:        %s\n", bcc)
	}
	fmt.Printf("  Service:    %s\n", service)
	fmt.Printf("  Repository: %s\n", repository)
	fmt.Printf("  Branch:     %s\n", branch)
	if sha != "" {
		short := sha
		if len(short) > 7 {
			short = short[:7]
		}
		fmt.Printf("  Commit:     %s %s\n", short, message)
	}
	fmt.Println()

	respBody, err := postWebhook(domain.Endpoint_CommitNotify, apiKey, payload)
	if err != nil {
		return fmt.Errorf("failed to send commit notification: %w", err)
	}

	fmt.Println("Commit notification sent successfully!")
	_ = respBody
	return nil
}

func extractSOPSectionCount(content string) int {
	sectionRe := regexp.MustCompile(`(?m)^## \d+\.`)
	return len(sectionRe.FindAllString(content, -1))
}

func runGithubSOP(cmd *cobra.Command, args []string) error {
	apiKey, err := resolveAPIKey(cmd)
	if err != nil {
		return err
	}

	sopType, _ := cmd.Flags().GetString("type")
	filePath, _ := cmd.Flags().GetString("file")
	project, _ := cmd.Flags().GetString("project")
	clientName, _ := cmd.Flags().GetString("client")
	email, _ := cmd.Flags().GetString("email")
	cc, _ := cmd.Flags().GetString("cc")
	bcc, _ := cmd.Flags().GetString("bcc")
	threadID, _ := cmd.Flags().GetString("thread-id")
	version, _ := cmd.Flags().GetString("version")
	repository, _ := cmd.Flags().GetString("repository")
	branch, _ := cmd.Flags().GetString("branch")
	summary, _ := cmd.Flags().GetString("summary")

	// Validate SOP type
	if !validSOPTypes[sopType] {
		valid := make([]string, 0, len(validSOPTypes))
		for k := range validSOPTypes {
			valid = append(valid, k)
		}
		return fmt.Errorf("invalid SOP type %q. Valid types: %s", sopType, strings.Join(valid, ", "))
	}

	// Read markdown file
	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read SOP file: %w", err)
	}
	if len(strings.TrimSpace(string(content))) == 0 {
		return fmt.Errorf("SOP file is empty: %s", filePath)
	}

	// Resolve defaults
	fileName := filepath.Base(filePath)
	if version == "" {
		version = extractVersion(fileName)
	}
	if repository == "" {
		repository = envOrDefault("GITHUB_REPOSITORY", "unknown")
	}
	if branch == "" {
		branch = envOrDefault("GITHUB_REF_NAME", "main")
	}

	pipelineSource := "manual"
	if os.Getenv("CI") != "" || os.Getenv("GITHUB_ACTIONS") != "" {
		pipelineSource = "github_actions"
	}

	sectionCount := extractSOPSectionCount(string(content))

	payload := types.SOPNotifyRequest{
		SOPType:         sopType,
		Repository:      repository,
		Branch:          branch,
		CommitSha:       os.Getenv("GITHUB_SHA"),
		PipelineSource:  pipelineSource,
		PipelineID:      os.Getenv("GITHUB_RUN_ID"),
		PipelineURL:     os.Getenv("GITHUB_SERVER_URL") + "/" + repository + "/actions/runs/" + os.Getenv("GITHUB_RUN_ID"),
		Status:          "completed",
		FileVersion:     version,
		FilePath:        filePath,
		FileName:        fileName,
		ProjectName:     project,
		ClientEmail:     email,
		ClientCCEmail:   cc,
		ClientBCCEmail:  bcc,
		ClientName:      clientName,
		ThreadID:        threadID,
		SectionCount:    sectionCount,
		Summary:         summary,
		MarkdownContent: string(content),
	}

	// Display info
	fmt.Printf("Sending %s SOP notification...\n", sopType)
	fmt.Printf("  Project:    %s\n", project)
	fmt.Printf("  Client:     %s <%s>\n", clientName, email)
	if cc != "" {
		fmt.Printf("  CC:         %s\n", cc)
	}
	if bcc != "" {
		fmt.Printf("  BCC:        %s\n", bcc)
	}
	fmt.Printf("  File:       %s\n", fileName)
	if version != "" {
		fmt.Printf("  Version:    %s\n", version)
	}
	fmt.Printf("  Repository: %s\n", repository)
	fmt.Printf("  Branch:     %s\n", branch)
	if threadID != "" {
		fmt.Printf("  Thread:     %s\n", threadID)
	}
	if sectionCount > 0 {
		fmt.Printf("  Sections:   %d\n", sectionCount)
	}
	fmt.Printf("  Source:     %s\n", pipelineSource)
	fmt.Println()

	respBody, err := postWebhook(domain.Endpoint_SOPNotify, apiKey, payload)
	if err != nil {
		return fmt.Errorf("failed to send SOP notification: %w", err)
	}

	var resp types.SOPNotifyResponse
	if err := json.Unmarshal(respBody, &resp); err != nil {
		fmt.Println("SOP notification sent successfully!")
		return nil
	}

	if !resp.Success && resp.Error != "" {
		return fmt.Errorf("server error: %s", resp.Error)
	}

	fmt.Println("SOP notification sent successfully!")
	if resp.PDFGenerated {
		fmt.Println("  PDF:        Generated")
	}
	if resp.EmailID != "" {
		fmt.Printf("  Email ID:   %s\n", resp.EmailID)
	}
	if len(resp.Recipients) > 0 {
		fmt.Printf("  Recipients: %s\n", strings.Join(resp.Recipients, ", "))
	}

	return nil
}

// --- GitHub Issue from ECN ---

func runGithubIssue(cmd *cobra.Command, args []string) error {
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

	filePath, _ := cmd.Flags().GetString("file")
	repo, _ := cmd.Flags().GetString("repo")
	update, _ := cmd.Flags().GetBool("update")
	dryRun, _ := cmd.Flags().GetBool("dry-run")
	milestone, _ := cmd.Flags().GetString("milestone")
	extraLabels, _ := cmd.Flags().GetStringSlice("extra-labels")
	commentMode, _ := cmd.Flags().GetBool("comment")

	// Auto-detect repo
	if repo == "" {
		repo = os.Getenv("GITHUB_REPOSITORY")
	}
	if repo == "" {
		detected, err := ghcli.RepoFromLocal()
		if err == nil && detected != "" {
			repo = detected
		}
	}
	if repo == "" {
		return fmt.Errorf("--repo is required (could not auto-detect)")
	}

	// Read and parse ECN file
	content, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read ECN file: %w", err)
	}

	fm, body, err := parseECNFrontmatter(string(content))
	if err != nil {
		return fmt.Errorf("failed to parse frontmatter: %w", err)
	}

	issueTitle := fmt.Sprintf("[%s] %s", fm.ID, fm.Title)
	issueBody := buildIssueBody(fm, body, filePath)
	labels := buildIssueLabels(fm, extraLabels)

	fmt.Println("GitHub Issue from ECN")
	fmt.Printf("  Authenticated: %s\n", user)
	fmt.Printf("  Repository:    %s\n", repo)
	fmt.Printf("  ECN:           %s\n", fm.ID)
	fmt.Printf("  Title:         %s\n", issueTitle)
	fmt.Printf("  Severity:      %s\n", fm.Severity)
	fmt.Printf("  Status:        %s\n", fm.Status)
	fmt.Printf("  Labels:        %s\n", strings.Join(labels, ", "))
	if milestone != "" {
		fmt.Printf("  Milestone:     %s\n", milestone)
	}
	fmt.Println()

	if dryRun {
		fmt.Println("[dry-run] Would create/update issue. No changes made.")
		return nil
	}

	// Try to find and update existing issue
	if update {
		existingNum, existingURL, err := ghcli.FindIssueByTitle(repo, "["+fm.ID+"]", nil)
		if err == nil && existingNum > 0 {
			if commentMode {
				err = ghcli.AddComment(repo, existingNum, issueBody)
				if err != nil {
					return fmt.Errorf("failed to add comment: %w", err)
				}
				fmt.Printf("Added comment to issue #%d: %s\n", existingNum, existingURL)
			} else {
				_, err = ghcli.UpdateIssue(repo, existingNum, issueBody, labels)
				if err != nil {
					return fmt.Errorf("failed to update issue: %w", err)
				}
				fmt.Printf("Updated issue #%d: %s\n", existingNum, existingURL)
			}
			return nil
		}
	}

	// Create new issue
	num, url, err := ghcli.CreateIssue(repo, issueTitle, issueBody, labels, milestone)
	if err != nil {
		return fmt.Errorf("failed to create issue: %w", err)
	}
	fmt.Printf("Created issue #%d: %s\n", num, url)
	return nil
}

// parseECNFrontmatter extracts YAML frontmatter from an ECN markdown file.
// Returns the parsed frontmatter, the body (after second ---), and any error.
func parseECNFrontmatter(content string) (*types.ECNFrontmatter, string, error) {
	parts := strings.SplitN(content, "---", 3)
	if len(parts) < 3 {
		return nil, "", fmt.Errorf("no YAML frontmatter found (expected --- delimiters)")
	}

	fm := &types.ECNFrontmatter{}
	for _, line := range strings.Split(parts[1], "\n") {
		line = strings.TrimSpace(line)
		if line == "" || !strings.Contains(line, ":") {
			continue
		}
		idx := strings.Index(line, ":")
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		val = strings.Trim(val, "\"")

		switch key {
		case "id":
			fm.ID = val
		case "title":
			fm.Title = val
		case "type":
			fm.Type = val
		case "category":
			fm.Category = val
		case "disposition":
			fm.Disposition = val
		case "severity":
			fm.Severity = val
		case "status":
			fm.Status = val
		case "source":
			fm.Source = val
		case "affected":
			fm.Affected = val
		case "created_date":
			fm.CreatedDate = val
		case "updated_date":
			fm.UpdatedDate = val
		case "author":
			fm.Author = val
		case "thread_id":
			fm.ThreadID = val
		case "cross_references":
			val = strings.Trim(val, "[]")
			if val != "" {
				for _, ref := range strings.Split(val, ",") {
					fm.CrossReferences = append(fm.CrossReferences, strings.TrimSpace(ref))
				}
			}
		}
	}

	if fm.ID == "" {
		return nil, "", fmt.Errorf("frontmatter missing required 'id' field")
	}

	body := strings.TrimSpace(parts[2])
	return fm, body, nil
}

// buildIssueBody constructs a GitHub Issue body from ECN metadata and content.
func buildIssueBody(fm *types.ECNFrontmatter, body, filePath string) string {
	var b strings.Builder

	b.WriteString("## ECN Metadata\n\n")
	b.WriteString("| Field | Value |\n|-------|-------|\n")
	b.WriteString(fmt.Sprintf("| ID | %s |\n", fm.ID))
	b.WriteString(fmt.Sprintf("| Severity | **%s** |\n", fm.Severity))
	b.WriteString(fmt.Sprintf("| Status | %s |\n", fm.Status))
	b.WriteString(fmt.Sprintf("| Type | %s |\n", fm.Type))
	if fm.Category != "" {
		b.WriteString(fmt.Sprintf("| Category | %s |\n", fm.Category))
	}
	b.WriteString(fmt.Sprintf("| Disposition | %s |\n", fm.Disposition))
	if fm.Author != "" {
		b.WriteString(fmt.Sprintf("| Author | %s |\n", fm.Author))
	}
	if fm.CreatedDate != "" {
		b.WriteString(fmt.Sprintf("| Created | %s |\n", fm.CreatedDate))
	}
	if fm.UpdatedDate != "" {
		b.WriteString(fmt.Sprintf("| Updated | %s |\n", fm.UpdatedDate))
	}
	if fm.Affected != "" {
		b.WriteString(fmt.Sprintf("| Affected | %s |\n", fm.Affected))
	}

	if len(fm.CrossReferences) > 0 {
		b.WriteString("\n## Cross References\n\n")
		for _, ref := range fm.CrossReferences {
			b.WriteString(fmt.Sprintf("- %s\n", ref))
		}
	}

	b.WriteString("\n---\n\n")
	b.WriteString(body)
	b.WriteString("\n\n---\n")
	b.WriteString(fmt.Sprintf("*Generated by `parts github issue` from `%s`*\n", filePath))

	return b.String()
}

// buildIssueLabels generates GitHub Issue labels from ECN frontmatter.
func buildIssueLabels(fm *types.ECNFrontmatter, extra []string) []string {
	labels := []string{"ecn"}

	if fm.Severity != "" {
		labels = append(labels, "severity:"+normalize(fm.Severity))
	}
	if fm.Status != "" {
		labels = append(labels, "status:"+normalize(fm.Status))
	}
	if fm.Type != "" {
		labels = append(labels, "type:"+normalize(fm.Type))
	}
	if fm.Disposition != "" {
		labels = append(labels, "disposition:"+normalize(fm.Disposition))
	}

	labels = append(labels, extra...)
	return labels
}

func normalize(s string) string {
	return strings.ToLower(strings.ReplaceAll(strings.TrimSpace(s), " ", "-"))
}
