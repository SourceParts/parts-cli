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
                    appState.pdfDocument = nil
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
            } else {
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
