#if os(macOS)
import SwiftUI

enum FELTab: String, CaseIterable {
    case info = "Info"
    case memory = "Memory"
    case boot = "Boot"
    case uboot = "Serial"
    case console = "Console"

    var icon: String {
        switch self {
        case .info: return "cpu"
        case .memory: return "memorychip"
        case .boot: return "power"
        case .uboot: return "terminal.fill"
        case .console: return "terminal"
        }
    }
}

struct FELDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var hasAPIKey: Bool = APIKeychain.loadAPIKey() != nil

    @State private var selectedTab: FELTab = .info
    @State private var readAddress: String = "0x11000"
    @State private var readLength: String = "256"
    @State private var readData: Data?
    @State private var readBaseAddr: UInt32 = 0

    @State private var isBooting = false
    @State private var bootError: String?
    @State private var isReading = false
    @State private var readProgress: Double = 0
    @State private var readError: String?

    @State private var splURL: URL?
    @State private var ubootURL: URL?

    @State private var showSPLPicker = false
    @State private var showUBootPicker = false
    @State private var showAdvancedInfo = false
    @State private var showAPIKeyInfo = false

    // Memory write confirmation
    @State private var pendingWriteAddr: UInt32 = 0
    @State private var pendingWriteData: Data?
    @State private var showWriteConfirmation = false

    private var felService: FELService { appState.felService }

    var body: some View {
        VStack(spacing: 0) {
            if felService.connectionState == .connected, let info = felService.deviceInfo {
                // DevTools toolbar
                devToolsToolbar(info)
                Divider()

                // USB replug banner
                if felService.needsUSBReplug {
                    noticeBanner(
                        icon: "cable.connector",
                        message: "USB reset required — replug device to continue. DRAM init has corrupted the USB PHY state.",
                        color: .orange
                    )
                }

                // Tab content
                switch selectedTab {
                case .info:
                    infoPanel(info)
                case .memory:
                    memoryPanel
                case .boot:
                    bootPanel
                case .uboot:
                    ubootPanel
                case .console:
                    if felService.serialActive {
                        serialConsoleView
                    } else {
                        FELConsoleView(log: felService.log, onClear: {
                            felService.log.removeAll()
                        }, onCommand: { cmd in
                            handleConsoleCommand(cmd)
                        })
                    }
                }
            } else {
                disconnectedView
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Confirm Memory Write", isPresented: $showWriteConfirmation) {
            Button("Write", role: .destructive) {
                guard let bytes = pendingWriteData else { return }
                let addr = pendingWriteAddr
                felService.writeMemory(address: addr, data: bytes) { result in
                    if case .success = result {
                        felService.appendLog("Wrote \(bytes.count) byte(s) @ 0x\(String(format: "%x", addr))")
                        readMemory()
                    }
                }
                pendingWriteData = nil
            }
            Button("Cancel", role: .cancel) {
                pendingWriteData = nil
            }
        } message: {
            Text("Write \(pendingWriteData?.count ?? 0) byte(s) to address 0x\(String(format: "%08x", pendingWriteAddr))?\n\nThis directly modifies device memory and cannot be undone.")
        }
    }

    // MARK: - DevTools Toolbar

    @ViewBuilder
    private func devToolsToolbar(_ info: FELDeviceInfo) -> some View {
        HStack(spacing: 0) {
            // Tabs
            ForEach(FELTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedTab == tab
                        ? Color(nsColor: .textBackgroundColor)
                        : Color.clear)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            }

            // Separator
            Spacer()
                .frame(width: 1)
                .background(Color(nsColor: .separatorColor))
                .padding(.vertical, 4)

            Spacer()

            // Status area (right side)
            if isBooting {
                ProgressView()
                    .controlSize(.mini)
                    .padding(.trailing, 4)
            }
            if let error = bootError ?? readError {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }

            // source.parts account indicator
            HStack(spacing: 3) {
                Image(systemName: "person.fill")
                    .font(.system(size: 8))
                Text(hasAPIKey ? "Connected" : "No Account")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(hasAPIKey ? .green : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((hasAPIKey ? Color.green : Color.secondary).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help(hasAPIKey ? "source.parts API key configured" : "Click for setup info")
            .onTapGesture { if !hasAPIKey { showAPIKeyInfo.toggle() } }
            .popover(isPresented: $showAPIKeyInfo, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key Required")
                        .font(.system(size: 11, weight: .semibold))
                    Text("An API key enables:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("IQC live data", systemImage: "shippingbox")
                        Label("Device sync to source.parts", systemImage: "arrow.triangle.2.circlepath")
                        Label("Datasheet downloads", systemImage: "doc.text")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    Divider()
                    Text("Run: pws auth login")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(width: 200)
            }
            .onAppear { hasAPIKey = APIKeychain.loadAPIKey() != nil }

            // Access tier indicator
            HStack(spacing: 3) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 8))
                Text(appState.userSession.role.displayName)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help("Access tier: \(appState.userSession.role.displayName) — controls FEL permissions")

            // Device lifecycle state
            HStack(spacing: 4) {
                Image(systemName: appState.deviceTracker.state.icon)
                    .font(.system(size: 9))
                Text(appState.deviceTracker.state.displayName(for: appState.userSession.role))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(deviceStateColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(deviceStateColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // SoC badge
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(info.socInfo.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                if let sid = info.sid {
                    Text(String(sid.prefix(8)))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.horizontal, 4)
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Info Panel

    @ViewBuilder
    private func infoPanel(_ info: FELDeviceInfo) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                propRow("SoC", info.socInfo.name)
                propRow("SoC ID", "0x\(info.version.socIdHex)")
                propRow("Protocol", "0x\(String(format: "%04x", info.version.protocolVersion))")
                propRow("Scratchpad", "0x\(String(format: "%08x", info.version.scratchpad))")
                if let sid = info.sid {
                    propRow("SID", sid)
                }
                Divider().padding(.vertical, 2)
                propRow("SPL Address", "0x\(String(format: "%08x", info.socInfo.splAddr))")
                propRow("Scratch Address", "0x\(String(format: "%08x", info.socInfo.scratchAddr))")
                if info.socInfo.rvbarReg != 0 {
                    propRow("RVBAR Register", "0x\(String(format: "%08x", info.socInfo.rvbarReg))")
                }

                // Advanced — collapsed by default
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { showAdvancedInfo.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showAdvancedInfo ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                        Text("Internals")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAdvancedInfo {
                    propRow("Thunk Address", "0x\(String(format: "%08x", info.socInfo.thunkAddr))")
                    propRow("Thunk Size", "0x\(String(format: "%x", info.socInfo.thunkSize))")
                    if info.socInfo.sidBase != 0 {
                        propRow("SID Base", "0x\(String(format: "%08x", info.socInfo.sidBase))")
                    }
                    propRow("L2 Cache Enable", info.socInfo.needsL2EN ? "Yes" : "No")
                    propHeader("Swap Buffers (\(info.socInfo.swapBuffers.count))")
                    ForEach(Array(info.socInfo.swapBuffers.enumerated()), id: \.offset) { i, swap in
                        propRow("  [\(i)]", "0x\(String(format: "%05x", swap.buf1)) \u{2194} 0x\(String(format: "%05x", swap.buf2))  size=0x\(String(format: "%x", swap.size))")
                    }
                }
            }
        }
    }

    // MARK: - Memory Panel

    @ViewBuilder
    private var memoryPanel: some View {
        VStack(spacing: 0) {
            // Address bar
            HStack(spacing: 6) {
                Text("addr")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("0x11000", text: $readAddress)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Text("len")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("256", text: $readLength)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Button(action: readMemory) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 10))
                    Text("Read")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(isReading)

                Divider().frame(height: 14)

                // Quick buttons
                Button(action: { readScratch() }) {
                    Text("Scratch")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { readSRAM() }) {
                    Text("SRAM")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Divider().frame(height: 14)

                // Live watch toggle
                Button(action: { toggleWatch() }) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(felService.watchActive ? .red : .secondary)
                            .frame(width: 6, height: 6)
                        Text(felService.watchActive ? "Stop" : "Live")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(felService.watchActive ? .red : nil)

                Spacer()

                if isReading {
                    ProgressView(value: readProgress)
                        .frame(width: 60)
                        .controlSize(.mini)
                }
                if let error = readError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Hex dump — show live watch data or one-shot read
            if felService.watchActive, let data = felService.watchData {
                HexDumpView(data: data, baseAddress: felService.watchAddress)
            } else if let data = readData {
                HexDumpView(data: data, baseAddress: readBaseAddr) { addr, bytes in
                    pendingWriteAddr = addr
                    pendingWriteData = bytes
                    showWriteConfirmation = true
                }
            } else {
                VStack {
                    Spacer()
                    Text("Enter an address and click Read")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color.black)
            }
        }
        .onKeyPress("q") {
            selectedTab = .console
            return .handled
        }
    }

    // MARK: - Boot Panel

    @ViewBuilder
    private var bootPanel: some View {
        VStack(spacing: 0) {
            // Quick boot bar
            HStack(spacing: 6) {
                Button(action: bootPocketPCDefault) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text("Boot PocketPC")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.mini)
                .disabled(isBooting)

                Divider().frame(height: 14)

                Text("or load custom:")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Custom boot form
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // SPL
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "doc.zipper")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("SPL Binary")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Button("Browse...") { showSPLPicker = true }
                                    .font(.system(size: 10))
                                    .controlSize(.mini)
                            }
                            if let url = splURL {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.green)
                            } else {
                                Text("sunxi-spl.bin (eGON.BT0 format)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // U-Boot
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("U-Boot Image")
                                    .font(.system(size: 11, weight: .medium))
                                Text("optional")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("Browse...") { showUBootPicker = true }
                                    .font(.system(size: 10))
                                    .controlSize(.mini)
                            }
                            if let url = ubootURL {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.green)
                            } else {
                                Text("u-boot.bin (mkimage format, 0x27051956)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button(action: loadSPL) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 10))
                            Text("Load SPL")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(splURL == nil || isBooting)

                        Button(action: bootDevice) {
                            Image(systemName: "power")
                                .font(.system(size: 10))
                            Text("SPL + U-Boot + Boot")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(splURL == nil || isBooting)

                        Spacer()

                        if isBooting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let error = bootError {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                            Text(error)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.red)
                    }
                }
                .padding(12)
            }
        }
        .fileImporter(isPresented: $showSPLPicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { splURL = url }
        }
        .fileImporter(isPresented: $showUBootPicker, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { ubootURL = url }
        }
    }

    // MARK: - Disconnected

    @ViewBuilder
    private var disconnectedView: some View {
        VStack(spacing: 0) {
            // Toolbar even when disconnected
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 10))
                    Text("FEL")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }

                Spacer()

                // source.parts account indicator
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                    Text(hasAPIKey ? "Connected" : "No Account")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(hasAPIKey ? .green : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background((hasAPIKey ? Color.green : Color.secondary).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help(hasAPIKey ? "source.parts API key configured" : "Click for setup info")
                .onTapGesture { if !hasAPIKey { showAPIKeyInfo.toggle() } }
                .onAppear { hasAPIKey = APIKeychain.loadAPIKey() != nil }

                // Access tier indicator
                HStack(spacing: 3) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 8))
                    Text(appState.userSession.role.displayName)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 3))

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("disconnected")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 4)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Heartbeat loss banner
            if felService.heartbeatLost {
                noticeBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: "Device connection lost — heartbeat failed. Check USB cable or power cycle the device.",
                    color: .red
                )
            }

            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "bolt.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("No FEL device")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Power on without bootable media to enter FEL mode")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Button(action: { felService.connect() }) {
                    Text("Scan")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
        }
    }

    // MARK: - Property Row (DevTools style)

    @ViewBuilder
    private func propRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.leading, 8)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Color(nsColor: .separatorColor).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func propHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Notice Banner

    @ViewBuilder
    private func noticeBanner(icon: String, message: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(message)
                .font(.system(size: 10))
                .lineLimit(2)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .overlay(alignment: .bottom) {
            color.opacity(0.3).frame(height: 0.5)
        }
    }

    // MARK: - Console Commands

    private func handleConsoleCommand(_ cmd: String) {
        let parts = cmd.split(separator: " ", maxSplits: 3).map(String.init)
        let command = parts[0].lowercased()

        felService.appendLog("> \(cmd)")

        switch command {
        case "help":
            felService.appendLog("Commands:")
            felService.appendLog("  help                   Show commands")
            felService.appendLog("  status                 Connection state")
            felService.appendLog("  info                   Device info")
            felService.appendLog("  read <addr> [len]      Read memory")
            felService.appendLog("  watch <addr> [len]     Live memory watch")
            felService.appendLog("  stop                   Stop watch")
            felService.appendLog("  scratch                Read scratch memory")
            felService.appendLog("  sram                   Read SRAM A")
            felService.appendLog("  boot                   Full boot (SPL+U-Boot)")
            felService.appendLog("  spl                    Load SPL only (no U-Boot)")
            felService.appendLog("  write-uboot            Write U-Boot to DRAM")
            felService.appendLog("  exec <addr>            Execute at address")
            felService.appendLog("  gpio <port>            Read GPIO port (B-H)")
            felService.appendLog("  gpio <port> <pin> <0|1> Set GPIO pin")
            felService.appendLog("  uart <0-4>             Read UART status")
            felService.appendLog("  reg <addr>             Read 32-bit register")
            felService.appendLog("  i2c scan <bus>         Scan TWI bus (0-2)")
            felService.appendLog("  i2c read <bus> <addr> <reg> [len]")
            felService.appendLog("  i2c write <bus> <addr> <reg> <val>")
            felService.appendLog("  backlight <0-255>      Set LM3630A brightness")
            felService.appendLog("  dump brom              Dump 32KB BROM")
            felService.appendLog("  dump <addr> <len>      Dump memory to file")
            felService.appendLog("  gps                    Start GPS polling (parsed)")
            felService.appendLog("  gps raw                Start GPS raw NMEA output")
            felService.appendLog("  gps stop               Stop GPS polling")
            felService.appendLog("  rak                    RAK4200 version query")
            felService.appendLog("  rak reset              Reset RAK4200 module")
            felService.appendLog("  rak join               Join LoRaWAN network")
            felService.appendLog("  rak send <hex>         Send LoRa data")
            felService.appendLog("  rak <AT cmd>           Send raw AT command")
            felService.appendLog("  lora                   Alias for rak")
            felService.appendLog("  swd [scan|stop|status] Debug probe control")
            felService.appendLog("  voice [start|stop]     Voice recognition")
            felService.appendLog("  voice [direct|natural] Set voice mode")
            felService.appendLog("  sync                   Sync device to source.parts")
            felService.appendLog("  serial                 Connect serial console")
            felService.appendLog("  device                 Show device identity")
            felService.appendLog("  name <name>            Name this device")
            felService.appendLog("  owner <name>           Set device owner")
            felService.appendLog("  clear                  Clear console")
        case "status":
            let state = felService.connectionState.rawValue
            let soc = felService.deviceInfo?.displayName ?? "none"
            felService.appendLog("state: \(state)  soc: \(soc)")
        case "info":
            guard let info = felService.deviceInfo else {
                felService.appendLog("ERROR: No device connected")
                return
            }
            felService.appendLog("SoC: \(info.socInfo.name) (0x\(info.version.socIdHex))")
            felService.appendLog("SID: \(info.sid ?? "reading...")")
            felService.appendLog("SPL: 0x\(String(format: "%08x", info.socInfo.splAddr))  Scratch: 0x\(String(format: "%08x", info.socInfo.scratchAddr))")
        case "read":
            guard parts.count >= 2, let addr = parseHexAddress(parts[1]) else {
                felService.appendLog("ERROR: Usage: read <addr> [length]")
                return
            }
            let len = parts.count >= 3 ? (UInt32(parts[2]) ?? 256) : 256
            readAddress = "0x\(String(format: "%x", addr))"
            readLength = "\(len)"
            selectedTab = .memory
            readMemory()
        case "scratch":
            readScratch()
            selectedTab = .memory
        case "sram":
            readSRAM()
            selectedTab = .memory
        case "watch":
            guard parts.count >= 2, let addr = parseHexAddress(parts[1]) else {
                felService.appendLog("ERROR: Usage: watch <addr> [length]")
                return
            }
            let len = parts.count >= 3 ? (UInt32(parts[2]) ?? 256) : 256
            readAddress = "0x\(String(format: "%x", addr))"
            readLength = "\(len)"
            selectedTab = .memory
            felService.startWatch(address: addr, length: min(len, 4096))
        case "stop":
            felService.stopWatch()
            felService.stopGPS()
        case "spl":
            // Load SPL only — no U-Boot, no auto-exec. Manual control.
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
            guard let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else {
                felService.appendLog("ERROR: Cannot read \(splPath)")
                return
            }
            felService.writeSPL(data: splData) { result in
                switch result {
                case .success: felService.appendLog("SPL loaded. Device will reset to FEL after DRAM init.")
                case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "write-uboot":
            // Write U-Boot to DRAM (requires DRAM to be initialized via SPL first)
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let ubootPath = "\(home)/Work/PocketPC-Uboot/u-boot.bin"
            guard let ubootData = try? Data(contentsOf: URL(fileURLWithPath: ubootPath)) else {
                felService.appendLog("ERROR: Cannot read \(ubootPath)")
                return
            }
            felService.appendLog("Writing U-Boot (\(ubootData.count) bytes) to 0x4a000000...")
            felService.writeMemory(address: 0x4a000000, data: ubootData) { result in
                switch result {
                case .success: felService.appendLog("U-Boot written to 0x4a000000")
                case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "exec":
            guard parts.count >= 2, let addr = parseHexAddress(parts[1]) else {
                felService.appendLog("ERROR: Usage: exec <addr>")
                return
            }
            felService.appendLog("Executing at 0x\(String(format: "%x", addr))...")
            felService.executeAt(address: addr) { result in
                switch result {
                case .success: felService.appendLog("Execution started")
                case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "boot":
            bootPocketPCDefault()
        case "gpio":
            if parts.count == 2 {
                // Read GPIO port
                let portName = parts[1].uppercased()
                guard let portIndex = FELService.gpioPorts.firstIndex(of: portName) else {
                    felService.appendLog("ERROR: Unknown port \(portName). Use B-H.")
                    return
                }
                felService.readGPIOPort(port: portIndex) { result in
                    switch result {
                    case .success(let state):
                        felService.appendLog("GPIO \(portName): data=0x\(String(format: "%08x", state.data))")
                        for pin in 0..<32 {
                            let fn = state.pinFunction(pin)
                            if fn != 7 { // skip disabled pins
                                let val = state.pinValue(pin) ? "1" : "0"
                                felService.appendLog("  P\(portName)\(pin): \(GPIOPortState.functionName(fn)) = \(val)")
                            }
                        }
                    case .failure(let err):
                        felService.appendLog("ERROR: \(err.localizedDescription)")
                    }
                }
            } else if parts.count == 4 {
                // Set GPIO pin
                let portName = parts[1].uppercased()
                guard let portIndex = FELService.gpioPorts.firstIndex(of: portName),
                      let pin = Int(parts[2]),
                      let value = Int(parts[3]) else {
                    felService.appendLog("ERROR: Usage: gpio <port> <pin> <0|1>")
                    return
                }
                // Configure as output first
                felService.configureGPIOPin(port: portIndex, pin: pin, function: 1) { _ in
                    felService.setGPIOPin(port: portIndex, pin: pin, high: value != 0) { result in
                        switch result {
                        case .success:
                            felService.appendLog("P\(portName)\(pin) = \(value)")
                        case .failure(let err):
                            felService.appendLog("ERROR: \(err.localizedDescription)")
                        }
                    }
                }
            } else {
                felService.appendLog("ERROR: Usage: gpio <port> [pin] [0|1]")
            }

        case "uart":
            guard parts.count >= 2, let num = Int(parts[1]) else {
                felService.appendLog("ERROR: Usage: uart <0-4>")
                return
            }
            felService.readUARTStatus(uart: num) { result in
                switch result {
                case .success(let status):
                    felService.appendLog(status.summary)
                case .failure(let err):
                    felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "reg":
            guard parts.count >= 2, let addr = parseHexAddress(parts[1]) else {
                felService.appendLog("ERROR: Usage: reg <addr>")
                return
            }
            felService.readRegister(address: addr) { result in
                switch result {
                case .success(let value):
                    felService.appendLog("0x\(String(format: "%08x", addr)) = 0x\(String(format: "%08x", value))")
                case .failure(let err):
                    felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "i2c":
            guard parts.count >= 2 else {
                felService.appendLog("Usage: i2c scan <bus> | i2c read <bus> <addr> <reg> [len] | i2c write <bus> <addr> <reg> <val>")
                return
            }
            let subCmd = parts[1].lowercased()
            switch subCmd {
            case "scan":
                let bus = parts.count >= 3 ? (Int(parts[2]) ?? 1) : 1
                felService.appendLog("Initializing TWI\(bus)...")
                felService.initTWI(bus: bus) { result in
                    if case .failure(let err) = result {
                        felService.appendLog("ERROR: TWI init failed: \(err.localizedDescription)")
                        return
                    }
                    felService.appendLog("Scanning TWI\(bus) (0x03-0x77)...")
                    felService.i2cScan(bus: bus) { result in
                        switch result {
                        case .success(let addrs):
                            if addrs.isEmpty {
                                felService.appendLog("No devices found on TWI\(bus)")
                            } else {
                                let list = addrs.map { String(format: "0x%02x", $0) }.joined(separator: " ")
                                felService.appendLog("Found \(addrs.count) device(s): \(list)")
                            }
                        case .failure(let err):
                            felService.appendLog("ERROR: \(err.localizedDescription)")
                        }
                    }
                }
            case "read":
                let cmdParts = cmd.split(separator: " ").map(String.init)
                guard cmdParts.count >= 5,
                      let bus = Int(cmdParts[2]),
                      let addrVal = parseHexAddress(cmdParts[3]),
                      let regVal = parseHexAddress(cmdParts[4]) else {
                    felService.appendLog("Usage: i2c read <bus> <addr> <reg> [len]")
                    return
                }
                let addr = UInt8(addrVal & 0x7F)
                let reg = UInt8(regVal & 0xFF)
                let len = cmdParts.count >= 6 ? (Int(cmdParts[5]) ?? 1) : 1
                felService.i2cRead(bus: bus, addr: addr, reg: reg, length: len) { result in
                    switch result {
                    case .success(let data):
                        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                        felService.appendLog("[0x\(String(format: "%02x", addr))] reg 0x\(String(format: "%02x", reg)): \(hex)")
                    case .failure(let err):
                        felService.appendLog("ERROR: \(err.localizedDescription)")
                    }
                }
            case "write":
                let cmdParts = cmd.split(separator: " ").map(String.init)
                guard cmdParts.count >= 6,
                      let bus = Int(cmdParts[2]),
                      let addrVal = parseHexAddress(cmdParts[3]),
                      let regVal = parseHexAddress(cmdParts[4]),
                      let valVal = parseHexAddress(cmdParts[5]) else {
                    felService.appendLog("Usage: i2c write <bus> <addr> <reg> <val>")
                    return
                }
                let addr = UInt8(addrVal & 0x7F)
                let reg = UInt8(regVal & 0xFF)
                let val = UInt8(valVal & 0xFF)
                felService.i2cWrite(bus: bus, addr: addr, reg: reg, data: [val]) { result in
                    switch result {
                    case .success:
                        felService.appendLog("OK: [0x\(String(format: "%02x", addr))] reg 0x\(String(format: "%02x", reg)) = 0x\(String(format: "%02x", val))")
                    case .failure(let err):
                        felService.appendLog("ERROR: \(err.localizedDescription)")
                    }
                }
            default:
                felService.appendLog("Usage: i2c scan <bus> | i2c read <bus> <addr> <reg> [len] | i2c write <bus> <addr> <reg> <val>")
            }

        case "backlight":
            guard parts.count >= 2, let val = UInt8(parts[1]) else {
                felService.appendLog("Usage: backlight <0-255>")
                return
            }
            felService.appendLog("Setting backlight to \(val)...")
            felService.initBacklight(brightness: val) { result in
                switch result {
                case .success:
                    felService.appendLog("Backlight set to \(val)")
                case .failure(let err):
                    felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "gps":
            if parts.count >= 2 && parts[1].lowercased() == "stop" {
                felService.stopGPS()
            } else {
                let raw = parts.count >= 2 && parts[1].lowercased() == "raw"
                felService.startGPS(raw: raw)
            }

        case "rak", "lora":
            if parts.count < 2 {
                felService.appendLog("Querying RAK4200...")
                felService.ensureUART3 { result in
                    if case .failure(let err) = result {
                        felService.appendLog("ERROR: UART3 init failed: \(err.localizedDescription)")
                        return
                    }
                    felService.rakCommand("at+version") { result in
                        switch result {
                        case .success(let response): felService.appendLog("RAK: \(response)")
                        case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                        }
                    }
                }
            } else {
                let subCmd = parts[1].lowercased()
                switch subCmd {
                case "reset":
                    felService.appendLog("Resetting RAK4200...")
                    felService.rakReset { result in
                        switch result {
                        case .success: felService.appendLog("RAK4200 reset complete")
                        case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                        }
                    }
                case "join":
                    felService.ensureUART3 { result in
                        if case .failure(let err) = result { felService.appendLog("ERROR: \(err.localizedDescription)"); return }
                        felService.appendLog("Joining LoRaWAN...")
                        felService.rakCommand("at+join", responseDelay: 5.0) { result in
                            switch result {
                            case .success(let response): felService.appendLog("RAK: \(response)")
                            case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                            }
                        }
                    }
                case "send":
                    guard parts.count >= 3 else {
                        felService.appendLog("Usage: rak send <hex data>")
                        return
                    }
                    let payload = parts[2]
                    felService.ensureUART3 { result in
                        if case .failure(let err) = result { felService.appendLog("ERROR: \(err.localizedDescription)"); return }
                        felService.appendLog("Sending LoRa data...")
                        felService.rakCommand("at+send=lora:2:\(payload)", responseDelay: 2.0) { result in
                            switch result {
                            case .success(let response): felService.appendLog("RAK: \(response)")
                            case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                            }
                        }
                    }
                default:
                    // Raw AT command
                    let atCmd = parts[1...].joined(separator: " ")
                    felService.ensureUART3 { result in
                        if case .failure(let err) = result { felService.appendLog("ERROR: \(err.localizedDescription)"); return }
                        felService.rakCommand(atCmd) { result in
                            switch result {
                            case .success(let response): felService.appendLog("RAK: \(response)")
                            case .failure(let err): felService.appendLog("ERROR: \(err.localizedDescription)")
                            }
                        }
                    }
                }
            }

        case "swd":
            let result = appState.swdProbe.handleCommand(parts)
            felService.appendLog(result)

        case "voice":
            if parts.count >= 2 {
                switch parts[1].lowercased() {
                case "start", "on":
                    appState.voiceService.startListening()
                    felService.appendLog("Voice recognition started (\(appState.voiceService.mode.rawValue) mode)")
                case "stop", "off":
                    appState.voiceService.stopListening()
                    felService.appendLog("Voice recognition stopped")
                case "direct":
                    appState.voiceService.mode = .direct
                    felService.appendLog("Voice mode: direct commands")
                case "natural":
                    appState.voiceService.mode = .natural
                    felService.appendLog("Voice mode: natural language (say 'hey parts')")
                default:
                    felService.appendLog("Usage: voice [start|stop|direct|natural]")
                }
            } else {
                felService.appendLog("Voice: \(appState.voiceService.isListening ? "listening" : "off") (\(appState.voiceService.mode.rawValue) mode)")
            }

        case "esp32", "esp":
            let result = appState.esp32Service.handleCommand(parts)
            felService.appendLog(result)

        case "dump":
            guard parts.count >= 2 else {
                felService.appendLog("Usage: dump brom | dump <addr> <len>")
                return
            }
            let dumpAddr: UInt32
            let dumpLen: UInt32
            let filename: String

            if parts[1].lowercased() == "brom" {
                dumpAddr = 0x00000000
                dumpLen = 0x8000 // 32KB
                filename = "a64-brom.bin"
            } else {
                guard let a = parseHexAddress(parts[1]),
                      parts.count >= 3, let l = UInt32(parts[2]) else {
                    felService.appendLog("Usage: dump <addr> <len>")
                    return
                }
                dumpAddr = a
                dumpLen = l
                filename = "dump-\(String(format: "%08x", a))-\(l).bin"
            }

            felService.appendLog("Dumping \(dumpLen) bytes from 0x\(String(format: "%08x", dumpAddr))...")
            felService.dumpMemory(address: dumpAddr, length: dumpLen, progress: { done, total in
                let pct = (done * 100) / total
                if pct % 25 == 0 {
                    felService.appendLog("  \(done)/\(total) (\(pct)%)")
                }
            }) { result in
                switch result {
                case .success(let data):
                    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                    let fileURL = desktop.appendingPathComponent(filename)
                    do {
                        try data.write(to: fileURL)
                        felService.appendLog("Saved \(data.count) bytes to \(fileURL.path)")
                    } catch {
                        felService.appendLog("ERROR: Failed to save: \(error.localizedDescription)")
                    }
                case .failure(let err):
                    felService.appendLog("ERROR: \(err.localizedDescription)")
                }
            }

        case "sync":
            guard let sid = felService.deviceInfo?.sid else {
                felService.appendLog("ERROR: No device SID available")
                return
            }
            let pending = appState.deviceRegistry.pendingSyncs
            if pending > 0 {
                felService.appendLog("Flushing \(pending) queued sync(s)...")
                appState.deviceRegistry.flushQueue()
            }
            felService.appendLog("Syncing device to source.parts...")
            appState.deviceRegistry.sync(sid: sid) { [weak appState] result in
                switch result {
                case .success:
                    felService.appendLog("Device synced to source.parts API")
                case .failure(let err):
                    let queued = appState?.deviceRegistry.pendingSyncs ?? 0
                    felService.appendLog("\(err.localizedDescription) (\(queued) queued)")
                }
            }

        case "disconnect":
            felService.disconnect()

        case "reconnect", "connect":
            felService.connect()

        case "serial":
            if felService.connectionState == .connected {
                felService.appendLog("Cannot open serial while FEL is active — boot first")
            } else {
                felService.connectSerial()
            }

        case "device":
            if let reg = felService.registeredDevice {
                felService.appendLog("Name:     \(reg.name)")
                felService.appendLog("Owner:    \(reg.owner.isEmpty ? "(unset)" : reg.owner)")
                felService.appendLog("SID:      \(reg.sid)")
                felService.appendLog("SoC:      \(reg.hardware.soc)")
                felService.appendLog("Board:    \(reg.boardRevision.isEmpty ? "(unset)" : reg.boardRevision)")
                felService.appendLog("Serial:   \(reg.boardSerial.isEmpty ? "(unset)" : reg.boardSerial)")
                felService.appendLog("Boots:    \(reg.bootCount)")
                felService.appendLog("First:    \(reg.firstSeen.formatted())")
                felService.appendLog("Last:     \(reg.lastSeen.formatted())")
                if !reg.notes.isEmpty { felService.appendLog("Notes:    \(reg.notes)") }
                if !reg.tags.isEmpty { felService.appendLog("Tags:     \(reg.tags.joined(separator: ", "))") }
            } else {
                felService.appendLog("No device registered. Connect a device first.")
            }

        case "name":
            guard parts.count >= 2 else {
                felService.appendLog("ERROR: Usage: name <device name>")
                return
            }
            let newName = parts[1...].joined(separator: " ")
            if let sid = felService.deviceInfo?.sid {
                appState.deviceRegistry.rename(sid: sid, name: newName)
                felService.registeredDevice = appState.deviceRegistry.lookup(sid: sid)
                felService.appendLog("Device renamed: \(newName)")
            }

        case "owner":
            guard parts.count >= 2 else {
                felService.appendLog("ERROR: Usage: owner <owner name>")
                return
            }
            let ownerName = parts[1...].joined(separator: " ")
            if let sid = felService.deviceInfo?.sid {
                appState.deviceRegistry.setOwner(sid: sid, owner: ownerName)
                felService.registeredDevice = appState.deviceRegistry.lookup(sid: sid)
                felService.appendLog("Owner set: \(ownerName)")
            }

        case "clear":
            felService.log.removeAll()
        default:
            felService.appendLog("ERROR: Unknown command: \(command). Type 'help'.")
        }
    }

    // MARK: - U-Boot Panel

    @State private var ubootCommand = ""

    /// Whether serial commands can be sent (not in FEL mode and serial is active).
    private var serialReady: Bool {
        felService.connectionState != .connected && felService.serialActive
    }

    @ViewBuilder
    private var ubootPanel: some View {
        VStack(spacing: 0) {
            // Quick command bar
            HStack(spacing: 6) {
                Button(action: { sendUBoot("version") }) {
                    Text("version")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!serialReady)

                Button(action: { sendUBoot("bdinfo") }) {
                    Text("bdinfo")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!serialReady)

                Button(action: { sendUBoot("printenv") }) {
                    Text("env")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!serialReady)

                Button(action: { sendUBoot("mmc info") }) {
                    Text("mmc")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!serialReady)

                Button(action: { sendUBoot("usb info") }) {
                    Text("usb")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!serialReady)

                Button(action: { sendUBoot("boot") }) {
                    Text("boot")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.mini)
                .disabled(!serialReady)

                Button(action: { sendUBoot("reset") }) {
                    Text("reset")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.mini)
                .disabled(!serialReady)

                Divider().frame(height: 14)

                if felService.connectionState == .connected {
                    HStack(spacing: 3) {
                        Circle().fill(.yellow).frame(width: 5, height: 5)
                        Text("FEL Mode")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                } else if !felService.serialActive {
                    Button(action: { felService.connectSerial() }) {
                        HStack(spacing: 3) {
                            Circle().fill(.orange).frame(width: 5, height: 5)
                            Text("Connect Serial")
                                .font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    HStack(spacing: 3) {
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text(felService.serialPort ?? "Serial")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Serial output
            ScrollView {
                if felService.connectionState == .connected {
                    Text("Device is in FEL mode — boot first to use serial console")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    Text(felService.serialOutput.isEmpty ? "Connect serial or boot device to see output..." : felService.serialOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
            }
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Command input
            HStack(spacing: 4) {
                Text("=>")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(serialReady ? .yellow : .yellow.opacity(0.3))
                TextField("Serial command...", text: $ubootCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textFieldStyle(.plain)
                    .disabled(!serialReady)
                    .onSubmit {
                        guard !ubootCommand.isEmpty else { return }
                        sendUBoot(ubootCommand)
                        ubootCommand = ""
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))
        }
    }

    private func sendUBoot(_ cmd: String) {
        if felService.connectionState == .connected {
            felService.appendLog("Cannot send serial while FEL is active — boot first")
            return
        }
        if !felService.serialActive {
            felService.connectSerial()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                felService.sendSerial(cmd)
            }
        } else {
            felService.sendSerial(cmd)
        }
    }

    // MARK: - Serial Console View

    @State private var serialInput = ""

    @ViewBuilder
    private var serialConsoleView: some View {
        VStack(spacing: 0) {
            // Serial header bar
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(felService.serialPort ?? "Serial")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)
                Text("115200")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("FEL Log") {
                    felService.disconnectSerial()
                }
                .font(.caption2)
                .buttonStyle(.link)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(felService.serialOutput, forType: .string)
                }
                .font(.caption2)
                .buttonStyle(.link)
                Button("Clear") {
                    felService.serialOutput = ""
                }
                .font(.caption2)
                .buttonStyle(.link)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(white: 0.05))

            // Serial output
            ScrollView {
                Text(felService.serialOutput.isEmpty ? "Waiting for serial data..." : felService.serialOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Serial input
            HStack(spacing: 4) {
                Text(">")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                TextField("", text: $serialInput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let cmd = serialInput
                        guard !cmd.isEmpty else { return }
                        felService.sendSerial(cmd)
                        serialInput = ""
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(white: 0.08))
        }
    }

    private var deviceStateColor: Color {
        switch appState.deviceTracker.state {
        case .disconnected: return .secondary
        case .fel: return .yellow
        case .splLoading, .dramInit: return .orange
        case .uboot: return .blue
        case .kernel: return .purple
        case .login, .running: return .green
        case .massStorage: return .cyan
        }
    }

    // MARK: - Live Watch

    private func toggleWatch() {
        if felService.watchActive {
            felService.stopWatch()
        } else {
            guard let addr = parseHexAddress(readAddress),
                  let len = UInt32(readLength) else { return }
            felService.startWatch(address: addr, length: min(len, 4096))
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

        // Cap at 64KB to prevent GUI lock
        let cappedLen = min(len, 65536)
        if cappedLen < len {
            readError = "Capped to 64KB (requested \(len))"
        } else {
            readError = nil
        }

        isReading = true
        readProgress = 0

        // Chunked read: 4KB per chunk with progress
        let chunkSize: UInt32 = 4096
        var accumulated = Data()
        let totalChunks = max(1, (cappedLen + chunkSize - 1) / chunkSize)

        func readChunk(_ index: UInt32) {
            let offset = index * chunkSize
            if offset >= cappedLen {
                isReading = false
                readData = accumulated
                readBaseAddr = addr
                felService.appendLog("Read \(accumulated.count) bytes @ 0x\(String(format: "%x", addr))")
                return
            }
            let remaining = cappedLen - offset
            let thisLen = min(chunkSize, remaining)
            felService.readMemory(address: addr + offset, length: thisLen) { result in
                switch result {
                case .success(let data):
                    accumulated.append(data)
                    readProgress = Double(index + 1) / Double(totalChunks)
                    readChunk(index + 1)
                case .failure(let error):
                    isReading = false
                    readData = accumulated.isEmpty ? nil : accumulated
                    readBaseAddr = addr
                    readError = error.localizedDescription
                }
            }
        }

        readChunk(0)
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

        guard confirmBoot(
            splName: splUrl.lastPathComponent,
            splSize: splData.count,
            ubootName: ubootURL?.lastPathComponent,
            ubootSize: ubootData?.count
        ) else { return }

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
        guard felService.connectionState == .connected else {
            bootError = "No FEL device connected"
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Try binary paths in order of preference:
        // 1. Buildroot combined binary (SPL + ATF BL31 + U-Boot FIT)
        // 2. fel.js assets combined binary
        // 3. Standalone SPL from PocketPC-Uboot build (SPL-only, no U-Boot)
        let candidates = [
            "\(home)/Work/deepfry/buildroot/output/images/u-boot-sunxi-with-spl.bin",
            "\(home)/Work/fel.js/assets/PocketPC/u-boot-sunxi-with-spl.bin",
            "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin",
        ]
        guard let splPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else {
            bootError = "No SPL binary found"
            return
        }

        // Load separate U-Boot and ATF BL31 binaries
        let ubootData = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/Work/PocketPC-Uboot/u-boot.bin"))
        let bl31Data = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/Work/PocketPC-Uboot/bl31.bin"))

        let splName = URL(fileURLWithPath: splPath).lastPathComponent
        guard confirmBoot(splName: splName, splSize: splData.count, ubootName: nil, ubootSize: ubootData?.count) else { return }

        isBooting = true
        bootError = nil

        felService.bootPocketPC(splData: splData, ubootData: ubootData, bl31Data: bl31Data) { result in
            isBooting = false
            if case .failure(let error) = result {
                bootError = error.localizedDescription
            }
        }
    }

    /// Show a pre-flight confirmation dialog before boot. Returns true if user confirms.
    private func confirmBoot(splName: String, splSize: Int, ubootName: String?, ubootSize: Int?) -> Bool {
        let soc = felService.deviceInfo?.socInfo.name ?? "Unknown SoC"
        var details = """
        SoC: \(soc)
        SPL: \(splName) (\(splSize) bytes)
        """
        if let name = ubootName, let size = ubootSize {
            details += "\nU-Boot: \(name) (\(size) bytes)"
        } else if splSize > 0x8000 {
            details += "\nCombined binary — SPL + U-Boot will be split automatically"
        }
        details += """

        \nThis will:
        1. Write and execute SPL (DRAM init, 30-60s)
        2. Reset USB after DRAM PLL reconfig
        3. Write U-Boot to DRAM
        4. Trigger RMR warm reset into AArch64

        The device will reboot and the USB connection will drop.
        """

        let alert = NSAlert()
        alert.messageText = "Boot Device?"
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Boot")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
#endif
