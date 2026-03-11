package types

// ReleaseOptions contains options for fabrication release package creation
type ReleaseOptions struct {
	Version     string
	Notes       string
	IncludeBOM  bool
	IncludeAsm  bool
	Output      string
}

// ReleaseResponse represents the initial API response from manufacturing publish
type ReleaseResponse struct {
	Status string      `json:"status"`
	Data   ReleaseData `json:"data"`
}

// ReleaseData contains the job info returned from the publish endpoint
type ReleaseData struct {
	JobID     string `json:"job_id"`
	Message   string `json:"message"`
	StatusURL string `json:"status_url"`
}

// ReleaseStatusResponse represents a polling response for job status
type ReleaseStatusResponse struct {
	Status   string `json:"status"`
	Progress int    `json:"progress"`
	Error    string `json:"error,omitempty"`
	Data     struct {
		DRCErrors  int    `json:"drc_errors"`
		PackageURL string `json:"package_url,omitempty"`
	} `json:"data"`
}
