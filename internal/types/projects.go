package types

type ProjectListOptions struct {
	Limit  int    `json:"limit,omitempty"`
	Offset int    `json:"offset,omitempty"`
	Status string `json:"status,omitempty"`
}

type ECORequest struct {
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	ChangesFile string `json:"-"`
	Changes     []any  `json:"changes,omitempty"`
}
