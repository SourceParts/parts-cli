package types

// PriceOptions contains options for price estimation
type PriceOptions struct {
	Quantity int
	Currency string
}

type PriceResponse struct {
	Status string    `json:"status"`
	Data   PriceData `json:"data"`
}

type PriceData struct {
	Parts         []PricePartResult `json:"parts"`
	TotalEstimate float64           `json:"total_estimate"`
	Currency      string            `json:"currency"`
}

type PricePartResult struct {
	PartNumber string  `json:"part_number"`
	Quantity   int     `json:"quantity"`
	UnitPrice  float64 `json:"unit_price"`
	Total      float64 `json:"total"`
	Available  bool    `json:"available"`
}

// AllUnavailable returns true if every part in the estimate came back
// with zero price and unavailable status.
func (d *PriceData) AllUnavailable() bool {
	if len(d.Parts) == 0 {
		return true
	}
	for _, p := range d.Parts {
		if p.Available || p.UnitPrice > 0 {
			return false
		}
	}
	return true
}
