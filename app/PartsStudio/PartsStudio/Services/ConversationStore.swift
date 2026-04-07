import Foundation
import Security

/// Manages JSON sidecar files for conversation threads next to cached PDFs.
class ConversationStore: ObservableObject {
    @Published var threads: [ConversationThread] = []
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var syncError: String? = nil

    private var currentDatasheet: CachedDatasheet?

    // MARK: - Sidecar path

    private func sidecarPath(for datasheet: CachedDatasheet) -> URL {
        let pdfURL = URL(fileURLWithPath: datasheet.path)
        let name = pdfURL.deletingPathExtension().lastPathComponent
        return pdfURL.deletingLastPathComponent().appendingPathComponent("\(name).conversations.json")
    }

    // MARK: - Load

    func load(for datasheet: CachedDatasheet) {
        currentDatasheet = datasheet
        let path = sidecarPath(for: datasheet)

        guard let data = try? Data(contentsOf: path) else {
            threads = []
            return
        }

        do {
            let file = try JSONDecoder().decode(ConversationFile.self, from: data)
            threads = file.threads
        } catch {
            threads = []
        }
    }

    // MARK: - Save

    func save() {
        guard let datasheet = currentDatasheet else { return }
        let path = sidecarPath(for: datasheet)

        let file = ConversationFile(
            version: 1,
            contentHash: datasheet.contentHash,
            threads: threads
        )

        do {
            let data = try JSONEncoder.prettyPrinted.encode(file)
            try data.write(to: path, options: .atomic)
        } catch {
            // silent fail for now
        }
    }

    // MARK: - Mutate

    func addThread(page: Int, anchorX: CGFloat, anchorY: CGFloat, text: String, selectedText: String? = nil) {
        let author = NSUserName()
        let comment = Comment(author: author, text: text)
        let thread = ConversationThread(page: page, anchorX: anchorX, anchorY: anchorY, initialComment: comment, selectedText: selectedText)
        threads.append(thread)
        save()
    }

    func addReply(threadId: String, text: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        let author = NSUserName()
        threads[index].addReply(author: author, text: text)
        save()
    }

    func resolveThread(id: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].resolved = true
        save()
    }

    func unresolveThread(id: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].resolved = false
        save()
    }

    func deleteThread(id: String) {
        threads.removeAll { $0.id == id }
        save()
    }

    func threadsForPage(_ page: Int) -> [ConversationThread] {
        threads.filter { $0.page == page }
    }

    // MARK: - Remote Sync

    /// Syncs local conversation threads with the remote API.
    /// Builds a ConversationFile JSON, POSTs it to the sync endpoint,
    /// and replaces local threads with the merged result.
    func sync() async {
        guard let datasheet = currentDatasheet else { return }

        await MainActor.run {
            isSyncing = true
            syncError = nil
        }

        defer {
            Task { @MainActor in
                isSyncing = false
            }
        }

        guard let apiKey = Self.loadAPIKey() else {
            await MainActor.run {
                syncError = "No API key found. Run `parts auth login` to authenticate."
            }
            return
        }

        let conversationFile = ConversationFile(
            version: 1,
            contentHash: datasheet.contentHash,
            threads: threads
        )

        let payload = SyncPayload(
            contentHash: datasheet.contentHash,
            conversations: conversationFile
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(payload)

            let url = URL(string: "\(PartsConfig.shared.apiURL)/v1/datasheets/threads/sync")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("PartsStudio/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { syncError = "Invalid response from server" }
                return
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                await MainActor.run {
                    if httpResponse.statusCode == 401 {
                        syncError = "Unauthorized. Run `parts auth login` to re-authenticate."
                    } else {
                        syncError = "Sync failed (HTTP \(httpResponse.statusCode)): \(body)"
                    }
                }
                return
            }

            let mergedFile = try JSONDecoder().decode(ConversationFile.self, from: data)

            await MainActor.run {
                threads = mergedFile.threads
                lastSyncDate = Date()
            }

            save()
        } catch {
            await MainActor.run {
                syncError = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - API Key

    /// Loads the API key from the macOS Keychain (parts-cli service)
    /// or falls back to the PARTS_API_KEY environment variable.
    private static func loadAPIKey() -> String? {
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
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }

        return nil
    }
}

// MARK: - Sync Payload

/// The JSON envelope sent to POST /v1/datasheets/threads/sync
private struct SyncPayload: Codable {
    let contentHash: String
    let conversations: ConversationFile

    enum CodingKeys: String, CodingKey {
        case contentHash = "content_hash"
        case conversations
    }
}
