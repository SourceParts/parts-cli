import SwiftUI

enum FELTab: String, CaseIterable {
    case info = "Info"
    case memory = "Memory"
    case boot = "Boot"
    case uboot = "U-Boot"
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

    private var felService: FELService { appState.felService }

    var body: some View {
        VStack(spacing: 0) {
            if felService.connectionState == .connected, let info = felService.deviceInfo {
                // DevTools toolbar
                devToolsToolbar(info)
                Divider()

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
            .help(hasAPIKey ? "source.parts API key configured" : "No source.parts API key found")
            .onAppear { hasAPIKey = APIKeychain.loadAPIKey() != nil }

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
                    felService.writeMemory(address: addr, data: bytes) { result in
                        if case .success = result {
                            felService.appendLog("Wrote \(bytes.count) byte(s) @ 0x\(String(format: "%x", addr))")
                            readMemory() // refresh
                        }
                    }
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
                .help(hasAPIKey ? "source.parts API key configured" : "No source.parts API key found")
                .onAppear { hasAPIKey = APIKeychain.loadAPIKey() != nil }

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

        case "serial":
            felService.connectSerial()

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

                Button(action: { sendUBoot("bdinfo") }) {
                    Text("bdinfo")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { sendUBoot("printenv") }) {
                    Text("env")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { sendUBoot("mmc info") }) {
                    Text("mmc")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { sendUBoot("usb info") }) {
                    Text("usb")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { sendUBoot("boot") }) {
                    Text("boot")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.mini)

                Button(action: { sendUBoot("reset") }) {
                    Text("reset")
                        .font(.system(size: 9, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.mini)

                Divider().frame(height: 14)

                if !felService.serialActive {
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
                Text(felService.serialOutput.isEmpty ? "Connect serial or boot device to see U-Boot output..." : felService.serialOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Command input
            HStack(spacing: 4) {
                Text("=>")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.yellow)
                TextField("U-Boot command...", text: $ubootCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textFieldStyle(.plain)
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
        if !felService.serialActive {
            felService.connectSerial()
            // Wait a moment for serial to connect
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
}
