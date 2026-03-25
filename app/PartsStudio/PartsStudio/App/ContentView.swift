#if os(macOS)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDevConsole = false

    var body: some View {
        ZStack(alignment: .top) {
        NavigationSplitView {
            DatasheetSidebarView()
        } detail: {
            if appState.showDocuments {
                DocumentEditorView()
            } else if appState.showFEL {
                FELDetailView()
            } else if appState.showESLR {
                ESLRDetailView()
            } else if appState.showBLE {
                BLEView()
            } else if appState.showUSBMonitor {
                USBMonitorView()
            } else if appState.showCredits {
                CreditsView()
            } else if appState.showBotInbox {
                BotInboxView()
            } else if appState.showIQCCalendar {
                IQCCalendarView(items: appState.effectiveIQCItems)
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
            } else if let asmDoc = appState.selectedAssemblyDoc, asmDoc.path.lowercased().hasSuffix(".gbrjob") {
                GerberJobView(filePath: asmDoc.path)
            } else if appState.showPCBEditor {
                PCBEditorView()
            } else if let asmDoc = appState.selectedAssemblyDoc, isGerberFile(asmDoc.path) {
                GerberViewerView(filePaths: gerberFilesInSameDir(asmDoc.path))
            } else if let asmDoc = appState.selectedAssemblyDoc, asmDoc.path.lowercased().hasSuffix(".md") {
                MarkdownFileView(filePath: asmDoc.path)
            } else if let asmDoc = appState.selectedAssemblyDoc, asmDoc.path.lowercased().hasSuffix(".dxf") {
                DXFViewerView(filePath: asmDoc.path)
            } else if let asmDoc = appState.selectedAssemblyDoc, asmDoc.path.lowercased().hasSuffix(".json") {
                JSONViewerView(filePath: asmDoc.path)
            } else if let asmDoc = appState.selectedAssemblyDoc, isSTEPFile(asmDoc.path) {
                STEPViewerView(filePath: asmDoc.path)
            } else if let partNumber = appState.selectedPartNumber {
                PartDetailView(partNumber: partNumber)
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
        .onChange(of: appState.showStripMetadata) { _, newValue in
            if newValue {
                appState.showStripMetadata = false
                PDFExporter.stripMetadata(from: appState.pdfDocument)
            }
        }
        .onChange(of: appState.showExport) { _, newValue in
            if newValue {
                appState.showExport = false
                PDFExporter.exportWithRedactions(from: appState.pdfDocument)
            }
        }
        .onChange(of: appState.showExportAnnotations) { _, newValue in
            if newValue {
                appState.showExportAnnotations = false
                PDFExporter.exportAnnotations(from: appState.annotationStore.annotations)
            }
        }
        .onChange(of: appState.showExportLabels) { _, newValue in
            if newValue {
                appState.showExportLabels = false
                PDFExporter.exportLabels(from: appState.dataLabelStore)
            }
        }
        .onChange(of: appState.showExportPagePNG) { _, newValue in
            if newValue {
                appState.showExportPagePNG = false
                PDFExporter.exportPageAsPNG(from: appState.pdfDocument, pageIndex: appState.currentPage)
            }
        }

            // Dev console overlay — fills entire viewport
            if showDevConsole {
                DevConsoleView(isVisible: $showDevConsole)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        } // ZStack
        .onKeyPress("`") {
            withAnimation(.easeOut(duration: 0.2)) { showDevConsole.toggle() }
            return .handled
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

    private func isGerberFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return isKnownGerberExt(ext)
    }

    private func isSTEPFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "step" || ext == "stp"
    }

    /// Check if a file extension is a known Gerber/drill format (including inner layers g1-g999).
    private func isKnownGerberExt(_ ext: String) -> Bool {
        let fixed: Set<String> = ["gbr", "gtl", "gbl", "gts", "gbs", "gto", "gbo", "gtp", "gbp", "gm1", "gko", "drl", "xln"]
        if fixed.contains(ext) { return true }
        // Inner copper layers: g1, g2, ..., g999
        if ext.hasPrefix("g"), let num = Int(ext.dropFirst()), num >= 1 { return true }
        return false
    }

    private func gerberFilesInSameDir(_ path: String) -> [String] {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [path] }
        return files
            .filter { isKnownGerberExt(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .sorted()
            .map { "\(dir)/\($0)" }
    }

    private func importPDF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let path = url.path
        appState.cacheService.importAndCache(path: path)
        appState.cacheService.reload()
    }
}
#endif
