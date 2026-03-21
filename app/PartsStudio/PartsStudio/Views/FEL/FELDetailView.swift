import SwiftUI

enum FELTab: String, CaseIterable {
    case info = "Info"
    case memory = "Memory"
    case boot = "Boot"
    case console = "Console"

    var icon: String {
        switch self {
        case .info: return "cpu"
        case .memory: return "memorychip"
        case .boot: return "power"
        case .console: return "terminal"
        }
    }
}

struct FELDetailView: View {
    @EnvironmentObject var appState: AppState

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
                case .console:
                    FELConsoleView(log: felService.log) {
                        felService.log.removeAll()
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

            // Device badge
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

            // Hex dump
            if let data = readData {
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
