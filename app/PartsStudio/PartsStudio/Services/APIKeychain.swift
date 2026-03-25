import Foundation
import Security

/// Shared helper for loading the API key from the macOS Keychain or environment.
/// Used by ConversationStore, IQCService, and any other service that needs auth.
///
/// Note: The binary must be code-signed to avoid repeated keychain prompts.
/// Sign after build: codesign --force --sign "PartsStudio Dev" .build/debug/PartsStudio
enum APIKeychain {
    /// Cached token to avoid repeated keychain access prompts.
    /// Only caches non-nil results — retries on nil so login during session is picked up.
    private static var cachedKey: String?

    /// Clear the cached token so the next loadAPIKey() re-reads from keychain.
    /// Call this on HTTP 401 to pick up a fresh token after re-authentication.
    static func clearCache() {
        cachedKey = nil
    }

    /// Loads the API key from the PARTS_API_KEY environment variable,
    /// or falls back to the macOS Keychain. Checks both api-key (legacy)
    /// and oauth-access-token (from `parts auth login`).
    /// Caches non-nil results for the session. Retries if previously nil.
    static func loadAPIKey() -> String? {
        if let cached = cachedKey {
            return cached
        }
        // Don't cache nil — allow retry after login

        // Try environment variable first (useful for development)
        if let envKey = ProcessInfo.processInfo.environment["PARTS_API_KEY"], !envKey.isEmpty {
            cachedKey = envKey
            return envKey
        }

        // Use `security` CLI to read keychain — avoids ACL/cdhash issues with unsigned builds.
        // The `security` binary is always trusted by the keychain.
        for account in ["api-key", "oauth-access-token"] {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            proc.arguments = ["find-generic-password", "-s", "parts-cli", "-a", account, "-w"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { continue }

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
            } catch {
                continue
            }
        }

        return nil
    }
}
