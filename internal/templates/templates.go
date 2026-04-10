package templates

import (
	"fmt"
	"sync"
)

var (
	registry     = make(map[string]Template)
	registryLock sync.RWMutex
)

func init() {
	RegisterTemplate(PCBTemplate())
}

// RegisterTemplate adds a template to the registry
func RegisterTemplate(t Template) {
	registryLock.Lock()
	defer registryLock.Unlock()
	registry[t.Name] = t
}

// GetTemplate retrieves a template by name
func GetTemplate(name string) (Template, error) {
	registryLock.RLock()
	defer registryLock.RUnlock()

	t, ok := registry[name]
	if !ok {
		return Template{}, fmt.Errorf("template not found: %s", name)
	}
	return t, nil
}

// PCBTemplate returns a PCB-focused project template
func PCBTemplate() Template {
	return Template{
		Name:        "pcb",
		Type:        ProjectTypePCB,
		Description: "PCB design focused project",
		Directories: []DirectorySpec{
			{Path: ".parts", Description: "Project configuration", GitKeep: false},
			{Path: "BOM/{{.Revision}}", Description: "Bill of Materials", GitKeep: true},
			{Path: "Datasheets", Description: "Component datasheets", GitKeep: true},
			{Path: "DRC", Description: "Design Rule Check reports", GitKeep: true},
			{Path: "ERC", Description: "Electrical Rule Check reports", GitKeep: true},
			{Path: "ECO", Description: "Engineering Change Orders", GitKeep: true},
			{Path: "PCB/{{.Revision}}", Description: "PCB design files", GitKeep: true},
			{Path: "Original_Files", Description: "Client submissions", GitKeep: true},
			{Path: "Reports", Description: "Analysis reports", GitKeep: true},
			{Path: "IQC", Description: "Incoming Quality Control", GitKeep: true},
			{Path: "DFT", Description: "Design for Test", GitKeep: true},
			{Path: "SOP", Description: "Standard Operating Procedures", GitKeep: true},
			{Path: "PRD", Description: "Product Requirements Documents", GitKeep: false},
			{Path: "Mechanical", Description: "Mechanical design files", GitKeep: true},
			{Path: "Mechanical/3D", Description: "3D models and STEP files", GitKeep: true},
		},
		Files: []FileSpec{
			{Path: "README.md", TemplateName: "README.md.tmpl"},
			{Path: "PARTS.md", TemplateName: "PARTS.md.tmpl"},
			{Path: "LICENSE.md", TemplateName: "LICENSE.md.tmpl"},
			{Path: ".gitignore", TemplateName: "gitignore.tmpl"},
			{Path: ".parts/config.yaml", TemplateName: "config.yaml.tmpl"},
			{Path: "PRD/PRD.md", TemplateName: "PRD.md.tmpl"},
		},
	}
}
