import SwiftUI

struct FELPanelView: View {
    @StateObject private var fel = FELBridge()
    @State private var splPath: String = ""
    @State private var ubootPath: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(fel.isConnected ? .yellow : .secondary)
                Text("FEL Mode")
                    .font(.headline)
                Spacer()
                Text(fel.status)
                    .font(.caption)
                    .foregroundStyle(fel.isConnected ? .green : .secondary)
                Button(action: { Task { await fel.getVersion() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Check for FEL device")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if fel.isConnected {
                // Connected — show device info and actions
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Device info
                        GroupBox("Device") {
                            VStack(alignment: .leading, spacing: 4) {
                                infoRow("SoC", fel.socInfo)
                                infoRow("SID", fel.sid)
                            }
                        }

                        // Quick actions
                        GroupBox("Actions") {
                            VStack(spacing: 8) {
                                Button(action: {
                                    Task {
                                        try? await fel.bootPocketPC()
                                    }
                                }) {
                                    Label("Boot PocketPC (SPL + U-Boot)", systemImage: "power")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .help("Load SPL + U-Boot via FEL and boot the device")

                                Button(action: {
                                    Task { await fel.getSID() }
                                }) {
                                    Label("Read Serial ID", systemImage: "number")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button(action: {
                                    Task {
                                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                                        try? await fel.readSPIFlash(offset: 0, size: 4096, outputPath: "\(home)/Work/PocketPC-Backup/spi_dump.bin")
                                    }
                                }) {
                                    Label("Dump SPI Flash (4KB)", systemImage: "memorychip")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .help("Read first 4KB of SPI NOR flash")

                                Button(action: {
                                    Task {
                                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                                        let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
                                        try? await fel.writeSPIFlash(offset: 0, inputPath: splPath)
                                    }
                                }) {
                                    Label("Write SPL to SPI NOR", systemImage: "arrow.down.to.line")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .help("Write U-Boot SPL to SPI NOR flash for permanent boot")

                                Button(action: {
                                    Task {
                                        if let dump = await fel.hexdump(address: 0x0, length: 256) {
                                            fel.log.append(dump)
                                        }
                                    }
                                }) {
                                    Label("Hexdump SRAM", systemImage: "text.alignleft")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                // Not connected
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No FEL device detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Power on the device without bootable media\nto enter FEL mode (Allwinner USB boot)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button("Scan for Device") {
                        Task { await fel.getVersion() }
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                    Spacer()
                }
            }

            Divider()

            // Log
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Log")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { fel.log.removeAll() }
                        .font(.caption2)
                        .buttonStyle(.link)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                ScrollView {
                    Text(fel.log.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(height: 120)
                .background(Color.black)
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
