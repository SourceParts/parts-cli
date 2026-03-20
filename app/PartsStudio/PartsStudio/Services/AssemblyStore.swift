import Foundation

struct AssemblyDocument: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String  // "BOM", "Assembly", "Fab", "Schematic"
    let path: String
    let size: Int64
    let revision: String  // "EVT1", "EVT2", etc.

    var icon: String {
        switch category {
        case "BOM": return "tablecells"
        case "Assembly": return "square.on.square.dashed"
        case "Fab": return "cpu"
        case "Schematic": return "waveform.path.ecg"
        default: return "doc"
        }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

@MainActor
class AssemblyStore: ObservableObject {
    @Published var documents: [AssemblyDocument] = []

    private let projectPath: String

    init() {
        self.projectPath = PartsConfig.shared.projectPath
        loadDocuments()
    }

    func loadDocuments() {
        let fm = FileManager.default
        var results: [AssemblyDocument] = []

        // BOM files
        scanDirectory("\(projectPath)/BOM", category: "BOM", fm: fm, results: &results)

        // Assembly PDFs (from fab release and pdf_output)
        scanDirectory("\(projectPath)/PCB/EVT2/fab_release/assembly", category: "Assembly", fm: fm, results: &results)
        scanPDFs("\(projectPath)/PCB/EVT2/pdf_output", keyword: "assembly", category: "Assembly", fm: fm, results: &results)

        // Fab files
        scanDirectory("\(projectPath)/PCB/EVT2/fab_release", category: "Fab", fm: fm, results: &results, excludeSubdirs: true)

        // Schematic PDFs
        scanPDFs("\(projectPath)/PCB/EVT2/pdf_output", keyword: "schematic", category: "Schematic", fm: fm, results: &results)

        // Sort by category then name
        results.sort { a, b in
            if a.category != b.category {
                let order = ["BOM", "Assembly", "Schematic", "Fab"]
                return (order.firstIndex(of: a.category) ?? 99) < (order.firstIndex(of: b.category) ?? 99)
            }
            return a.name < b.name
        }

        documents = results
    }

    private func scanDirectory(_ path: String, category: String, fm: FileManager, results: inout [AssemblyDocument], excludeSubdirs: Bool = false) {
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return }
        for file in files {
            let fullPath = "\(path)/\(file)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            if isDir.boolValue && excludeSubdirs { continue }
            if isDir.boolValue { continue }
            if file.hasPrefix(".") { continue }

            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let size = attrs?[.size] as? Int64 ?? 0
            let revision = fullPath.contains("EVT2") ? "EVT2" : fullPath.contains("EVT1") ? "EVT1" : ""

            results.append(AssemblyDocument(
                id: fullPath,
                name: file,
                category: category,
                path: fullPath,
                size: size,
                revision: revision
            ))
        }
    }

    private func scanPDFs(_ path: String, keyword: String, category: String, fm: FileManager, results: inout [AssemblyDocument]) {
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return }
        for file in files {
            guard file.lowercased().contains(keyword), file.lowercased().hasSuffix(".pdf") else { continue }
            let fullPath = "\(path)/\(file)"
            // Skip if already added
            if results.contains(where: { $0.path == fullPath }) { continue }

            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let size = attrs?[.size] as? Int64 ?? 0

            results.append(AssemblyDocument(
                id: fullPath,
                name: file,
                category: category,
                path: fullPath,
                size: size,
                revision: fullPath.contains("EVT2") ? "EVT2" : "EVT1"
            ))
        }
    }
}
