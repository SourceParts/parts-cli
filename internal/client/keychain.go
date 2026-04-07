package client

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/SourceParts/parts-cli/internal/auth"
	"github.com/zalando/go-keyring"
)

const (
	// KeyringService is the service name used in the system keychain
	KeyringService = "parts-cli"
	// KeyringUser is the user/account name used in the system keychain
	KeyringUser          = "api-key"
	keychainOAuthAccess  = "oauth-access-token"
	keychainOAuthRefresh = "oauth-refresh-token"
	keychainOAuthMeta    = "oauth-metadata"
	keychainUpdateCfg    = "update-config"
)

// useFileStore is true when the system keychain is unavailable (headless VMs,
// Docker containers, CI runners without D-Bus Secret Service, etc.).
// Detected lazily on first credential access via detectBackend().
var (
	detectOnce   sync.Once
	useFileStore bool
)

// detectBackend probes the system keychain on first use.
// Uses a goroutine with a 2-second timeout so a locked or hung keychain
// (e.g. macOS Keychain waiting for password) doesn't block the CLI.
func detectBackend() {
	detectOnce.Do(func() {
		const probe = "__parts_keychain_probe__"
		ch := make(chan error, 1)
		go func() {
			ch <- keyring.Set(KeyringService, probe, "1")
		}()
		select {
		case err := <-ch:
			if err != nil {
				useFileStore = true
				return
			}
			go keyring.Delete(KeyringService, probe)
		case <-time.After(2 * time.Second):
			useFileStore = true
		}
	})
}

// StorageBackend returns a human-readable name for the active credential store.
// Returns "env" if PARTS_TOKEN is set, "keychain" if using the system keychain,
// or "file (<path>)" if using the file-based fallback.
func StorageBackend() string {
	if os.Getenv("PARTS_TOKEN") != "" {
		return "env (PARTS_TOKEN)"
	}
	detectBackend()
	if useFileStore {
		return fmt.Sprintf("file (%s)", defaultFileStore.filePath())
	}
	return "keychain"
}

// credSet writes a credential, using the system keychain or file fallback.
func credSet(service, account, value string) error {
	detectBackend()
	if useFileStore {
		return defaultFileStore.set(service, account, value)
	}
	return keyring.Set(service, account, value)
}

// credGet reads a credential, using the system keychain or file fallback.
func credGet(service, account string) (string, error) {
	detectBackend()
	if useFileStore {
		val, err := defaultFileStore.get(service, account)
		if err == errFileNotFound {
			return "", keyring.ErrNotFound
		}
		return val, err
	}
	return keyring.Get(service, account)
}

// credDelete removes a credential, using the system keychain or file fallback.
func credDelete(service, account string) error {
	detectBackend()
	if useFileStore {
		return defaultFileStore.delete(service, account)
	}
	return keyring.Delete(service, account)
}

// oauthMeta holds the non-JWT fields of OAuthTokens, stored as a small JSON blob.
type oauthMeta struct {
	IDToken   string    `json:"id_token"`
	ExpiresAt time.Time `json:"expires_at"`
	Sub       string    `json:"sub"`
	Email     string    `json:"email"`
}

// SaveAPIKey saves the API key to the system keychain.
// Uses platform-specific secure storage:
//   - macOS: Keychain
//   - Linux: Secret Service (GNOME Keyring, KWallet)
//   - Windows: Credential Manager
//
// Falls back to ~/.config/parts/credentials.json on headless systems.
func SaveAPIKey(apiKey string) error {
	if apiKey == "" {
		return fmt.Errorf("API key cannot be empty")
	}
	err := credSet(KeyringService, KeyringUser, apiKey)
	if err != nil {
		return fmt.Errorf("failed to save API key: %w", err)
	}
	return nil
}

// LoadAPIKey retrieves the API key from the system keychain.
// Returns empty string if no key is found (not an error condition).
func LoadAPIKey() (string, error) {
	apiKey, err := credGet(KeyringService, KeyringUser)
	if err != nil {
		if err == keyring.ErrNotFound {
			return "", nil
		}
		return "", fmt.Errorf("failed to load API key: %w", err)
	}
	return apiKey, nil
}

// DeleteAPIKey removes the API key from the system keychain.
func DeleteAPIKey() error {
	err := credDelete(KeyringService, KeyringUser)
	if err != nil {
		if err == keyring.ErrNotFound {
			return nil
		}
		return fmt.Errorf("failed to delete API key: %w", err)
	}
	return nil
}

// HasAPIKey checks if an API key is stored in the keychain.
func HasAPIKey() bool {
	apiKey, err := LoadAPIKey()
	return err == nil && apiKey != ""
}

