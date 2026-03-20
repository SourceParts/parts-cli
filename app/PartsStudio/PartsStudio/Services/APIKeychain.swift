import Foundation
import Security

/// Shared helper for loading the API key from the macOS Keychain or environment.
/// Used by ConversationStore, IQCService, and any other service that needs auth.
enum APIKeychain {
    /// Loads the API key from the PARTS_API_KEY environment variable,
    /// or falls back to the macOS Keychain (parts-cli service, api-key account).
    static func loadAPIKey() -> String? {
        // Try environment variable first (useful for development)
        if let envKey = ProcessInfo.processInfo.environment["PARTS_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Read from macOS Keychain (matches parts-cli Go keyring: service="parts-cli", account="api-key")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "parts-cli",
            kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }

        return nil
    }
}
