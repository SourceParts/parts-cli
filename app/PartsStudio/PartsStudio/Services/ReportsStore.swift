import Foundation
import Combine

@MainActor
class ReportsStore: ObservableObject {
    @Published var documents: [ReportDocument] = []

    private let directoryPath: String

    init(directoryPath: String? = nil) {
        self.directoryPath = directoryPath ?? PartsConfig.shared.reportsPath
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
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            documents = []
            return
        }

        let mdFiles = files.filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }

        var docs: [ReportDocument] = []
        for file in mdFiles {
            if let doc = parseReport(at: file) {
                docs.append(doc)
            }
        }

        // Sort by filename descending (most recent date-stamped reports first)
        docs.sort { a, b in
            a.filePath > b.filePath
        }

        documents = docs
    }

    private func parseReport(at url: URL) -> ReportDocument? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let filename = url.deletingPathExtension().lastPathComponent

        // Extract title from first markdown heading
        var title = filename
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                title = String(trimmed.dropFirst(2))
                break
            }
        }

        // Extract date from filename (e.g., _20260325) or fallback to file mod date
        var date = ""
        if let range = filename.range(of: #"\d{8}"#, options: .regularExpression) {
            let dateStr = String(filename[range])
            let y = dateStr.prefix(4)
            let m = dateStr.dropFirst(4).prefix(2)
            let d = dateStr.suffix(2)
            date = "\(y)-\(m)-\(d)"
        }

        return ReportDocument(
            id: filename,
            title: title,
            filePath: url.path,
            date: date,
            body: content
        )
    }
}
