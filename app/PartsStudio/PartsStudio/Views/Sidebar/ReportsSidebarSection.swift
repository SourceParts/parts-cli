import SwiftUI

struct ReportsSidebarSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ForEach(appState.reportsStore.documents) { doc in
            ReportDocumentRow(document: doc)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectedReport = doc
                    appState.lastSelectedReportId = doc.id
                    appState.selectedDatasheet = nil
                    appState.selectedECO = nil
                    appState.selectedIQCItem = nil
                    appState.selectedAssemblyDoc = nil
                    appState.pdfDocument = nil
                    appState.showFEL = false
                    appState.showUSBMonitor = false
                    appState.showCredits = false
                }
                .contextMenu {
                    Button("Reveal in Finder") {
                        #if os(macOS)
                        NSWorkspace.shared.selectFile(doc.filePath, inFileViewerRootedAtPath: "")
                        #endif
                    }
                    Button("Copy Path") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(doc.filePath, forType: .string)
                        #endif
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(appState.selectedReport?.id == doc.id ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
    }
}

struct ReportDocumentRow: View {
    let document: ReportDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(document.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer()

                if !document.date.isEmpty {
                    Text(document.date)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
