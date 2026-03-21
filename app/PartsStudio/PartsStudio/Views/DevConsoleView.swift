import SwiftUI

/// Counter-Strike / Quake-style drop-down developer console.
/// Toggle with backtick (`). Slides down from top of the window.
struct DevConsoleView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isVisible: Bool
    @State private var commandText: String = ""
    @State private var history: [ConsoleLine] = []
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int = -1
    @FocusState private var isFocused: Bool
    @AppStorage("consoleTextColor") private var consoleTextColor = "green"
    @AppStorage("consoleBackgroundColor") private var consoleBackgroundColor = "black"

    private var textColor: Color { ConsoleTheme.textColor(from: consoleTextColor) }
    private var bgColor: Color { ConsoleTheme.backgroundColor(from: consoleBackgroundColor) }

    struct ConsoleLine: Identifiable {
        let id = UUID()
        let text: String
        let style: LineStyle

        enum LineStyle {
            case input, output, error, info
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Console body
            VStack(spacing: 0) {
                // Output area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            // FEL log passthrough
                            ForEach(appState.felService.log.indices, id: \.self) { i in
                                Text(appState.felService.log[i])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(textColor.opacity(0.7))
                            }
                            // Console history
                            ForEach(history) { line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(lineColor(line.style))
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: history.count) { _, _ in
                        if let last = history.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                // Input line
                HStack(spacing: 4) {
                    Text(">")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(textColor)
                    TextField("", text: $commandText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(textColor)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit { executeCommand() }
                        .onKeyPress(.upArrow) {
                            navigateHistory(up: true)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            navigateHistory(up: false)
                            return .handled
                        }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(white: 0.08))
            }
            .background(.ultraThinMaterial.opacity(0.85))
            .background(bgColor.opacity(0.75))
        }
        .onAppear { isFocused = true }
    }

    private func lineColor(_ style: ConsoleLine.LineStyle) -> Color {
        switch style {
        case .input: return textColor
        case .output: return .white
        case .error: return .red
        case .info: return .yellow
        }
    }

    private func navigateHistory(up: Bool) {
        guard !commandHistory.isEmpty else { return }
        if up {
            historyIndex = min(historyIndex + 1, commandHistory.count - 1)
        } else {
            historyIndex = max(historyIndex - 1, -1)
        }
        commandText = historyIndex >= 0 ? commandHistory[commandHistory.count - 1 - historyIndex] : ""
    }

    private func executeCommand() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }

        history.append(ConsoleLine(text: "> \(cmd)", style: .input))
        commandHistory.append(cmd)
        historyIndex = -1
        commandText = ""

        let parts = cmd.split(separator: " ", maxSplits: 3).map(String.init)
        let command = parts[0].lowercased()

        switch command {
        case "help":
            output("""
            Commands:
              help                    Show this help
              status                  FEL connection status
              info                    Device info (SoC, SID, addresses)
              internals               Thunk, swap buffers, L2 details
              read <addr> [len]       Read memory (hex address, default 256 bytes)
              scratch                 Read scratch memory
              sram                    Read SRAM A
              boot                    Boot PocketPC (default paths)
              clear                   Clear console
              close                   Close console
            """)

        case "status":
            let state = appState.felService.connectionState.rawValue
            let soc = appState.felService.deviceInfo?.displayName ?? "none"
            output("state: \(state)  soc: \(soc)")

        case "info":
            guard let info = appState.felService.deviceInfo else {
                error("No device connected")
                return
            }
            output("SoC:      \(info.socInfo.name) (0x\(info.version.socIdHex))")
            output("Protocol: 0x\(String(format: "%04x", info.version.protocolVersion))")
            output("SID:      \(info.sid ?? "reading...")")
            output("SPL:      0x\(String(format: "%08x", info.socInfo.splAddr))")
            output("Scratch:  0x\(String(format: "%08x", info.socInfo.scratchAddr))")
            if info.socInfo.rvbarReg != 0 {
                output("RVBAR:    0x\(String(format: "%08x", info.socInfo.rvbarReg))")
            }

        case "internals":
            guard let info = appState.felService.deviceInfo else {
                error("No device connected")
                return
            }
            output("Thunk:    0x\(String(format: "%08x", info.socInfo.thunkAddr))  size=0x\(String(format: "%x", info.socInfo.thunkSize))")
            output("SID Base: 0x\(String(format: "%08x", info.socInfo.sidBase))  offset=0x\(String(format: "%x", info.socInfo.sidOffset))")
            output("L2EN:     \(info.socInfo.needsL2EN)  SID Fix: \(info.socInfo.sidFix)")
            output("Swap Buffers (\(info.socInfo.swapBuffers.count)):")
            for (i, sb) in info.socInfo.swapBuffers.enumerated() {
                output("  [\(i)] 0x\(String(format: "%05x", sb.buf1)) <-> 0x\(String(format: "%05x", sb.buf2))  size=0x\(String(format: "%x", sb.size))")
            }

        case "read":
            guard appState.felService.connectionState == .connected else {
                error("Not connected")
                return
            }
            guard parts.count >= 2 else {
                error("Usage: read <addr> [length]")
                return
            }
            guard let addr = parseHex(parts[1]) else {
                error("Invalid address: \(parts[1])")
                return
            }
            let len = parts.count >= 3 ? (UInt32(parts[2]) ?? 256) : 256
            info("Reading \(len) bytes @ 0x\(String(format: "%x", addr))...")
            appState.felService.readMemory(address: addr, length: len) { result in
                switch result {
                case .success(let data):
                    output(hexDump(data, base: addr))
                case .failure(let err):
                    error(err.localizedDescription)
                }
            }

        case "scratch":
            guard let si = appState.felService.deviceInfo?.socInfo else {
                error("Not connected")
                return
            }
            info("Reading scratch @ 0x\(String(format: "%x", si.scratchAddr))...")
            appState.felService.readMemory(address: si.scratchAddr, length: 256) { result in
                switch result {
                case .success(let data): output(hexDump(data, base: si.scratchAddr))
                case .failure(let err): error(err.localizedDescription)
                }
            }

        case "sram":
            guard let si = appState.felService.deviceInfo?.socInfo else {
                error("Not connected")
                return
            }
            let addr = si.splAddr > 0 ? si.splAddr : UInt32(0)
            info("Reading SRAM @ 0x\(String(format: "%x", addr))...")
            appState.felService.readMemory(address: addr, length: 256) { result in
                switch result {
                case .success(let data): output(hexDump(data, base: addr))
                case .failure(let err): error(err.localizedDescription)
                }
            }

        case "boot":
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
            let ubootPath = "\(home)/Work/PocketPC-Uboot/u-boot.bin"
            guard let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else {
                error("Cannot read \(splPath)")
                return
            }
            let ubootData = try? Data(contentsOf: URL(fileURLWithPath: ubootPath))
            info("Booting PocketPC...")
            appState.felService.bootPocketPC(splData: splData, ubootData: ubootData) { result in
                switch result {
                case .success: output("Boot sequence complete")
                case .failure(let err): error(err.localizedDescription)
                }
            }

        case "clear":
            history.removeAll()

        case "close":
            withAnimation(.easeOut(duration: 0.2)) { isVisible = false }

        default:
            error("Unknown command: \(command). Type 'help' for commands.")
        }
    }

    private func output(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            history.append(ConsoleLine(text: String(line), style: .output))
        }
    }

    private func error(_ text: String) {
        history.append(ConsoleLine(text: text, style: .error))
    }

    private func info(_ text: String) {
        history.append(ConsoleLine(text: text, style: .info))
    }

    private func parseHex(_ s: String) -> UInt32? {
        let cleaned = s.hasPrefix("0x") || s.hasPrefix("0X") ? String(s.dropFirst(2)) : s
        return UInt32(cleaned, radix: 16)
    }

    private func hexDump(_ data: Data, base: UInt32) -> String {
        var lines: [String] = []
        for offset in stride(from: 0, to: data.count, by: 16) {
            let addr = String(format: "%08x", base + UInt32(offset))
            let end = min(offset + 16, data.count)
            let bytes = data[offset..<end]
            let hex = bytes.map { String(format: "%02x", $0) }
                .enumerated()
                .map { i, s in i == 7 ? s + " " : s }
                .joined(separator: " ")
            let ascii = bytes.map { (0x20...0x7E).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append("\(addr)  \(hex.padding(toLength: 49, withPad: " ", startingAt: 0))  |\(ascii)|")
        }
        return lines.joined(separator: "\n")
    }
}
