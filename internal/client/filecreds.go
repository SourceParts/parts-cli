package client

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

const (
	configDirName = "parts"
	credsFileName = "credentials.json"
)

// fileStore is a file-based credential store used as a fallback when no
// system keychain (Secret Service, Keychain, Credential Manager) is
// available — common on headless Linux VMs, Docker containers, and CI
// runners.
//
// Credentials are stored as plaintext JSON in ~/.config/parts/credentials.json
// with 0600 permissions (owner read/write only). This is less secure than a
// system keychain — prefer PARTS_TOKEN env var for CI/CD environments.
type fileStore struct {
	mu   sync.Mutex
	path string
}

var defaultFileStore = &fileStore{}

func (fs *fileStore) filePath() string {
	if fs.path != "" {
		return fs.path
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		home, _ := os.UserHomeDir()
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, configDirName, credsFileName)
}

// load reads the credential file into a nested map: service -> account -> value.
func (fs *fileStore) load() (map[string]map[string]string, error) {
	data, err := os.ReadFile(fs.filePath())
	if err != nil {
		if os.IsNotExist(err) {
			return make(map[string]map[string]string), nil
		}
		return nil, fmt.Errorf("read credentials file: %w", err)
	}
	var store map[string]map[string]string
	if err := json.Unmarshal(data, &store); err != nil {
		return nil, fmt.Errorf("parse credentials file: %w", err)
	}
	if store == nil {
		store = make(map[string]map[string]string)
	}
	return store, nil
}

// save atomically writes the credential map to disk.
func (fs *fileStore) save(store map[string]map[string]string) error {
	p := fs.filePath()
	if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}
	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return fmt.Errorf("encode credentials: %w", err)
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return fmt.Errorf("write credentials tmp: %w", err)
	}
	if err := os.Rename(tmp, p); err != nil {
		return fmt.Errorf("rename credentials file: %w", err)
	}
	return nil
}

func (fs *fileStore) set(service, account, value string) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	store, err := fs.load()
	if err != nil {
		return err
	}
	if store[service] == nil {
		store[service] = make(map[string]string)
	}
	store[service][account] = value
	return fs.save(store)
}

func (fs *fileStore) get(service, account string) (string, error) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	store, err := fs.load()
	if err != nil {
		return "", err
	}
	svc, ok := store[service]
	if !ok {
		return "", errFileNotFound
	}
	val, ok := svc[account]
	if !ok {
		return "", errFileNotFound
	}
	return val, nil
}

func (fs *fileStore) delete(service, account string) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	store, err := fs.load()
	if err != nil {
		return err
	}
	svc, ok := store[service]
	if !ok {
		return nil
	}
	delete(svc, account)
	if len(svc) == 0 {
		delete(store, service)
	}
	return fs.save(store)
}

var errFileNotFound = fmt.Errorf("credential not found")
