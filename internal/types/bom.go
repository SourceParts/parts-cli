package types

// BOMUploadOptions contains options for BOM upload
type BOMUploadOptions struct {
	ProjectID   string
	Wait        bool
	ExtractLCSC bool
}

// BOMUploadResponse represents the API response from BOM upload
type BOMUploadResponse struct {
	FileName      string         `json:"fileName"`
	Hash          string         `json:"hash"`
	ItemCount     int            `json:"itemCount"`
	JobID         string         `json:"jobId,omitempty"`
	ScraperStatus string         `json:"scraperStatus,omitempty"`
	LCSCParts     []LCSCPartInfo `json:"lcscParts,omitempty"`
}

// LCSCPartInfo represents LCSC component data
type LCSCPartInfo struct {
	LCSCNumber   string  `json:"lcscNumber"`
	PartNumber   string  `json:"partNumber,omitempty"`
	Manufacturer string  `json:"manufacturer,omitempty"`
	Description  string  `json:"description,omitempty"`
	DatasheetURL string  `json:"datasheetUrl,omitempty"`
	Price        float64 `json:"price,omitempty"`
	Stock        int     `json:"stock,omitempty"`
	Status       string  `json:"status"` // "fetched", "pending", "error"
}

// BOMStatusResponse represents the status check response
type BOMStatusResponse struct {
	JobID     string         `json:"jobId"`
	Status    string         `json:"status"` // "pending", "processing", "completed", "error"
	Progress  int            `json:"progress,omitempty"`
	LCSCParts []LCSCPartInfo `json:"lcscParts,omitempty"`
	Error     string         `json:"error,omitempty"`
}
