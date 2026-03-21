import SwiftUI

struct FELDetailView: View {
    @EnvironmentObject var appState: AppState

    @State private var readAddress: String = "0x11000"
    @State private var readLength: String = "256"
    @State private var readData: Data?
    @State private var readBaseAddr: UInt32 = 0

    @State private var isBooting = false
    @State private var bootError: String?
    @State private var isReading = false
    @State private var readError: String?

    @State private var splURL: URL?
    @State private var ubootURL: URL?

    @State private var showSPLPicker = false
    @State private var showUBootPicker = false

    private var felService: FELService { appState.felService }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(felService.connectionState == .connected ? .yellow : .secondary)
                Text("FEL Mode")
                    .font(.headline)
                Spacer()
                connectionBadge
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if felService.connectionState == .connected, let info = felService.deviceInfo {
                // Action buttons bar
                actionBar
                Divider()

                // Main area: info + console
                HSplitView {
                    // Left: device info & details
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            deviceInfoSection(info)
                            memorySection
                            bootSection
                            diagnosticsSection(info)
                        }
                        .padding(12)
                    }
                    .frame(minWidth: 350)

                    // Right: hex dump + console
                    VStack(spacing: 0) {
                        if let data = readData {
                            HexDumpView(data: data, baseAddress: readBaseAddr)
                                .frame(minHeight: 200)
                            Divider()
                        }
                        FELConsoleView(log: felService.log) {
                            felService.log.removeAll()
                        }
                    }
                    .frame(minWidth: 300)
                }
            } else {
                disconnectedView
            }
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: bootPocketPCDefault) {
                Label("Boot PocketPC", systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isBooting)

            Button(action: readMemory) {
                Label("Read Memory", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isReading)

            Button(action: { readScratch() }) {
                Label("Read Scratch", systemImage: "memorychip")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: { readSRAM() }) {
                Label("Read SRAM", systemImage: "text.alignleft")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if isBooting {
                ProgressView()
                    .controlSize(.small)
            }
            if let error = bootError ?? readError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Connection Badge

    @ViewBuilder
    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(badgeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var badgeColor: Color {
        switch felService.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private var badgeText: String {
        switch felService.connectionState {
        case .connected: return felService.deviceInfo?.displayName ?? "Connected"
        case .connecting: return "Connecting..."
        case .error: return "Error"
        case .disconnected: return "Disconnected"
        }
    }

    // MARK: - Device Info

    @ViewBuilder
    private func deviceInfoSection(_ info: FELDeviceInfo) -> some View {
        DisclosureGroup("Device Info") {
            VStack(alignment: .leading, spacing: 4) {
                infoRow("SoC", info.socInfo.name)
                infoRow("SoC ID", "0x\(info.version.socIdHex)")
                infoRow("Protocol", "0x\(String(format: "%x", info.version.protocolVersion))")
                infoRow("Scratchpad", "0x\(String(format: "%x", info.version.scratchpad))")
                if let sid = info.sid {
                    infoRow("SID", sid)
                }
                infoRow("SPL Addr", "0x\(String(format: "%x", info.socInfo.splAddr))")
                infoRow("Scratch Addr", "0x\(String(format: "%x", info.socInfo.scratchAddr))")
                if info.socInfo.rvbarReg != 0 {
                    infoRow("RVBAR", "0x\(String(format: "%x", info.socInfo.rvbarReg))")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Memory Section

    @ViewBuilder
    private var memorySection: some View {
        DisclosureGroup("Memory") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Address:")
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    TextField("0x11000", text: $readAddress)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    Text("Length:")
                        .font(.caption)
                    TextField("256", text: $readLength)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Button(action: readMemory) {
                        Label("Read", systemImage: "arrow.down.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isReading)
                }

                if let error = readError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Boot Section

    @ViewBuilder
    private var bootSection: some View {
        DisclosureGroup("Boot") {
            VStack(alignment: .leading, spacing: 8) {
                // SPL file
                HStack {
                    Text("SPL:")
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    if let url = splURL {
                        Text(url.lastPathComponent)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    } else {
                        Text("No file selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Browse...") { showSPLPicker = true }
                        .font(.caption)
                        .controlSize(.small)
                }

                // U-Boot file
                HStack {
                    Text("U-Boot:")
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    if let url = ubootURL {
                        Text(url.lastPathComponent)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    } else {
                        Text("Optional")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Browse...") { showUBootPicker = true }
                        .font(.caption)
                        .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Button(action: loadSPL) {
                        Label("Load SPL", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(splURL == nil || isBooting)

                    Button(action: bootDevice) {
                        Label("Boot Device", systemImage: "power")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(splURL == nil || isBooting)

                    Button(action: bootPocketPCDefault) {
                        Label("Boot PocketPC", systemImage: "desktopcomputer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(isBooting)
                }

                if isBooting {
                    ProgressView()
                        .controlSize(.small)
                }
                if let error = bootError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .fileImporter(isPresented: $showSPLPicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { splURL = url }
        }
        .fileImporter(isPresented: $showUBootPicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { ubootURL = url }
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private func diagnosticsSection(_ info: FELDeviceInfo) -> some View {
        DisclosureGroup("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: { readScratch() }) {
                        Label("Read Scratch", systemImage: "memorychip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { readSRAM() }) {
                        Label("Read SRAM A", systemImage: "text.alignleft")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Swap Buffers: \(info.socInfo.swapBuffers.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(Array(info.socInfo.swapBuffers.enumerated()), id: \.offset) { _, swap in
                    Text("  buf1=0x\(String(format: "%x", swap.buf1)) buf2=0x\(String(format: "%x", swap.buf2)) size=0x\(String(format: "%x", swap.size))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Disconnected

    @ViewBuilder
    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No FEL device detected")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Power on the Allwinner device without bootable media\nto enter FEL mode (USB boot)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Scan for Device") {
                felService.connect()
            }
            .buttonStyle(.borderedProminent)

            // Console at bottom even when disconnected
            Spacer()
            Divider()
            FELConsoleView(log: felService.log) {
                felService.log.removeAll()
            }
        }
    }

    // MARK: - Actions

    private func parseHexAddress(_ s: String) -> UInt32? {
        let cleaned = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
        return UInt32(cleaned, radix: 16)
    }

    private func readMemory() {
        guard let addr = parseHexAddress(readAddress),
              let len = UInt32(readLength) else {
            readError = "Invalid address or length"
            return
        }
        readError = nil
        isReading = true

        felService.readMemory(address: addr, length: len) { result in
            isReading = false
            switch result {
            case .success(let data):
                readData = data
                readBaseAddr = addr
                felService.appendLog("Read \(data.count) bytes from 0x\(String(format: "%x", addr))")
            case .failure(let error):
                readError = error.localizedDescription
            }
        }
    }

    private func readScratch() {
        guard let info = felService.deviceInfo else { return }
        readAddress = "0x\(String(format: "%x", info.socInfo.scratchAddr))"
        readLength = "256"
        readMemory()
    }

    private func readSRAM() {
        guard let info = felService.deviceInfo else { return }
        let addr = info.socInfo.splAddr > 0 ? info.socInfo.splAddr : UInt32(0)
        readAddress = "0x\(String(format: "%x", addr))"
        readLength = "256"
        readMemory()
    }

    private func loadSPL() {
        guard let url = splURL, let data = try? Data(contentsOf: url) else {
            bootError = "Cannot read SPL file"
            return
        }
        isBooting = true
        bootError = nil

        felService.writeSPL(data: data) { result in
            isBooting = false
            if case .failure(let error) = result {
                bootError = error.localizedDescription
            }
        }
    }

    private func bootDevice() {
        guard let splUrl = splURL, let splData = try? Data(contentsOf: splUrl) else {
            bootError = "Cannot read SPL file"
            return
        }

        var ubootData: Data?
        if let ubootUrl = ubootURL {
            ubootData = try? Data(contentsOf: ubootUrl)
        }

        isBooting = true
        bootError = nil

        felService.bootPocketPC(splData: splData, ubootData: ubootData) { result in
            isBooting = false
            if case .failure(let error) = result {
                bootError = error.localizedDescription
            }
        }
    }

    private func bootPocketPCDefault() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
        let ubootPath = "\(home)/Work/PocketPC-Uboot/u-boot.bin"

        guard let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else {
            bootError = "Cannot read \(splPath)"
            return
        }

        let ubootData = try? Data(contentsOf: URL(fileURLWithPath: ubootPath))

        isBooting = true
        bootError = nil

        felService.bootPocketPC(splData: splData, ubootData: ubootData) { result in
            isBooting = false
            if case .failure(let error) = result {
                bootError = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
