package client

import (
	"encoding/json"
	"fmt"
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
func SaveAPIKey(apiKey string) error {
	if apiKey == "" {
		return fmt.Errorf("API key cannot be empty")
	}
	err := keyring.Set(KeyringService, KeyringUser, apiKey)
	if err != nil {
		return fmt.Errorf("failed to save API key to keychain: %w", err)
	}
	return nil
}

// LoadAPIKey retrieves the API key from the system keychain.
// Returns empty string if no key is found (not an error condition).
func LoadAPIKey() (string, error) {
	apiKey, err := keyring.Get(KeyringService, KeyringUser)
	if err != nil {
		if err == keyring.ErrNotFound {
			return "", nil
		}
		return "", fmt.Errorf("failed to load API key from keychain: %w", err)
	}
	return apiKey, nil
}

// DeleteAPIKey removes the API key from the system keychain.
func DeleteAPIKey() error {
	err := keyring.Delete(KeyringService, KeyringUser)
	if err != nil {
		if err == keyring.ErrNotFound {
			return nil
		}
		return fmt.Errorf("failed to delete API key from keychain: %w", err)
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
	if err := keyring.Set(KeyringService, keychainOAuthAccess, tokens.AccessToken); err != nil {
		return fmt.Errorf("failed to save access token to keychain: %w", err)
	}
	if err := keyring.Set(KeyringService, keychainOAuthRefresh, tokens.RefreshToken); err != nil {
		return fmt.Errorf("failed to save refresh token to keychain: %w", err)
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
	if err := keyring.Set(KeyringService, keychainOAuthMeta, string(data)); err != nil {
		return fmt.Errorf("failed to save OAuth metadata to keychain: %w", err)
	}
	return nil
}

// LoadOAuthTokens retrieves Auth0 OAuth tokens from the system keychain.
// Returns nil, nil if no tokens are stored.
// Falls back to the legacy single-entry format for backward compatibility.
func LoadOAuthTokens() (*auth.OAuthTokens, error) {
	access, err := keyring.Get(KeyringService, keychainOAuthAccess)
	if err == keyring.ErrNotFound {
		return loadLegacyOAuthTokens()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to load access token from keychain: %w", err)
	}

	refresh, _ := keyring.Get(KeyringService, keychainOAuthRefresh)

	metaStr, err := keyring.Get(KeyringService, keychainOAuthMeta)
	if err != nil && err != keyring.ErrNotFound {
		return nil, fmt.Errorf("failed to load OAuth metadata from keychain: %w", err)
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
	data, err := keyring.Get(KeyringService, "oauth-tokens")
	if err != nil {
		if err == keyring.ErrNotFound {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to load OAuth tokens from keychain: %w", err)
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
		err := keyring.Delete(KeyringService, acct)
		if err != nil && err != keyring.ErrNotFound {
			return fmt.Errorf("failed to delete %s from keychain: %w", acct, err)
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
	if err := keyring.Set(KeyringService, keychainUpdateCfg, string(data)); err != nil {
		return fmt.Errorf("failed to save update config to keychain: %w", err)
	}
	return nil
}

// LoadUpdateConfig retrieves the update configuration from the system keychain.
// Returns nil, nil if no config is stored (caller should use DefaultConfig).
func LoadUpdateConfig() (map[string]interface{}, error) {
	data, err := keyring.Get(KeyringService, keychainUpdateCfg)
	if err != nil {
		if err == keyring.ErrNotFound {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to load update config from keychain: %w", err)
	}
	var config map[string]interface{}
	if err := json.Unmarshal([]byte(data), &config); err != nil {
		return nil, fmt.Errorf("failed to decode update config: %w", err)
	}
	return config, nil
}
