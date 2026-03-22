import Foundation
import Security

/// Shared helper for loading the API key from the macOS Keychain or environment.
/// Used by ConversationStore, IQCService, and any other service that needs auth.
///
/// Note: The binary must be code-signed to avoid repeated keychain prompts.
/// Sign after build: codesign --force --sign "PartsStudio Dev" .build/debug/PartsStudio
enum APIKeychain {
    /// Cached token to avoid repeated keychain access prompts.
    private static var cachedKey: String?

    /// Loads the API key from the PARTS_API_KEY environment variable,
    /// or falls back to the macOS Keychain. Checks both api-key (legacy)
    /// and oauth-access-token (from `parts auth login`).
    /// Caches the result for the entire session.
    static func loadAPIKey() -> String? {
        if let cached = cachedKey {
            return cached
        }

        // Try environment variable first (useful for development)
        if let envKey = ProcessInfo.processInfo.environment["PARTS_API_KEY"], !envKey.isEmpty {
            cachedKey = envKey
            return envKey
        }

        // Try accounts in order: api-key (static key), then oauth-access-token (from parts auth login)
        for account in ["api-key", "oauth-access-token"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "parts-cli",
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                // Go keyring stores values with "go-keyring-base64:" prefix + base64-encoded value
                let key: String
                if raw.hasPrefix("go-keyring-base64:") {
                    let encoded = String(raw.dropFirst("go-keyring-base64:".count))
                    if let decoded = Data(base64Encoded: encoded),
                       let token = String(data: decoded, encoding: .utf8), !token.isEmpty {
                        key = token
                    } else {
                        continue
                    }
                } else {
                    key = raw
                }
                cachedKey = key
                return key
            }
        }

        return nil
    }
}
