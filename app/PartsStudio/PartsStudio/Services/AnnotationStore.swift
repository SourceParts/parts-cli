import Foundation

/// Manages JSON sidecar files for annotations next to cached PDFs.
class AnnotationStore: ObservableObject {
    @Published var annotations: [DatasheetAnnotation] = []

    private var currentDatasheet: CachedDatasheet?

    // MARK: - Sidecar path

    private func sidecarPath(for datasheet: CachedDatasheet) -> URL {
        let pdfURL = URL(fileURLWithPath: datasheet.path)
        let name = pdfURL.deletingPathExtension().lastPathComponent
        return pdfURL.deletingLastPathComponent().appendingPathComponent("\(name).annotations.json")
    }

    // MARK: - Load

    func load(for datasheet: CachedDatasheet) {
        currentDatasheet = datasheet
        let path = sidecarPath(for: datasheet)

        guard let data = try? Data(contentsOf: path) else {
            annotations = []
            return
        }

        do {
            let file = try JSONDecoder().decode(AnnotationFile.self, from: data)
            annotations = file.annotations
        } catch {
            annotations = []
        }
    }

    // MARK: - Save

    func save() {
        guard let datasheet = currentDatasheet else { return }
        let path = sidecarPath(for: datasheet)

        let file = AnnotationFile(
            version: 1,
            contentHash: datasheet.contentHash,
            annotations: annotations
        )

        do {
            let data = try JSONEncoder.prettyPrinted.encode(file)
            // Atomic write: tmp then rename (mirrors Go pattern)
            let tmpPath = path.appendingPathExtension("tmp")
            try data.write(to: tmpPath, options: .atomic)
            try FileManager.default.moveItem(at: tmpPath, to: path)
        } catch {
            // Fallback: direct write
            if let data = try? JSONEncoder.prettyPrinted.encode(file) {
                try? data.write(to: path, options: .atomic)
            }
        }
    }

    // MARK: - Mutate

    func addAnnotation(_ annotation: DatasheetAnnotation) {
        annotations.append(annotation)
        save()
    }

    func removeAnnotation(id: String) {
        annotations.removeAll { $0.id == id }
        save()
    }

    func annotationsForPage(_ page: Int) -> [DatasheetAnnotation] {
        annotations.filter { $0.page == page }
    }
}

extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
