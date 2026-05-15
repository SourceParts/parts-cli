package types

// APIResponse is the standard envelope returned by the parts API:
// {"status": "success", "data": {…}, "error": "…"}.
type APIResponse[T any] struct {
	Status string `json:"status"`
	Data   T      `json:"data"`
	Error  string `json:"error,omitempty"`
}

type ProjectListOptions struct {
	Limit  int    `json:"limit,omitempty"`
	Offset int    `json:"offset,omitempty"`
	Status string `json:"status,omitempty"`
}

// ProjectCreateData is the data payload for POST /v1/projects.
type ProjectCreateData struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Message string `json:"message,omitempty"`
}

// ProjectCreateResponse is the full envelope for POST /v1/projects.
type ProjectCreateResponse = APIResponse[ProjectCreateData]

type ECORequest struct {
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	ChangesFile string `json:"-"`
	Changes     []any  `json:"changes,omitempty"`
}
