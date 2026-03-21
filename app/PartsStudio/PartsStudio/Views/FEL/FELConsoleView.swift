import SwiftUI

struct FELConsoleView: View {
    let log: [String]
    var onClear: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Console")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: onClear)
                    .font(.caption2)
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(log.enumerated()), id: \.offset) { index, entry in
                            Text(entry)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .onChange(of: log.count) { _, _ in
                    if let last = log.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .background(Color.black)
            .frame(minHeight: 120, maxHeight: 200)
            .contentShape(Rectangle())
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
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
        }
    }
}

/// Hex dump display for memory reads.
struct HexDumpView: View {
    let data: Data
    let baseAddress: UInt32

    var body: some View {
        ScrollView {
            Text(hexDump)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.green)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .background(Color.black)
    }

    private var hexDump: String {
        var lines: [String] = []
        let bytesPerLine = 16

        for offset in stride(from: 0, to: data.count, by: bytesPerLine) {
            let addr = String(format: "%08x", baseAddress + UInt32(offset))
            let end = min(offset + bytesPerLine, data.count)
            let lineBytes = data[offset..<end]

            let hex = lineBytes.map { String(format: "%02x", $0) }
                .enumerated()
                .map { i, s in i == 7 ? s + " " : s }
                .joined(separator: " ")

            let ascii = lineBytes.map { byte -> String in
                (0x20...0x7E).contains(byte) ? String(UnicodeScalar(byte)) : "."
            }.joined()

            let paddedHex = hex.padding(toLength: 49, withPad: " ", startingAt: 0)
            lines.append("\(addr)  \(paddedHex)  |\(ascii)|")
        }
        return lines.joined(separator: "\n")
    }
}
