import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            DatasheetSidebarView()
        } detail: {
            if appState.pdfDocument != nil {
                HSplitView {
                    PDFViewerContainer()
                        .frame(minWidth: 500)

                    ConversationPanelView()
                        .frame(width: 280)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a datasheet from the sidebar")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("or import a PDF with Cmd+I")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .fileImporter(
            isPresented: $appState.showImportPanel,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importPDF(url: url)
            }
        }
    }

    private func importPDF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let path = url.path
        appState.cacheService.importAndCache(path: path)
        appState.cacheService.reload()
    }
}
