import SwiftUI

struct ECOSidebarSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ForEach(appState.ecoStore.documents) { doc in
            ECODocumentRow(document: doc)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectedECO = doc
                    appState.selectedDatasheet = nil
                    appState.selectedIQCItem = nil
                    appState.selectedAssemblyDoc = nil
                    appState.pdfDocument = nil
                    appState.showFEL = false
                    appState.showUSBMonitor = false
                    appState.showCredits = false
                }
                .contextMenu {
                    Button("Copy ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(doc.id, forType: .string)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(doc.filePath, inFileViewerRootedAtPath: "")
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(doc.filePath, forType: .string)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(appState.selectedECO?.id == doc.id ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
    }
}

struct ECODocumentRow: View {
    let document: ECODocument

    private var typeColor: Color {
        switch document.type {
        case .eco: return .purple
        case .ecr: return .blue
        case .ecn: return .teal
        }
    }

    private var statusColor: Color {
        switch document.status.uppercased() {
        case "OPEN": return .green
        case "CLOSED": return .gray
        case "IN-REVIEW", "IN REVIEW", "REVIEW": return .orange
        case "IMPLEMENTED": return .blue
        case "REJECTED": return .red
        case "DEFERRED": return .yellow
        default: return .secondary
        }
    }

    private var severityColor: Color {
        switch document.severity.uppercased() {
        case "CRITICAL": return .red
        case "HIGH": return .orange
        case "MEDIUM": return .yellow
        case "LOW": return .green
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                // Type badge
                Text(document.type.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(typeColor.opacity(0.2))
                    .foregroundStyle(typeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(document.id)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                // Severity badge (only if severity is set)
                if !document.severity.isEmpty {
                    Text(document.severity)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(severityColor.opacity(0.15))
                        .foregroundStyle(severityColor)
                        .clipShape(Capsule())
                }
            }

            Text(document.title)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(document.status)
                .font(.system(size: 8, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}
