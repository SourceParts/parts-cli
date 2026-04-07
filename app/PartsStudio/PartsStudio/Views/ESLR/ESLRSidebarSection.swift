#if os(macOS)
import SwiftUI

struct ESLRSidebarSection: View {
    @EnvironmentObject var appState: AppState

    private var service: ESLRService { appState.eslrService }

    private var statusColor: Color {
        switch service.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private var statusText: String {
        switch service.connectionState {
        case .connected:
            return service.deviceInfo?.displayName ?? "Connected"
        case .connecting:
            return "Connecting..."
        case .error:
            return "Error"
        case .disconnected:
            return "No Radio"
        }
    }

    var body: some View {
        Button(action: {
            appState.showESLR = true
            appState.showFEL = false
            appState.showBLE = false
            appState.selectedDatasheet = nil
            appState.selectedECO = nil
            appState.selectedIQCItem = nil
            appState.selectedAssemblyDoc = nil
            appState.showCredits = false
            appState.showUSBMonitor = false
            appState.pdfDocument = nil
        }) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(statusColor)

                Text("ESLR")
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
        .foregroundStyle(appState.showESLR ? Color.accentColor : .primary)
    }
}
#endif
