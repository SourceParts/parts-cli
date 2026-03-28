package types

// FirmwareUploadOptions contains options for firmware upload.
type FirmwareUploadOptions struct {
	Chip        string // e.g., "W25N01GV"
	JedecID     string // e.g., "ef:aa:21"
	BoardSerial string // e.g., "PP-F1C200s-B8642360"
	SoC         string // e.g., "F1C200s"
	DieUID      string // e.g., "c2:62:24:07:67:23:32:32"
	MetadataFile string // path to metadata JSON file
}

// FirmwareUploadResponse from the API.
type FirmwareUploadResponse struct {
	ID          int    `json:"id"`
	SHA256      string `json:"sha256"`
	StoragePath string `json:"storage_path"`
	Size        int64  `json:"size"`
}

// FirmwareListOptions for filtering firmware list queries.
type FirmwareListOptions struct {
	JedecID     string
	Chip        string
	BoardSerial string
}

// FirmwareListItem represents a firmware entry in list responses.
type FirmwareListItem struct {
	ID          int    `json:"id"`
	SHA256      string `json:"sha256"`
	JedecID     string `json:"jedec_id"`
	Chip        string `json:"chip"`
	BoardSerial string `json:"board_serial"`
	SoC         string `json:"soc"`
	Size        int64  `json:"size"`
	StoragePath string `json:"storage_path"`
	CreatedAt   string `json:"created_at"`
}
