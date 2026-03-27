package types

// ReportNotifyRequest is the payload sent to the report-notify webhook endpoint
type ReportNotifyRequest struct {
	ReportType      string `json:"report_type"`
	Repository      string `json:"repository"`
	Branch          string `json:"branch"`
	CommitSha       string `json:"commit_sha,omitempty"`
	PipelineSource  string `json:"pipeline_source"`
	PipelineID      string `json:"pipeline_id,omitempty"`
	PipelineURL     string `json:"pipeline_url,omitempty"`
	Status          string `json:"status"`
	FileVersion     string `json:"file_version,omitempty"`
	FilePath        string `json:"file_path,omitempty"`
	FileName        string `json:"file_name,omitempty"`
	ProjectName     string `json:"project_name"`
	ClientEmail     string `json:"client_email"`
	ClientCCEmail   string `json:"client_cc_email,omitempty"`
	ClientBCCEmail  string `json:"client_bcc_email,omitempty"`
	ClientName      string `json:"client_name"`
	IssuesCount     int    `json:"issues_count,omitempty"`
	Summary         string `json:"summary,omitempty"`
	ThreadID        string `json:"thread_id,omitempty"`
	MarkdownContent string `json:"markdown_content"`

	// ECN frontmatter metadata (extracted client-side for email template)
	ECNID          string `json:"ecn_id,omitempty"`
	ECNTitle       string `json:"ecn_title,omitempty"`
	ECNSeverity    string `json:"ecn_severity,omitempty"`
	ECNStatus      string `json:"ecn_status,omitempty"`
	ECNType        string `json:"ecn_type,omitempty"`
	ECNDisposition string `json:"ecn_disposition,omitempty"`
	ECNAuthor      string `json:"ecn_author,omitempty"`
	ECNUpdatedDate string `json:"ecn_updated_date,omitempty"`
}

// ReportNotifyResponse is the response from the report-notify webhook endpoint
type ReportNotifyResponse struct {
	Success         bool     `json:"success"`
	Message         string   `json:"message"`
	EmailID         string   `json:"email_id,omitempty"`
	NotificationID  string   `json:"notification_id,omitempty"`
	IsRevision      bool     `json:"is_revision"`
	PreviousVersion string   `json:"previous_version,omitempty"`
	Recipients      []string `json:"recipients,omitempty"`
	PDFGenerated    bool     `json:"pdf_generated"`
	Error           string   `json:"error,omitempty"`
}

// CommitInfo represents a single commit in a push event
type CommitInfo struct {
	SHA         string `json:"sha"`
	Message     string `json:"message"`
	AuthorName  string `json:"author_name"`
	AuthorEmail string `json:"author_email,omitempty"`
	URL         string `json:"url,omitempty"`
	Timestamp   string `json:"timestamp,omitempty"`
}

// CommitNotifyMultiRequest is the payload for multi-commit notifications
type CommitNotifyMultiRequest struct {
	Commits     []CommitInfo `json:"commits"`
	BeforeSHA   string       `json:"before_sha,omitempty"`
	AfterSHA    string       `json:"after_sha,omitempty"`
	Repository  string       `json:"repository"`
	Branch      string       `json:"branch"`
	ClientName  string       `json:"client_name"`
	ClientEmail string       `json:"client_email"`
	ProjectName string       `json:"project_name"`
	ServiceType string       `json:"service_type"`
}

// CommitNotifySingleRequest is the payload for single-commit notifications
type CommitNotifySingleRequest struct {
	CommitMessage string `json:"commit_message"`
	CommitSHA     string `json:"commit_sha"`
	CommitURL     string `json:"commit_url,omitempty"`
	AuthorName    string `json:"author_name"`
	AuthorEmail   string `json:"author_email,omitempty"`
	Repository    string `json:"repository"`
	Branch        string `json:"branch"`
	Timestamp     string `json:"timestamp"`
	ClientName    string `json:"client_name"`
	ClientEmail   string `json:"client_email"`
	ProjectName   string `json:"project_name"`
	ServiceType   string `json:"service_type"`
}

// GitHubCommitJSON represents a commit object from GitHub Actions COMMITS_JSON
type GitHubCommitJSON struct {
	ID        string              `json:"id"`
	Message   string              `json:"message"`
	Timestamp string              `json:"timestamp"`
	URL       string              `json:"url"`
	Author    GitHubCommitAuthor  `json:"author"`
	Committer GitHubCommitAuthor  `json:"committer"`
}

// GitHubCommitAuthor represents the author/committer in GitHub webhook JSON
type GitHubCommitAuthor struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Username string `json:"username"`
}

// ECNFrontmatter represents the YAML frontmatter of an ECN markdown file.
type ECNFrontmatter struct {
	ID              string
	Title           string
	Type            string
	Category        string
	Disposition     string
	Severity        string
	Status          string
	Source          string
	Affected        string
	CrossReferences []string
	CreatedDate     string
	UpdatedDate     string
	Author          string
	ThreadID        string
}
