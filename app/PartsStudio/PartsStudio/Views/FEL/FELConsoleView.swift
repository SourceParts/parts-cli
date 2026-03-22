import SwiftUI

struct FELConsoleView: View {
    let log: [String]
    var onClear: () -> Void
    var onCommand: ((String) -> Void)? = nil
    @State private var copied = false
    @State private var commandText = ""
    @State private var cursorVisible = false
    @FocusState private var inputFocused: Bool
    @AppStorage("consoleTextColor") private var consoleTextColor = "green"
    @AppStorage("consoleBackgroundColor") private var consoleBackgroundColor = "black"

    private var textColor: Color { ConsoleTheme.textColor(from: consoleTextColor) }
    private var bgColor: Color { ConsoleTheme.backgroundColor(from: consoleBackgroundColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .font(.caption2)
                .buttonStyle(.link)
                .help("Copy console log to clipboard")
                Button("Clear", action: onClear)
                    .font(.caption2)
                    .buttonStyle(.link)
                    .keyboardShortcut("k", modifiers: [.command])
                    .help("Clear console (Cmd+K)")

                Divider().frame(height: 10)

                ConsoleColorPicker(selectedName: $consoleTextColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .id("bottom")
                }
                .onChange(of: log.count) { _, _ in
                    withAnimation(.none) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(bgColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if copied {
                    Text("Copied")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: copied)
                }
            }

            // Input line with blinking block cursor
            if onCommand != nil {
                HStack(spacing: 0) {
                    Text("> ")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(textColor)
                    ZStack(alignment: .leading) {
                        // Blinking block cursor positioned after text
                        HStack(spacing: 0) {
                            Text(commandText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.clear)
                            Rectangle()
                                .fill(textColor)
                                .frame(width: 7, height: 14)
                                .opacity(cursorVisible ? 1 : 0)
                        }
                        TextField("", text: $commandText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(textColor)
                            .textFieldStyle(.plain)
                            .focused($inputFocused)
                            .onSubmit {
                                let cmd = commandText.trimmingCharacters(in: .whitespaces)
                                guard !cmd.isEmpty else { return }
                                onCommand?(cmd)
                                commandText = ""
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(white: 0.08))
                .onAppear {
                    // Delay focus so the view is fully laid out first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        inputFocused = true
                    }
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        cursorVisible = true
                    }
                }
                .onTapGesture {
                    inputFocused = true
                }
            }
        }
        .onTapGesture {
            inputFocused = true
        }
    }
}

/// Hex dump display for memory reads with copy and editing.
struct HexDumpView: View {
    let data: Data
    let baseAddress: UInt32
    var onWrite: ((UInt32, Data) -> Void)? = nil

    @State private var copied = false
    @State private var editingOffset: Int? = nil
    @State private var editValue: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 6) {
                Text("\(data.count) bytes @ 0x\(String(format: "%08x", baseAddress))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.7))
                Spacer()
                Button(action: copyHex) {
                    HStack(spacing: 2) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 9))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? .green : .secondary)

                Button(action: copyRawBytes) {
                    Text("Raw")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy raw hex bytes without formatting")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(white: 0.08))

            // Hex dump
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lineIndices, id: \.self) { offset in
                        hexLine(at: offset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .background(Color.black)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                copyHex()
            }
            .overlay(alignment: .center) {
                if copied {
                    Text("Copied")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: copied)
                }
            }
        }
    }

    private var lineIndices: [Int] {
        stride(from: 0, to: data.count, by: 16).map { $0 }
    }

    @ViewBuilder
    private func hexLine(at offset: Int) -> some View {
        let end = min(offset + 16, data.count)
        let lineBytes = data[offset..<end]

        HStack(spacing: 0) {
            // Address
            Text(String(format: "%08x", baseAddress + UInt32(offset)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("  ")
                .font(.system(size: 10, design: .monospaced))

            // Hex bytes — clickable for editing
            ForEach(Array(lineBytes.enumerated()), id: \.offset) { i, byte in
                let globalOffset = offset + i
                if editingOffset == globalOffset {
                    TextField("", text: $editValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.yellow)
                        .frame(width: 18)
                        .textFieldStyle(.plain)
                        .onSubmit { commitEdit(at: globalOffset) }
                        .onExitCommand { editingOffset = nil }
                } else {
                    Text(String(format: "%02x", byte))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(byte == 0 ? .green.opacity(0.3) : .green)
                        .onTapGesture {
                            if onWrite != nil {
                                editingOffset = globalOffset
                                editValue = String(format: "%02x", byte)
                            }
                        }
                }
                Text(i == 7 ? "  " : " ")
                    .font(.system(size: 10, design: .monospaced))
            }

            // Pad if short line
            if lineBytes.count < 16 {
                Spacer()
            }

            Text(" |")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            // ASCII
            Text(lineBytes.map { (0x20...0x7E).contains($0) ? String(UnicodeScalar($0)) : "." }.joined())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.green.opacity(0.6))

            Text("|")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 0.5)
    }

    private func commitEdit(at offset: Int) {
        guard let byte = UInt8(editValue, radix: 16) else {
            editingOffset = nil
            return
        }
        let addr = baseAddress + UInt32(offset)
        onWrite?(addr, Data([byte]))
        editingOffset = nil
    }

    private func copyHex() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hexDumpText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func copyRawBytes() {
        let raw = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(raw, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private var hexDumpText: String {
        hexDumpFormatted(data, base: baseAddress)
    }

}

private func hexDumpFormatted(_ data: Data, base: UInt32) -> String {
    var lines: [String] = []
    for offset in stride(from: 0, to: data.count, by: 16) {
        let addr = String(format: "%08x", base + UInt32(offset))
        let end = min(offset + 16, data.count)
        let lineBytes = data[offset..<end]
        let hex = lineBytes.map { String(format: "%02x", $0) }
            .enumerated()
            .map { i, s in i == 7 ? s + " " : s }
            .joined(separator: " ")
        let ascii = lineBytes.map { (0x20...0x7E).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
        lines.append("\(addr)  \(hex.padding(toLength: 49, withPad: " ", startingAt: 0))  |\(ascii)|")
    }
    return lines.joined(separator: "\n")
}
