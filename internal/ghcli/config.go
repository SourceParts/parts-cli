package ghcli

import (
	"os"
	"path/filepath"
	"strings"
)

// PartsConfig holds the github section from .parts/config.yaml.
type PartsConfig struct {
	Repo          string
	DefaultBranch string
	LastSynced    string
	LastRemoteSHA string
}

// ReadPartsConfig walks up from dir to find .parts/config.yaml and
// extracts the github section. Returns nil if not found.
func ReadPartsConfig(dir string) *PartsConfig {
	configPath := findPartsConfig(dir)
	if configPath == "" {
		return nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil
	}

	return parseGitHubSection(string(data))
}

// WritePartsConfigField updates a single field under the github: section
// in .parts/config.yaml. Creates the section if it doesn't exist.
func WritePartsConfigField(dir, key, value string) error {
	configPath := findPartsConfig(dir)
	if configPath == "" {
		return nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}

	content := string(data)
	yamlKey := "  " + key + ":"

	// Find and replace the line
	lines := strings.Split(content, "\n")
	found := false
	inGithub := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "github:" {
			inGithub = true
			continue
		}
		if inGithub && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") && trimmed != "" {
			inGithub = false
		}
		if inGithub && strings.HasPrefix(line, yamlKey) {
			if value == "" {
				lines[i] = yamlKey + " \"\""
			} else {
				lines[i] = yamlKey + " \"" + value + "\""
			}
			found = true
			break
		}
	}

	if !found {
		return nil // key not in config, skip
	}

	return os.WriteFile(configPath, []byte(strings.Join(lines, "\n")), 0644)
}

func findPartsConfig(dir string) string {
	current := dir
	for {
		config := filepath.Join(current, ".parts", "config.yaml")
		if _, err := os.Stat(config); err == nil {
			return config
		}
		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return ""
}

func parseGitHubSection(content string) *PartsConfig {
	cfg := &PartsConfig{}
	inGithub := false

	for _, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "github:" {
			inGithub = true
			continue
		}
		// Exit github section when we hit a non-indented non-empty line
		if inGithub && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") && trimmed != "" {
			break
		}
		if !inGithub {
			continue
		}

		parts := strings.SplitN(trimmed, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		val = strings.Trim(val, "\"")

		switch key {
		case "repo":
			cfg.Repo = val
		case "default_branch":
			cfg.DefaultBranch = val
		case "last_synced":
			cfg.LastSynced = val
		case "last_remote_sha":
			cfg.LastRemoteSHA = val
		}
	}

	if cfg.Repo == "" {
		return nil
	}
	return cfg
}
