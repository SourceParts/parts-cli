import Foundation

struct ECOChatMessage: Codable, Identifiable {
    let id: String
    let author: String
    let text: String
    let timestamp: String

    init(author: String, text: String) {
        self.id = UUID().uuidString
        self.author = author
        self.text = text
        self.timestamp = ISO8601DateFormatter().string(from: Date())
    }
}

struct ECOChatFile: Codable {
    let version: Int
    var documents: [String: [ECOChatMessage]]  // docId -> messages
}
