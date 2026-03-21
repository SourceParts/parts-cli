import SwiftUI

struct FELSidebarSection: View {
    @EnvironmentObject var appState: AppState

    private var felService: FELService { appState.felService }

    private var statusColor: Color {
        switch felService.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private var statusText: String {
        switch felService.connectionState {
        case .connected:
            return felService.deviceInfo?.displayName ?? "Connected"
        case .connecting:
            return "Connecting..."
        case .error:
            return "Error"
        case .disconnected:
            return "No Device"
        }
    }

    var body: some View {
        Button(action: {
            appState.showFEL = true
            appState.selectedDatasheet = nil
            appState.selectedECO = nil
            appState.selectedIQCItem = nil
            appState.selectedAssemblyDoc = nil
            appState.showCredits = false
            appState.showUSBMonitor = false
            appState.pdfDocument = nil
        }) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Text("FEL")
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(appState.showFEL ? Color.accentColor : .primary)
    }
}
