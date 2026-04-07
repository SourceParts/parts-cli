package ghcli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// PartsConfig holds the github section from .parts/config.yaml.
type PartsConfig struct {
	Repo          string
	DefaultBranch string
}

// SyncState holds per-user local sync state from .parts/sync.json.
// This file is gitignored — it tracks the user's own view of the remote.
type SyncState struct {
	LastSynced    string `json:"last_synced"`
	LastRemoteSHA string `json:"last_remote_sha"`
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

// ReadSyncState reads .parts/sync.json (local-only state).
func ReadSyncState(dir string) *SyncState {
	partsDir := findPartsDir(dir)
	if partsDir == "" {
		return nil
	}
	data, err := os.ReadFile(filepath.Join(partsDir, "sync.json"))
	if err != nil {
		return nil
	}
	var s SyncState
	if err := json.Unmarshal(data, &s); err != nil {
		return nil
	}
	return &s
}

// WriteSyncState writes .parts/sync.json (local-only state).
func WriteSyncState(dir string, state *SyncState) error {
	partsDir := findPartsDir(dir)
	if partsDir == "" {
		return nil
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(partsDir, "sync.json"), data, 0644)
}

// WritePartsConfigField updates a single field under the github: section
// in .parts/config.yaml.
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
		return nil
	}

	return os.WriteFile(configPath, []byte(strings.Join(lines, "\n")), 0644)
}

func findPartsDir(dir string) string {
	current := dir
	for {
		partsDir := filepath.Join(current, ".parts")
		if info, err := os.Stat(partsDir); err == nil && info.IsDir() {
			return partsDir
		}
		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return ""
}

func findPartsConfig(dir string) string {
	partsDir := findPartsDir(dir)
	if partsDir == "" {
		return ""
	}
	config := filepath.Join(partsDir, "config.yaml")
	if _, err := os.Stat(config); err == nil {
		return config
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
		}
	}

	if cfg.Repo == "" {
		return nil
	}
	return cfg
}
