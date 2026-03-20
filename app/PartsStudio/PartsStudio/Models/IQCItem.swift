import Foundation

struct IQCItem: Identifiable, Codable {
    let id: String        // SP-XXXXXX code
    let code: String
    let status: String    // received, pending_inspection, inspected, accepted, rejected
    let createdAt: String
    var images: [IQCImage]
    var inspectionNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, code, status, images
        case createdAt = "created_at"
        case inspectionNotes = "inspection_notes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        id = code
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        images = try container.decodeIfPresent([IQCImage].self, forKey: .images) ?? []
        inspectionNotes = try container.decodeIfPresent(String.self, forKey: .inspectionNotes)
    }

    /// Memberwise initializer for creating sample data.
    init(code: String, status: String, createdAt: String, images: [IQCImage] = [], inspectionNotes: String? = nil) {
        self.id = code
        self.code = code
        self.status = status
        self.createdAt = createdAt
        self.images = images
        self.inspectionNotes = inspectionNotes
    }

    var statusColor: String {
        switch status {
        case "accepted": return "green"
        case "rejected": return "red"
        case "inspected": return "blue"
        case "pending_inspection": return "orange"
        default: return "gray"
        }
    }
}

struct IQCImage: Identifiable, Codable {
    let id: String
    let url: String
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, url
        case thumbnailUrl = "thumbnail_url"
    }
}
