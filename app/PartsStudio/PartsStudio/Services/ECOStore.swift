import Foundation
import Combine

@MainActor
class ECOStore: ObservableObject {
    @Published var documents: [ECODocument] = []

    static var defaultECOPath: URL {
        URL(fileURLWithPath: PartsConfig.shared.ecoPath)
    }

    private let directoryPath: String

    init(directoryPath: String? = nil) {
        if let directoryPath = directoryPath {
            self.directoryPath = directoryPath
        } else {
            self.directoryPath = PartsConfig.shared.ecoPath
        }
        loadDocuments()
    }

    func loadDocuments() {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directoryPath)

        guard fm.fileExists(atPath: directoryPath) else {
            documents = []
            return
        }

        guard let files = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            documents = []
            return
        }

        let mdFiles = files.filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }

        var docs: [ECODocument] = []
        for file in mdFiles {
            if let doc = parseDocument(at: file) {
                docs.append(doc)
            }
        }

        // Sort: ECOs first, then ECRs, then ECNs
        // Within each group: by id number descending
        docs.sort { a, b in
            let typeOrder: [ECODocType: Int] = [.eco: 0, .ecr: 1, .ecn: 2]
            let aOrder = typeOrder[a.type] ?? 3
            let bOrder = typeOrder[b.type] ?? 3
            if aOrder != bOrder { return aOrder < bOrder }
            return extractNumber(from: a.id) > extractNumber(from: b.id)
        }

        documents = docs
    }

    private func parseDocument(at url: URL) -> ECODocument? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let (frontmatter, body) = parseFrontmatter(content)
        guard !frontmatter.isEmpty else { return nil }

        let id = frontmatter["id"] ?? url.deletingPathExtension().lastPathComponent
        let title = frontmatter["title"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
        let severity = frontmatter["severity"] ?? ""
        let status = frontmatter["status"] ?? ""

        let type: ECODocType
        if let typeStr = frontmatter["id"]?.prefix(3).uppercased() {
            switch typeStr {
            case "ECO": type = .eco
            case "ECR": type = .ecr
            default: type = .ecn
            }
        } else {
            type = .ecn
        }

        return ECODocument(
            id: id,
            type: type,
            title: title,
            severity: severity,
            status: status,
            filePath: url.path,
            body: body
        )
    }

    private func parseFrontmatter(_ content: String) -> (fields: [String: String], body: String) {
        let delimiter = "---"
        let lines = content.components(separatedBy: "\n")

        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == delimiter else {
            return ([:], content)
        }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == delimiter {
                endIndex = i
                break
            }
        }

        guard let end = endIndex else { return ([:], content) }

        var fields: [String: String] = [:]
        for i in 1..<end {
            let line = lines[i]
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        let bodyLines = Array(lines[(end + 1)...])
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (fields, body)
    }

    private func extractNumber(from id: String) -> Int {
        // Extract numeric portion from IDs like "ECN-027", "ECR-001", "ECN-002a"
        let parts = id.split(separator: "-")
        guard parts.count >= 2 else { return 0 }
        let numStr = parts[1].filter { $0.isNumber }
        return Int(numStr) ?? 0
    }
}
