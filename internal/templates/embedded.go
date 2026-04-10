package templates

import (
	"embed"
	"fmt"
	"io/fs"
)

//go:embed embedded/*.tmpl
var embeddedFS embed.FS

// GetTemplateContent returns the content of an embedded template file
func GetTemplateContent(name string) (string, error) {
	path := "embedded/" + name
	content, err := fs.ReadFile(embeddedFS, path)
	if err != nil {
		return "", fmt.Errorf("failed to read template %s: %w", name, err)
	}
	return string(content), nil
}
