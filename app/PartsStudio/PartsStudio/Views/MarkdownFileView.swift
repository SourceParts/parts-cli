import SwiftUI

struct MarkdownFileView: View {
    let filePath: String
    @State private var content: String?

    var body: some View {
        Group {
            if let md = content {
                MarkdownView(markdown: md)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadFile() }
        .onChange(of: filePath) { loadFile() }
    }

    private func loadFile() {
        content = try? String(contentsOfFile: filePath, encoding: .utf8)
    }
}
