import Foundation

struct DatasheetAlias: Codable {
    let contentHash: String
    let filename: String
    let created: String

    enum CodingKeys: String, CodingKey {
        case contentHash = "content_hash"
        case filename
        case created
    }
}

struct CachedDatasheet: Identifiable, Hashable {
    let id: String  // contentHash/filename
    let contentHash: String
    let filename: String
    let path: String
    let size: Int64
    var aliases: [String]

    init(contentHash: String, filename: String, path: String, size: Int64, aliases: [String] = []) {
        self.id = "\(contentHash)/\(filename)"
        self.contentHash = contentHash
        self.filename = filename
        self.path = path
        self.size = size
        self.aliases = aliases
    }

    var displayName: String {
        aliases.first ?? filename
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
