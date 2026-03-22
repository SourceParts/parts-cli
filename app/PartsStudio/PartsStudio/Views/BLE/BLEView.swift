import SwiftUI

struct BLEView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HSplitView {
            // Left: device list + controls
            BLEDeviceListView(bleService: appState.bleService)
                .frame(minWidth: 280, idealWidth: 320)

            // Right: console log
            BLEConsoleView(bleService: appState.bleService)
                .frame(minWidth: 400)
        }
        .navigationTitle("Bluetooth")
    }
}

// MARK: - Device List

struct BLEDeviceListView: View {
    @ObservedObject var bleService: BLEService
    @State private var selectedDevice: BLEDevice?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                Text("BLE Devices")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Scan button
            HStack {
                if bleService.state == .scanning {
                    Button("Stop Scan") { bleService.stopScan() }
                        .buttonStyle(.bordered)
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Scan") { bleService.startScan() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if bleService.connectedDevice != nil {
                    Button("Disconnect") { bleService.disconnect() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
            .padding(8)

            Divider()

            // Device list
            if bleService.devices.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bluetooth")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                    Text("Press Scan to search")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List(bleService.devices, selection: $selectedDevice) { device in
                    BLEDeviceRow(device: device, isConnected: device.id == bleService.connectedDevice?.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            bleService.connect(device: device)
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch bleService.state {
        case .disconnected:
            Label("Off", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .scanning:
            Label("Scanning", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .connecting:
            Label("Connecting", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
        case .connected:
            Label("Connected", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Device Row

struct BLEDeviceRow: View {
    let device: BLEDevice
    let isConnected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(device.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(isConnected ? .bold : .regular)
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text(device.id.uuidString.prefix(8).lowercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            rssiIndicator
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var rssiIndicator: some View {
        let bars = rssiToBars(device.rssi)
        HStack(spacing: 1) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? .green : Color.secondary.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
        Text("\(device.rssi)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 32, alignment: .trailing)
    }

    private func rssiToBars(_ rssi: Int) -> Int {
        if rssi >= -50 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -80 { return 2 }
        if rssi >= -95 { return 1 }
        return 0
    }
}

// MARK: - Console

struct BLEConsoleView: View {
    @ObservedObject var bleService: BLEService
    @State private var command: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal")
                Text("BLE Console")
                    .font(.headline)
                Spacer()
                Button(action: { bleService.log.removeAll() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear log")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(bleService.log.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(">") ? .blue : .primary)
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: bleService.log.count) { _, _ in
                    if let last = bleService.log.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Send command...", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { sendCommand() }
                    .disabled(bleService.state != .connected)

                Button("Send") { sendCommand() }
                    .buttonStyle(.borderedProminent)
                    .disabled(bleService.state != .connected || command.isEmpty)
            }
            .padding(8)
        }
    }

    private func sendCommand() {
        guard !command.isEmpty else { return }
        bleService.send(command)
        command = ""
    }
}