// SaveOAuthTokens saves Auth0 OAuth tokens to the system keychain.
// Tokens are split across separate keychain entries to stay under
// the macOS Keychain per-item size limit.
func SaveOAuthTokens(tokens *auth.OAuthTokens) error {
	if err := credSet(KeyringService, keychainOAuthAccess, tokens.AccessToken); err != nil {
		return fmt.Errorf("failed to save access token: %w", err)
	}
	if err := credSet(KeyringService, keychainOAuthRefresh, tokens.RefreshToken); err != nil {
		return fmt.Errorf("failed to save refresh token: %w", err)
	}
	meta := oauthMeta{
		IDToken:   tokens.IDToken,
		ExpiresAt: tokens.ExpiresAt,
		Sub:       tokens.Sub,
		Email:     tokens.Email,
	}
	data, err := json.Marshal(meta)
	if err != nil {
		return fmt.Errorf("failed to encode OAuth metadata: %w", err)
	}
	if err := credSet(KeyringService, keychainOAuthMeta, string(data)); err != nil {
		return fmt.Errorf("failed to save OAuth metadata: %w", err)
	}
	return nil
}

// LoadOAuthTokens retrieves Auth0 OAuth tokens from the system keychain.
// Returns nil, nil if no tokens are stored.
// Falls back to the legacy single-entry format for backward compatibility.
func LoadOAuthTokens() (*auth.OAuthTokens, error) {
	access, err := credGet(KeyringService, keychainOAuthAccess)
	if err == keyring.ErrNotFound {
		return loadLegacyOAuthTokens()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to load access token: %w", err)
	}

	refresh, _ := credGet(KeyringService, keychainOAuthRefresh)

	metaStr, err := credGet(KeyringService, keychainOAuthMeta)
	if err != nil && err != keyring.ErrNotFound {
		return nil, fmt.Errorf("failed to load OAuth metadata: %w", err)
	}

	tokens := &auth.OAuthTokens{AccessToken: access, RefreshToken: refresh}
	if metaStr != "" {
		var meta oauthMeta
		if err := json.Unmarshal([]byte(metaStr), &meta); err == nil {
			tokens.IDToken = meta.IDToken
			tokens.ExpiresAt = meta.ExpiresAt
			tokens.Sub = meta.Sub
			tokens.Email = meta.Email
		}
	}
	return tokens, nil
}

// loadLegacyOAuthTokens reads the old single-entry "oauth-tokens" format.
func loadLegacyOAuthTokens() (*auth.OAuthTokens, error) {
	data, err := credGet(KeyringService, "oauth-tokens")
	if err != nil {
		if err == keyring.ErrNotFound {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to load OAuth tokens: %w", err)
	}
	var tokens auth.OAuthTokens
	if err := json.Unmarshal([]byte(data), &tokens); err != nil {
		return nil, fmt.Errorf("failed to decode OAuth tokens: %w", err)
	}
	return &tokens, nil
}

// DeleteOAuthTokens removes Auth0 OAuth tokens from the system keychain.
// Cleans up both the split entries and the legacy single-entry format.
func DeleteOAuthTokens() error {
	for _, acct := range []string{keychainOAuthAccess, keychainOAuthRefresh, keychainOAuthMeta, "oauth-tokens"} {
		err := credDelete(KeyringService, acct)
		if err != nil && err != keyring.ErrNotFound {
			return fmt.Errorf("failed to delete %s: %w", acct, err)
		}
	}
	return nil
}

// HasOAuthTokens checks if Auth0 OAuth tokens are stored in the keychain.
func HasOAuthTokens() bool {
	tokens, err := LoadOAuthTokens()
	return err == nil && tokens != nil
}

// SaveUpdateConfig saves the update configuration to the system keychain.
func SaveUpdateConfig(config interface{}) error {
	data, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("failed to encode update config: %w", err)
	}
	if err := credSet(KeyringService, keychainUpdateCfg, string(data)); err != nil {
		return fmt.Errorf("failed to save update config: %w", err)
	}
	return nil
}

// LoadUpdateConfig retrieves the update configuration from the system keychain.
// Returns nil, nil if no config is stored (caller should use DefaultConfig).
func LoadUpdateConfig() (map[string]interface{}, error) {
	data, err := credGet(KeyringService, keychainUpdateCfg)
	if err != nil {
		if err == keyring.ErrNotFound {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to load update config: %w", err)
	}
	var config map[string]interface{}
	if err := json.Unmarshal([]byte(data), &config); err != nil {
		return nil, fmt.Errorf("failed to decode update config: %w", err)
	}
	return config, nil
}
