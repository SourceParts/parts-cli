import Foundation

struct Comment: Codable, Identifiable {
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

struct ConversationThread: Codable, Identifiable {
    let id: String
    let page: Int
    let anchorX: CGFloat
    let anchorY: CGFloat
    var resolved: Bool
    var comments: [Comment]
    var selectedText: String?  // Text selected from the PDF when creating the thread

    enum CodingKeys: String, CodingKey {
        case id, page, resolved, comments
        case anchorX = "anchor_x"
        case anchorY = "anchor_y"
        case selectedText = "selected_text"
    }

    init(page: Int, anchorX: CGFloat, anchorY: CGFloat, initialComment: Comment, selectedText: String? = nil) {
        self.id = UUID().uuidString
        self.page = page
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.resolved = false
        self.comments = [initialComment]
        self.selectedText = selectedText
    }

    mutating func addReply(author: String, text: String) {
        comments.append(Comment(author: author, text: text))
    }
}

struct ConversationFile: Codable {
    let version: Int
    let contentHash: String
    var threads: [ConversationThread]

    enum CodingKeys: String, CodingKey {
        case version
        case contentHash = "content_hash"
        case threads
    }
}
