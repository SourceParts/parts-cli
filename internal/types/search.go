package types

// SearchOptions contains options for part search filtering
type SearchOptions struct {
	InStock bool
	EUOnly  bool
	USOnly  bool
	CNOnly  bool
	Limit   int
}
