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

	"github.com/SourceParts/parts-cli/internal/domain"
	"github.com/SourceParts/parts-cli/internal/types"
	"github.com/spf13/cobra"
)

// Valid report types accepted by the report-notify endpoint
var validReportTypes = map[string]bool{
	"ecn":               true,
	"schematic_review":  true,
	"dfm":               true,
	"dvt":               true,
	"dfm_review":        true,
	"dvt_scan":          true,
	"stackup_diff":      true,
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

func init() {
	// Report flags
	githubReport.Flags().StringP("type", "t", "", "Report type: ecn, schematic_review, dfm, dvt, dfm_review, dvt_scan, stackup_diff")
	githubReport.Flags().StringP("file", "f", "", "Path to markdown report file")
	githubReport.Flags().StringP("project", "p", "", "Project name")
	githubReport.Flags().StringP("client", "c", "", "Client full name")
	githubReport.Flags().StringP("email", "e", "", "Client email address")
	githubReport.Flags().String("cc", "", "CC email address")
	githubReport.Flags().StringP("api-key", "k", "", "API key (overrides env var)")
	githubReport.Flags().String("version", "", "File version (auto-extracted from filename if omitted)")
	githubReport.Flags().String("repository", "", "Repository name (default: GITHUB_REPOSITORY env or \"unknown\")")
	githubReport.Flags().String("branch", "", "Branch name (default: GITHUB_REF_NAME env or \"main\")")
	githubReport.Flags().StringP("summary", "s", "", "Engineer's notes / summary text")

	_ = githubReport.MarkFlagRequired("type")
	_ = githubReport.MarkFlagRequired("file")
	_ = githubReport.MarkFlagRequired("project")
	_ = githubReport.MarkFlagRequired("client")
	_ = githubReport.MarkFlagRequired("email")

	// Commit flags
	githubCommit.Flags().StringP("project", "p", "", "Project name")
	githubCommit.Flags().StringP("client", "c", "", "Client full name")
	githubCommit.Flags().StringP("email", "e", "", "Client email address")
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

	Github.AddCommand(githubReport)
	Github.AddCommand(githubCommit)
}

// resolveAPIKey resolves the GitHub API key from flag, then env vars
func resolveAPIKey(cmd *cobra.Command) (string, error) {
	key, _ := cmd.Flags().GetString("api-key")
	if key != "" {
		return key, nil
	}
	if key = os.Getenv("PARTS_GITHUB_API_KEY"); key != "" {
		return key, nil
	}
	if key = os.Getenv("GITHUB_API_KEY"); key != "" {
		return key, nil
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
	version, _ := cmd.Flags().GetString("version")
	repository, _ := cmd.Flags().GetString("repository")
	branch, _ := cmd.Flags().GetString("branch")
	summary, _ := cmd.Flags().GetString("summary")

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
		ClientName:      clientName,
		IssuesCount:     issuesCount,
		Summary:         summary,
		MarkdownContent: string(content),
	}

	// Display info
	fmt.Printf("Sending %s report notification...\n", reportType)
	fmt.Printf("  Project:    %s\n", project)
	fmt.Printf("  Client:     %s <%s>\n", clientName, email)
	if cc != "" {
		fmt.Printf("  CC:         %s\n", cc)
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
				Commits:     commits,
				BeforeSHA:   os.Getenv("GITHUB_EVENT_BEFORE"),
				AfterSHA:    os.Getenv("GITHUB_SHA"),
				Repository:  repository,
				Branch:      branch,
				ClientName:  clientName,
				ClientEmail: email,
				ProjectName: project,
				ServiceType: service,
			}

			fmt.Printf("Sending commit notification (%d commits)...\n", len(commits))
			fmt.Printf("  Project:    %s\n", project)
			fmt.Printf("  Client:     %s <%s>\n", clientName, email)
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
		CommitMessage: message,
		CommitSHA:     sha,
		CommitURL:     commitURL,
		AuthorName:    author,
		Repository:    repository,
		Branch:        branch,
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
		ClientName:    clientName,
		ClientEmail:   email,
		ProjectName:   project,
		ServiceType:   service,
	}

	fmt.Println("Sending commit notification...")
	fmt.Printf("  Project:    %s\n", project)
	fmt.Printf("  Client:     %s <%s>\n", clientName, email)
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
