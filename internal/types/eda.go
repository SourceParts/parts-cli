package types

// ERCOptions configures an Electrical Rules Check run.
type ERCOptions struct {
	Severity  string // "all", "error", "warning", or "exclusion"
	RulesFile string // Optional custom rules file path
}

// DRCOptions configures a Design Rules Check run.
type DRCOptions struct {
	Severity  string // "all", "error", "warning", or "exclusion"
	RulesFile string // Optional .kicad_dru rules file path
}
