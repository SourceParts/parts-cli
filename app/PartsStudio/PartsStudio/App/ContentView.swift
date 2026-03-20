import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            DatasheetSidebarView()
        } detail: {
            if let iqc = appState.selectedIQCItem {
                HSplitView {
                    IQCDetailView(item: iqc)
                        .frame(minWidth: 500)

                    ECOChatView(document: ECODocument(id: iqc.code, type: .ecn, title: "IQC Report", severity: "", status: iqc.status, filePath: "", body: ""))
                        .frame(width: 280)
                }
            } else if let eco = appState.selectedECO {
                HSplitView {
                    ECODetailView(document: eco)
                        .frame(minWidth: 500)

                    ECOChatView(document: eco)
                        .frame(width: 280)
                }
            } else if appState.pdfDocument != nil {
                HSplitView {
                    PDFViewerContainer()
                        .frame(minWidth: 500)

                    ConversationPanelView()
                        .frame(width: 280)
                }
            } else {
                QuarterMasterView()
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
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
