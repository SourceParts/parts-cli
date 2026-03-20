import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            DatasheetSidebarView()
        } detail: {
            if appState.showCredits {
                CreditsView()
            } else if let iqc = appState.selectedIQCItem {
                detailWithPanel {
                    IQCDetailView(item: iqc)
                } panel: {
                    ECOChatView(document: ECODocument(id: iqc.code, type: .ecn, title: "IQC Report", severity: "", status: iqc.status, filePath: "", body: ""))
                }
            } else if let eco = appState.selectedECO {
                detailWithPanel {
                    ECODetailView(document: eco)
                } panel: {
                    ECOChatView(document: eco)
                }
            } else if let asmDoc = appState.selectedAssemblyDoc, asmDoc.path.lowercased().hasSuffix(".csv") {
                CSVViewerView(filePath: asmDoc.path)
            } else if appState.pdfDocument != nil {
                detailWithPanel {
                    PDFViewerContainer()
                } panel: {
                    ConversationPanelView()
                }
            } else {
                PartsQView()
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

    @ViewBuilder
    private func detailWithPanel<Detail: View, Panel: View>(
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder panel: () -> Panel
    ) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                detail()
            }
            .frame(minWidth: 500)

            if appState.showRightPanel {
                VStack(spacing: 0) {
                    // Collapse button at top of panel
                    HStack {
                        Spacer()
                        Button(action: { appState.showRightPanel = false }) {
                            Image(systemName: "sidebar.trailing")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Hide panel (Cmd+.)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    panel()
                }
                .frame(width: 280)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { appState.showRightPanel.toggle() }) {
                    Image(systemName: appState.showRightPanel ? "sidebar.trailing" : "sidebar.trailing")
                        .symbolVariant(appState.showRightPanel ? .none : .slash)
                }
                .help(appState.showRightPanel ? "Hide threads panel" : "Show threads panel")
                .keyboardShortcut(".", modifiers: [.command])
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
