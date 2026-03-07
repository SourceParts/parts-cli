package types

// StackupOptions contains options for stackup PDF generation
type StackupOptions struct {
	BoardName string
	Scale     int
	Output    string // output file path (default: auto-named from Content-Disposition)
}

// StackupDiffOptions contains options for stackup diff PDF generation
type StackupDiffOptions struct {
	NameA  string // label for revision A (default: "Revision A")
	NameB  string // label for revision B (default: "Revision B")
	DPI    int    // rasterization DPI (default: 200, range: 100-600)
	Output string // output file path
}
