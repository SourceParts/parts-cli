package client

import (
	"encoding/json"
	"fmt"

	"github.com/SourceParts/parts-cli/internal/auth"
	"github.com/zalando/go-keyring"
)

const (
	// KeyringService is the service name used in the system keychain
	KeyringService = "parts-cli"
	// KeyringUser is the user/account name used in the system keychain
	KeyringUser   = "api-key"
	keychainOAuth = "oauth-tokens"
)

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
func SaveOAuthTokens(tokens *auth.OAuthTokens) error {
	data, err := json.Marshal(tokens)
	if err != nil {
		return fmt.Errorf("failed to encode OAuth tokens: %w", err)
	}
	if err := keyring.Set(KeyringService, keychainOAuth, string(data)); err != nil {
		return fmt.Errorf("failed to save OAuth tokens to keychain: %w", err)
	}
	return nil
}

// LoadOAuthTokens retrieves Auth0 OAuth tokens from the system keychain.
// Returns nil, nil if no tokens are stored.
func LoadOAuthTokens() (*auth.OAuthTokens, error) {
	data, err := keyring.Get(KeyringService, keychainOAuth)
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
func DeleteOAuthTokens() error {
	err := keyring.Delete(KeyringService, keychainOAuth)
	if err != nil && err != keyring.ErrNotFound {
		return fmt.Errorf("failed to delete OAuth tokens from keychain: %w", err)
	}
	return nil
}

// HasOAuthTokens checks if Auth0 OAuth tokens are stored in the keychain.
func HasOAuthTokens() bool {
	tokens, err := LoadOAuthTokens()
	return err == nil && tokens != nil
}
