import SwiftUI

struct ReportDetailView: View {
    let document: ReportDocument

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.headline)
                    if !document.date.isEmpty {
                        Text(document.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                #if os(macOS)
                Button { NotificationCenter.default.post(name: .markdownZoomOut, object: nil) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless).help("Zoom Out")

                Button { NotificationCenter.default.post(name: .markdownZoomReset, object: nil) } label: {
                    Image(systemName: "1.magnifyingglass")
                }
                .buttonStyle(.borderless).help("Reset Zoom")

                Button { NotificationCenter.default.post(name: .markdownZoomIn, object: nil) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless).help("Zoom In")

                Divider().frame(height: 16)

                Button {
                    NSWorkspace.shared.selectFile(document.filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                #endif
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Markdown content — reuse the same MarkdownView from ECODetailView
            MarkdownView(markdown: document.body)
        }
    }
}
