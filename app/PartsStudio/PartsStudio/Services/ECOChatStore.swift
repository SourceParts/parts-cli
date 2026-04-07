import Foundation

/// Stores chat feedback for ECO documents.
/// Persisted at ~/Work/Consulting/nRF54H20-Main-Board/ECO/.feedback.json
class ECOChatStore: ObservableObject {
    @Published private var chatData: [String: [ECOChatMessage]] = [:]

    private var filePath: URL {
        URL(fileURLWithPath: PartsConfig.shared.ecoPath).appendingPathComponent(".feedback.json")
    }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: filePath) else {
            chatData = [:]
            return
        }
        do {
            let file = try JSONDecoder().decode(ECOChatFile.self, from: data)
            chatData = file.documents
        } catch {
            chatData = [:]
        }
    }

    func save() {
        let file = ECOChatFile(version: 1, documents: chatData)
        guard let data = try? JSONEncoder.prettyPrinted.encode(file) else { return }
        try? data.write(to: filePath, options: .atomic)
    }

    func messages(for docId: String) -> [ECOChatMessage] {
        chatData[docId] ?? []
    }

    func addMessage(for docId: String, text: String) {
        let author = NSUserName()
        let message = ECOChatMessage(author: author, text: text)
        chatData[docId, default: []].append(message)
        save()
    }

    func deleteMessage(for docId: String, messageId: String) {
        chatData[docId]?.removeAll { $0.id == messageId }
        save()
    }

    func clearMessages(for docId: String) {
        chatData[docId] = []
        save()
    }
}
