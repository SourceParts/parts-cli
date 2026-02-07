package client

import (
	"fmt"

	"github.com/zalando/go-keyring"
)

const (
	// KeyringService is the service name used in the system keychain
	KeyringService = "parts-cli"
	// KeyringUser is the user/account name used in the system keychain
	KeyringUser = "api-key"
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
