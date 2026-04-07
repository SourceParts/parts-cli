#if os(macOS)
import Foundation

struct BotEmail: Identifiable {
    let id: String // R2 key
    let key: String
    let from: String
    let subject: String
    let receivedAt: String
    let size: Int
    let originalSender: String?
    let direction: String? // "notification", "outbound", nil (inbound)

    var displayFrom: String {
        originalSender ?? from
    }

    var isInbound: Bool {
        direction == nil && originalSender == nil
    }

    var isNotification: Bool {
        direction == "notification"
    }

    var isOutbound: Bool {
        direction == "outbound"
    }

    var formattedDate: String {
        // Parse ISO date and format nicely
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: receivedAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: receivedAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return receivedAt
    }
}

@MainActor
class BotInboxService: ObservableObject {
    @Published var emails: [BotEmail] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedEmailContent: String?

    // Cloudflare Worker URL
    private var workerURL: String {
        ProcessInfo.processInfo.environment["BOT_WORKER_URL"]
            ?? "https://bot-email-worker.jose-afd.workers.dev"
    }

    private var apiToken: String? {
        // Try env var first, then keychain
        if let env = ProcessInfo.processInfo.environment["BOT_API_TOKEN"], !env.isEmpty {
            return env
        }
        return loadKeychainToken()
    }

    private func loadKeychainToken() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "parts-cli", "-a", "bot-api-token", "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return token?.isEmpty == false ? token : nil
        } catch {
            return nil
        }
    }

    func fetchEmails() async {
        isLoading = true
        error = nil

        guard let token = apiToken else {
            error = "BOT_API_TOKEN not set. Export it or add to environment."
            isLoading = false
            return
        }

        guard let url = URL(string: "\(workerURL)/emails?prefix=emails/") else {
            error = "Invalid worker URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                error = "Invalid response"
                isLoading = false
                return
            }

            if http.statusCode == 401 {
                error = "Unauthorized — check BOT_API_TOKEN"
                isLoading = false
                return
            }

            guard http.statusCode == 200 else {
                error = "HTTP \(http.statusCode)"
                isLoading = false
                return
            }

            guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                error = "Invalid JSON response"
                isLoading = false
                return
            }

            emails = items.compactMap { item in
                guard let key = item["key"] as? String else { return nil }
                // Custom metadata may or may not be present depending on R2 list behavior
                let from = item["from"] as? String ?? ""
                let subject = item["subject"] as? String ?? ""
                let uploaded = item["uploaded"] as? String ?? ""

                // Derive direction from key path pattern
                let direction: String?
                if key.contains("notif-") { direction = "notification" }
                else if key.contains("sent-") { direction = "outbound" }
                else { direction = nil }

                // Extract a readable name from the key
                let filename = URL(fileURLWithPath: key).lastPathComponent
                let displaySubject = subject.isEmpty ? filename : subject

                return BotEmail(
                    id: key,
                    key: key,
                    from: from,
                    subject: displaySubject,
                    receivedAt: item["receivedAt"] as? String ?? uploaded,
                    size: item["size"] as? Int ?? 0,
                    originalSender: item["originalSender"] as? String,
                    direction: direction
                )
            }.sorted { $0.receivedAt > $1.receivedAt }

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func fetchEmailContent(key: String) async {
        guard let token = apiToken else { return }
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        guard let url = URL(string: "\(workerURL)/email/\(encoded)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            selectedEmailContent = String(data: data, encoding: .utf8) ?? "(binary content)"
        } catch {
            selectedEmailContent = "Error: \(error.localizedDescription)"
        }
    }

    func replyToEmail(key: String, text: String) async -> Bool {
        guard let token = apiToken else { return false }
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        guard let url = URL(string: "\(workerURL)/email/\(encoded)/reply") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
#endif
