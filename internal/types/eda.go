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

// NetlistExportOptions configures a netlist export.
type NetlistExportOptions struct {
	Format string // "xml" or "json"
}

// ExportOptions configures a kicad-cli export.
type ExportOptions struct {
	Format     string            // e.g. "step", "ipc2581", "bom"
	FormFields map[string]string // format-specific parameters
}
