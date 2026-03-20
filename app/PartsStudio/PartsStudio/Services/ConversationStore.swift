import Foundation

/// Manages JSON sidecar files for conversation threads next to cached PDFs.
class ConversationStore: ObservableObject {
    @Published var threads: [ConversationThread] = []

    private var currentDatasheet: CachedDatasheet?

    // MARK: - Sidecar path

    private func sidecarPath(for datasheet: CachedDatasheet) -> URL {
        let pdfURL = URL(fileURLWithPath: datasheet.path)
        let name = pdfURL.deletingPathExtension().lastPathComponent
        return pdfURL.deletingLastPathComponent().appendingPathComponent("\(name).conversations.json")
    }

    // MARK: - Load

    func load(for datasheet: CachedDatasheet) {
        currentDatasheet = datasheet
        let path = sidecarPath(for: datasheet)

        guard let data = try? Data(contentsOf: path) else {
            threads = []
            return
        }

        do {
            let file = try JSONDecoder().decode(ConversationFile.self, from: data)
            threads = file.threads
        } catch {
            threads = []
        }
    }

    // MARK: - Save

    func save() {
        guard let datasheet = currentDatasheet else { return }
        let path = sidecarPath(for: datasheet)

        let file = ConversationFile(
            version: 1,
            contentHash: datasheet.contentHash,
            threads: threads
        )

        do {
            let data = try JSONEncoder.prettyPrinted.encode(file)
            try data.write(to: path, options: .atomic)
        } catch {
            // silent fail for now
        }
    }

    // MARK: - Mutate

    func addThread(page: Int, anchorX: CGFloat, anchorY: CGFloat, text: String) {
        let author = NSUserName()
        let comment = Comment(author: author, text: text)
        let thread = ConversationThread(page: page, anchorX: anchorX, anchorY: anchorY, initialComment: comment)
        threads.append(thread)
        save()
    }

    func addReply(threadId: String, text: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        let author = NSUserName()
        threads[index].addReply(author: author, text: text)
        save()
    }

    func resolveThread(id: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].resolved = true
        save()
    }

    func deleteThread(id: String) {
        threads.removeAll { $0.id == id }
        save()
    }

    func threadsForPage(_ page: Int) -> [ConversationThread] {
        threads.filter { $0.page == page }
    }
}
