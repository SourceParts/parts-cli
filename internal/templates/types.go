package templates

import "time"

// ProjectType represents the type of project template
type ProjectType string

const (
	ProjectTypePCB ProjectType = "pcb"
	ProjectTypeRFQ ProjectType = "rfq"
)

// ProjectMetadata contains project-specific information used during template generation
type ProjectMetadata struct {
	Name         string
	Description  string
	Author       string
	Organization string
	Type         ProjectType
	CreatedAt    time.Time
	Revision     string // Board revision letter, e.g. "A", "B" — default "A"
	KiCad        bool   // Whether to generate KiCad project scaffolding
	ClientName   string // Client name for LICENSE.md copyright attribution
	ClientEmail  string // Client email for workflow env vars
}

// DirectorySpec defines a directory to be created in the project
type DirectorySpec struct {
	Path        string // Relative path from project root
	Description string // Purpose of this directory
	GitKeep     bool   // Whether to create a .gitkeep file
}

// FileSpec defines a file to be generated from a template
type FileSpec struct {
	Path         string // Relative path from project root
	TemplateName string // Name of the template file to use
}

// Template defines a complete project template with directories and files
type Template struct {
	Name        string          // Template identifier
	Type        ProjectType     // Type of project
	Description string          // Human-readable description
	Directories []DirectorySpec // Directories to create
	Files       []FileSpec      // Files to generate
}

// NewMetadata creates a new ProjectMetadata with default values
func NewMetadata(name string) ProjectMetadata {
	return ProjectMetadata{
		Name:      name,
		Type:      ProjectTypePCB,
		Revision:  "A",
		CreatedAt: time.Now(),
	}
}

// WithDescription sets the description
func (m ProjectMetadata) WithDescription(desc string) ProjectMetadata {
	m.Description = desc
	return m
}

// WithAuthor sets the author
func (m ProjectMetadata) WithAuthor(author string) ProjectMetadata {
	m.Author = author
	return m
}

// WithOrganization sets the organization
func (m ProjectMetadata) WithOrganization(org string) ProjectMetadata {
	m.Organization = org
	return m
}

// WithType sets the project type
func (m ProjectMetadata) WithType(t ProjectType) ProjectMetadata {
	m.Type = t
	return m
}

// WithRevision sets the board revision letter
func (m ProjectMetadata) WithRevision(rev string) ProjectMetadata {
	m.Revision = rev
	return m
}

// WithKiCad enables KiCad project file generation
func (m ProjectMetadata) WithKiCad(kicad bool) ProjectMetadata {
	m.KiCad = kicad
	return m
}

// WithClientName sets the client name for copyright attribution
func (m ProjectMetadata) WithClientName(name string) ProjectMetadata {
	m.ClientName = name
	return m
}

// WithClientEmail sets the client email for workflow configuration
func (m ProjectMetadata) WithClientEmail(email string) ProjectMetadata {
	m.ClientEmail = email
	return m
}
