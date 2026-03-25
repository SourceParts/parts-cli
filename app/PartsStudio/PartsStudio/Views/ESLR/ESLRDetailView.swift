#if os(macOS)
import SwiftUI

enum ESLRTab: String, CaseIterable {
    case info = "Info"
    case console = "Console"
    case wifi = "WiFi"

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .console: return "terminal"
        case .wifi: return "wifi"
        }
    }
}

struct ESLRDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ESLRTab = .info
    @State private var commandInput = ""

    private var service: ESLRService { appState.eslrService }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider()

            // Tab bar
            HStack(spacing: 0) {
                ForEach(ESLRTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Tab content
            switch selectedTab {
            case .info:
                infoTab
            case .console:
                consoleTab
            case .wifi:
                wifiTab
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(service.connectionState == .connected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.deviceInfo?.displayName ?? "ESLR Radio")
                    .font(.headline)

                if let info = service.deviceInfo {
                    Text(info.firmwareVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(service.connectionState.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let info = service.deviceInfo, info.variant != .unknown {
                Text(info.variant.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(variantColor(info.variant).opacity(0.2))
                    .foregroundStyle(variantColor(info.variant))
                    .cornerRadius(8)
            }

            if service.connectionState == .disconnected {
                Button("Connect") { service.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if service.connectionState == .connected {
                Button("Disconnect") { service.disconnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func variantColor(_ variant: ESLRVariant) -> Color {
        switch variant {
        case .threadstone: return .blue
        case .bridgestone: return .orange
        case .firestone: return .red
        case .unknown: return .secondary
        }
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        ScrollView {
            if let info = service.deviceInfo {
                VStack(alignment: .leading, spacing: 16) {
                    infoSection("Device", items: [
                        ("Firmware", info.firmwareVersion),
                        ("Variant", info.variant.rawValue),
                        ("Chip", "ESP32-S3 rev \(info.chipRevision)"),
                        ("Cores", "\(info.cores)"),
                        ("Flash", info.flashSize),
                    ])

                    infoSection("Network", items: [
                        ("WiFi MAC", info.wifiMAC),
                        ("BLE Name", info.bleName),
                    ])

                    infoSection("Memory", items: [
                        ("Free Heap", formatBytes(info.freeHeap)),
                        ("PSRAM", formatBytes(info.psram)),
                    ])

                    infoSection("Connection", items: [
                        ("Serial Port", info.serialPort),
                        ("Baud Rate", "115200"),
                    ])

                    // Quick actions
                    HStack(spacing: 8) {
                        actionButton("LED On", icon: "lightbulb.fill") { service.sendRaw("led on") }
                        actionButton("LED Off", icon: "lightbulb") { service.sendRaw("led off") }
                        actionButton("Ping", icon: "waveform") { service.sendRaw("ping") }
                        actionButton("Reset", icon: "arrow.clockwise") { service.sendRaw("reset") }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No ESLR Radio Connected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Connect an ESP32-S3 ESLR radio via CP2102 USB serial")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let port = service.serialPort {
                        Text("Detected: \(port)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Button("Connect") { service.connect() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    @ViewBuilder
    private func infoSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(items, id: \.0) { key, value in
                HStack {
                    Text(key)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(service.connectionState != .connected)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes > 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes > 1000 {
            return String(format: "%.0f KB", Double(bytes) / 1000)
        }
        return "\(bytes) B"
    }

    // MARK: - Console Tab

    private var consoleTab: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(service.log.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(">") ? .green : .primary)
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: service.log.count) { _, _ in
                    if let last = service.log.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Command input
            HStack(spacing: 8) {
                Text("esp32>")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("Command", text: $commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        guard !commandInput.isEmpty else { return }
                        service.sendRaw(commandInput)
                        commandInput = ""
                    }
                    .disabled(service.connectionState != .connected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - WiFi Tab

    private var wifiTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WiFi Networks")
                    .font(.headline)
                Spacer()
                Button(action: {
                    service.sendRaw("scan")
                }) {
                    Label("Scan", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.connectionState != .connected)
            }
            .padding(12)

            Divider()

            ScrollView {
                if service.connectionState != .connected {
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Connect to an ESLR radio to scan WiFi networks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 8) {
                        Text("Send 'scan' command to discover nearby networks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Results will appear in the Console tab")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
        }
    }
}
#endif
