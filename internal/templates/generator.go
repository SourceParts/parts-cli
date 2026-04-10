package templates

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

// Generator handles project structure generation from templates
type Generator struct {
	Template Template
	Metadata ProjectMetadata
	BasePath string
}

// NewGenerator creates a new Generator instance
func NewGenerator(tmpl Template, meta ProjectMetadata, basePath string) *Generator {
	return &Generator{
		Template: tmpl,
		Metadata: meta,
		BasePath: basePath,
	}
}

// Generate creates the complete project structure
func (g *Generator) Generate() error {
	// Create directories first
	if err := g.CreateDirectories(); err != nil {
		return fmt.Errorf("failed to create directories: %w", err)
	}

	// Generate files from templates
	if err := g.GenerateFiles(); err != nil {
		return fmt.Errorf("failed to generate files: %w", err)
	}

	// Generate KiCad project files if requested
	if g.Metadata.KiCad {
		kicadFiles := []FileSpec{
			{Path: "PCB/{{.Revision}}/{{.Name}}.kicad_pro", TemplateName: "kicad_pro.tmpl"},
			{Path: "PCB/{{.Revision}}/{{.Name}}.kicad_sch", TemplateName: "kicad_sch.tmpl"},
		}
		for _, file := range kicadFiles {
			if err := g.GenerateFile(file); err != nil {
				return fmt.Errorf("failed to generate KiCad file %s: %w", file.Path, err)
			}
		}
	}

	return nil
}

// resolvePath interpolates template variables (e.g. {{.Revision}}) in a path string
func (g *Generator) resolvePath(path string) (string, error) {
	// Fast path: no template syntax
	if !strings.Contains(path, "{{") {
		return path, nil
	}

	tmpl, err := template.New("path").Parse(path)
	if err != nil {
		return "", fmt.Errorf("failed to parse path template %q: %w", path, err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, g.Metadata); err != nil {
		return "", fmt.Errorf("failed to resolve path %q: %w", path, err)
	}
	return buf.String(), nil
}

// CreateDirectories creates all directories defined in the template
func (g *Generator) CreateDirectories() error {
	for _, dir := range g.Template.Directories {
		resolved, err := g.resolvePath(dir.Path)
		if err != nil {
			return err
		}

		dirPath := filepath.Join(g.BasePath, resolved)

		// Create directory with parents
		if err := os.MkdirAll(dirPath, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", resolved, err)
		}

		// Create .gitkeep if specified
		if dir.GitKeep {
			gitkeepPath := filepath.Join(dirPath, ".gitkeep")
			if err := os.WriteFile(gitkeepPath, []byte{}, 0644); err != nil {
				return fmt.Errorf("failed to create .gitkeep in %s: %w", resolved, err)
			}
		}
	}
	return nil
}

// GenerateFiles generates all files from templates
func (g *Generator) GenerateFiles() error {
	for _, file := range g.Template.Files {
		if err := g.GenerateFile(file); err != nil {
			return fmt.Errorf("failed to generate %s: %w", file.Path, err)
		}
	}
	return nil
}

// GenerateFile generates a single file from a template
func (g *Generator) GenerateFile(file FileSpec) error {
	// Resolve path template variables (e.g. {{.Revision}})
	resolvedPath, err := g.resolvePath(file.Path)
	if err != nil {
		return err
	}

	// Get template content
	content, err := GetTemplateContent(file.TemplateName)
	if err != nil {
		return err
	}

	// Parse and execute template
	tmpl, err := template.New(file.TemplateName).Parse(content)
	if err != nil {
		return fmt.Errorf("failed to parse template: %w", err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, g.Metadata); err != nil {
		return fmt.Errorf("failed to execute template: %w", err)
	}

	// Ensure parent directory exists
	filePath := filepath.Join(g.BasePath, resolvedPath)
	if err := os.MkdirAll(filepath.Dir(filePath), 0755); err != nil {
		return fmt.Errorf("failed to create parent directory: %w", err)
	}

	// Write file
	if err := os.WriteFile(filePath, buf.Bytes(), 0644); err != nil {
		return fmt.Errorf("failed to write file: %w", err)
	}

	return nil
}

// GenerateToPath generates the project structure at the given path
func GenerateToPath(templateName string, meta ProjectMetadata, basePath string) error {
	tmpl, err := GetTemplate(templateName)
	if err != nil {
		return err
	}

	gen := NewGenerator(tmpl, meta, basePath)
	return gen.Generate()
}
