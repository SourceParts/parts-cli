import SwiftUI

struct IQCSidebarSection: View {
    @EnvironmentObject var appState: AppState

    private var items: [IQCItem] {
        appState.effectiveIQCItems
    }

    var body: some View {
        ForEach(items) { item in
            IQCItemRow(item: item, isSelected: appState.selectedIQCItem?.id == item.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectedIQCItem = item
                    appState.selectedECO = nil
                    appState.selectedDatasheet = nil
                    appState.selectedAssemblyDoc = nil
                    appState.pdfDocument = nil
                    appState.showFEL = false
                    appState.showUSBMonitor = false
                    appState.showCredits = false
                }
        }
    }
}

struct IQCSidebarSectionHeader: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Label("IQC Reports (\(appState.effectiveIQCItems.count))", systemImage: "checkmark.shield")
                .font(.caption)
                .fontWeight(.semibold)
            Spacer()
            if appState.iqcService.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else if let progress = appState.iqcService.uploadProgress {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(progress)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Calendar view
                Button(action: {
                    appState.showIQCCalendar.toggle()
                    if appState.showIQCCalendar {
                        appState.selectedIQCItem = nil
                        appState.selectedECO = nil
                        appState.selectedDatasheet = nil
                        appState.selectedAssemblyDoc = nil
                        appState.pdfDocument = nil
                        appState.showFEL = false
                    }
                }) {
                    Image(systemName: appState.showIQCCalendar ? "calendar.circle.fill" : "calendar")
                        .font(.caption2)
                        .foregroundStyle(appState.showIQCCalendar ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("IQC timeline calendar")

                // Upload images
                Button(action: {
                    Task { await appState.iqcService.uploadImages() }
                }) {
                    Image(systemName: "photo.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Upload images to IQC ingest")

                // Load local JSON reports
                Button(action: {
                    appState.iqcService.loadLocalReports()
                }) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Load local IQC JSON reports")

                // Open X-ray analysis in JSON viewer
                if let xrayPath = appState.iqcService.xrayAnalysisPath {
                    Button(action: {
                        let doc = AssemblyDocument(
                            id: xrayPath, name: "xray_analysis_results.json",
                            category: "IQC", path: xrayPath, size: 0, revision: "")
                        appState.selectedAssemblyDoc = doc
                        appState.selectedIQCItem = nil
                        appState.selectedECO = nil
                        appState.selectedDatasheet = nil
                        appState.pdfDocument = nil
                    }) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View X-ray analysis results (JSON)")
                }

                // Refresh from API
                Button(action: {
                    Task { await appState.iqcService.fetchItems() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh IQC items from API")
            }
        }
    }
}

// MARK: - Error Banner

struct IQCErrorBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let error = appState.iqcService.error {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button(action: { appState.iqcService.error = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct IQCItemRow: View {
    let item: IQCItem
    var isSelected: Bool = false

    private var badgeColor: Color {
        switch item.status {
        case "accepted": return .green
        case "rejected": return .red
        case "inspected": return .blue
        case "pending_inspection": return .orange
        default: return .gray
        }
    }

    private var statusLabel: String {
        switch item.status {
        case "pending_inspection": return "Pending"
        case "accepted": return "Accepted"
        case "rejected": return "Rejected"
        case "inspected": return "Inspected"
        default: return item.status.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.code)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(statusLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.15))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
            }
            if !item.createdAt.isEmpty {
                Text(item.createdAt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let notes = item.inspectionNotes {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
