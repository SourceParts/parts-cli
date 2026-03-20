import Foundation

/// Manages JSON sidecar files for data labels next to cached PDFs.
class DataLabelStore: ObservableObject {
    @Published var labels: [DataLabel] = []

    private var currentDatasheet: CachedDatasheet?

    // MARK: - Sidecar path

    private func sidecarPath(for datasheet: CachedDatasheet) -> URL {
        let pdfURL = URL(fileURLWithPath: datasheet.path)
        let name = pdfURL.deletingPathExtension().lastPathComponent
        return pdfURL.deletingLastPathComponent().appendingPathComponent("\(name).labels.json")
    }

    // MARK: - Load

    func load(for datasheet: CachedDatasheet) {
        currentDatasheet = datasheet
        let path = sidecarPath(for: datasheet)

        guard let data = try? Data(contentsOf: path) else {
            labels = []
            return
        }

        do {
            let file = try JSONDecoder().decode(DataLabelsFile.self, from: data)
            labels = file.labels
        } catch {
            labels = []
        }
    }

    // MARK: - Save

    func save() {
        guard let datasheet = currentDatasheet else { return }
        let path = sidecarPath(for: datasheet)

        let file = DataLabelsFile(
            version: 1,
            contentHash: datasheet.contentHash,
            labels: labels
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

    func addLabel(_ label: DataLabel) {
        labels.append(label)
        save()
    }

    func removeLabel(id: String) {
        labels.removeAll { $0.id == id }
        save()
    }

    func labelsForPage(_ page: Int) -> [DataLabel] {
        labels.filter { $0.page == page }
    }
}
