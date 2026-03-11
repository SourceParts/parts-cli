package types

// SearchOptions contains options for part search filtering
type SearchOptions struct {
	InStock bool
	EUOnly  bool
	USOnly  bool
	CNOnly  bool
	Limit   int
}

type SearchResponse struct {
	Status string           `json:"status"`
	Data   SearchResultData `json:"data"`
}

type SearchResultData struct {
	Parts  []SearchPart `json:"parts"`
	Total  int          `json:"total"`
	Limit  int          `json:"limit"`
	Offset int          `json:"offset"`
	Query  string       `json:"query"`
}

type SearchPart struct {
	SKU           string  `json:"sku"`
	Name          string  `json:"name"`
	Manufacturer  string  `json:"manufacturer"`
	Description   string  `json:"description"`
	Category      string  `json:"category"`
	Price         *string `json:"price"`
	StockQuantity int     `json:"stock_quantity"`
}
