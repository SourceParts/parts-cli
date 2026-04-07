#if os(macOS)
import SwiftUI
import IOKit
import IOKit.usb
import IOKit.serial

struct USBDevice: Identifiable {
    let id: String
    let name: String
    let vendorId: Int
    let productId: Int
    let vendorName: String
    let maxPower: Int        // mA
    let speed: String
    let serialPort: String?  // /dev/cu.* path if serial
    let locationId: Int

    var vendorHex: String { String(format: "0x%04X", vendorId) }
    var productHex: String { String(format: "0x%04X", productId) }

    var chipType: String {
        switch vendorId {
        case 0x1A86: // WCH
            switch productId {
            case 0x7523: return "CH340"
            case 0x55D3: return "CH343"
            case 0x55D4: return "CH9102"
            case 0x7522: return "CH340K"
            case 0x5523: return "CH341"
            default: return "WCH (unknown)"
            }
        case 0x10C4: return "CP2102/CP2104 (Silicon Labs)"
        case 0x0403:
            switch productId {
            case 0x6001: return "FT232R (FTDI)"
            case 0x6010: return "FT2232 (FTDI)"
            case 0x6011: return "FT4232 (FTDI)"
            case 0x6014: return "FT232H (FTDI)"
            case 0x6015: return "FT-X (FTDI)"
            default: return "FTDI (unknown)"
            }
        case 0x1F3A: // Allwinner
            switch productId {
            case 0xEFE8: return "Allwinner A64 FEL (sunxi boot)"
            case 0x1010: return "Allwinner A64 (ADB)"
            default: return "Allwinner SoC"
            }
        case 0x303A: // Espressif
            switch productId {
            case 0x1001: return "ESP32-S2"
            case 0x0002: return "ESP32-S3"
            case 0x0003: return "ESP32-C3"
            case 0x1002: return "ESP32-C6"
            default: return "ESP32 (Espressif)"
            }
        case 0x2341: return "Arduino"
        case 0x1D6B: return "Linux USB (gadget)"
        case 0x0525: // Linux USB gadget (common for CDC-ECM)
            switch productId {
            case 0xA4A2: return "Linux CDC-ECM (Ethernet)"
            case 0xA4A1: return "Linux CDC-ACM (Serial)"
            default: return "Linux USB Gadget"
            }
        case 0x05AC: return "Apple"
        default: return ""
        }
    }

    var isSerial: Bool { serialPort != nil }
    var isFEL: Bool { vendorId == 0x1F3A && productId == 0xEFE8 }
    var isAllwinner: Bool { vendorId == 0x1F3A }
    var isCDCEthernet: Bool { vendorId == 0x0525 || name.lowercased().contains("ethernet") || name.lowercased().contains("cdc") || name.lowercased().contains("popcorn") }
    var isKnownDebugChip: Bool { [0x1A86, 0x10C4, 0x0403].contains(vendorId) }
    var isInteresting: Bool { isKnownDebugChip || isAllwinner || isCDCEthernet || isPocketPC }
    var isPocketPC: Bool { isAllwinner || isCDCEthernet || (vendorId == 0x1A86 && serialPort?.contains("usbserial") == true) }

    /// Friendly device name — like iTunes recognizing an iPod
    var friendlyName: String? {
        if isFEL { return "PocketPC (FEL Boot Mode)" }
        if vendorId == 0x1F3A { return "PocketPC (Allwinner A64)" }
        if isCDCEthernet || name.lowercased().contains("popcorn") { return "Popstick (CDC Ethernet)" }
        if vendorId == 0x1A86 && serialPort != nil { return "PocketPC Debug Console" }
        // ESP32 detection
        if vendorId == 0x303A { return "ESP32 (Espressif)" }
        if vendorId == 0x10C4 && name.lowercased().contains("cp210") { return "ESP32 (CP2102 Bridge)" }
        return nil
    }

    var deviceIcon: String {
        if isFEL { return "bolt.fill" }
        if isPocketPC { return "desktopcomputer" }
        if isCDCEthernet { return "network" }
        if vendorId == 0x303A || (vendorId == 0x10C4 && name.lowercased().contains("esp")) { return "antenna.radiowaves.left.and.right" }
        if isSerial { return "cable.connector" }
        return "usb"
    }
}

struct SerialSession: Identifiable {
    let id = UUID()
    let port: String
    let device: USBDevice
}

// MARK: - USB Monitor View

struct USBMonitorView: View {
    @EnvironmentObject var appState: AppState
    @State private var devices: [USBDevice] = []
    @State private var deviceLog: [(Date, USBDevice)] = []  // History of seen devices
    @State private var serialSessions: [SerialSession] = []
    @State private var selectedDevice: USBDevice?
    @State private var serialOutput: [String: String] = [:]
    @State private var serialInput: String = ""
    @State private var baudRate: Int = 115200
    @State private var activePort: String?
    @State private var fileHandles: [String: FileHandle] = [:]
    @State private var autoScan: Bool = true
    @State private var scanTimer: Timer?

    let baudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cable.connector")
                    .foregroundStyle(Color.accentColor)
                Text("USB Monitor")
                    .font(.headline)
                Spacer()
                Text("\(devices.count) device\(devices.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $autoScan) {
                    Text("Auto")
                        .font(.caption2)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Auto-scan every 2 seconds to catch FEL mode devices")
                .onChange(of: autoScan) { _, on in
                    if on { startAutoScan() } else { stopAutoScan() }
                }

                Button(action: scanDevices) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan USB devices")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HSplitView {
                // Device list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(devices) { device in
                            USBDeviceCard(device: device, isSelected: selectedDevice?.id == device.id) {
                                selectedDevice = device
                            } onConnect: {
                                connectSerial(device)
                            }
                        }

                        if devices.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "cable.connector.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                                Text("No USB devices detected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(40)
                        }

                        // Device event log
                        if !deviceLog.isEmpty {
                            Divider().padding(.vertical, 4)
                            HStack {
                                Text("Event Log")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear") { deviceLog.removeAll() }
                                    .font(.caption2)
                                    .buttonStyle(.link)
                            }

                            ForEach(Array(deviceLog.enumerated()), id: \.offset) { _, entry in
                                let (date, dev) = entry
                                HStack(spacing: 6) {
                                    Image(systemName: dev.isFEL ? "bolt.fill" : "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(dev.isFEL ? .yellow : .green)
                                    Text(dev.name)
                                        .font(.caption2)
                                        .fontWeight(dev.isFEL ? .bold : .regular)
                                    if !dev.chipType.isEmpty {
                                        Text(dev.chipType)
                                            .font(.caption2)
                                            .foregroundStyle(dev.isFEL ? .yellow : .blue)
                                    }
                                    Spacer()
                                    Text(timeFormatter.string(from: date))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                                .background(dev.isFEL ? Color.yellow.opacity(0.05) : Color.clear)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 350)

                // Serial terminal (right panel)
                if let port = activePort {
                    SerialTerminalView(
                        port: port,
                        output: serialOutput[port] ?? "",
                        input: $serialInput,
                        baudRate: $baudRate,
                        baudRates: baudRates,
                        onSend: { sendSerial(port, text: $0) },
                        onDisconnect: { disconnectSerial(port) },
                        onClear: { serialOutput[port] = "" }
                    )
                    .frame(minWidth: 300)
                } else if let device = selectedDevice {
                    // Device detail
                    USBDeviceDetailView(device: device)
                        .frame(minWidth: 300)
                }
            }
        }
        .onAppear { scanDevices(); if autoScan { startAutoScan() } }
        .onDisappear { stopAutoScan() }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }

    private func startAutoScan() {
        stopAutoScan()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            scanDevices()
        }
    }

    private func stopAutoScan() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - USB Scanning

    private func scanDevices() {
        var result: [USBDevice] = []

        // Get serial ports first
        let serialPorts = getSerialPorts()

        // Scan USB devices via IOKit
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0

        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else {
            devices = result
            return
        }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            let name = getStringProperty(service, key: "USB Product Name") ?? "Unknown USB Device"
            let vendorName = getStringProperty(service, key: "USB Vendor Name") ?? ""
            let vendorId = getIntProperty(service, key: "idVendor")
            let productId = getIntProperty(service, key: "idProduct")
            let locationId = getIntProperty(service, key: "locationID")
            let maxPower = getIntProperty(service, key: "bMaxPower") * 2  // units of 2mA
            let speedRaw = getIntProperty(service, key: "Device Speed")

            let speed: String
            switch speedRaw {
            case 0: speed = "Low (1.5 Mbps)"
            case 1: speed = "Full (12 Mbps)"
            case 2: speed = "High (480 Mbps)"
            case 3: speed = "Super (5 Gbps)"
            case 4: speed = "Super+ (10 Gbps)"
            default: speed = "Unknown"
            }

            // Match serial port by vendor ID pattern
            let serialPort = serialPorts.first(where: { port in
                // WCH chips show as usbserial-*
                if vendorId == 0x1A86 && port.contains("usbserial") { return true }
                if port.contains("usbmodem") { return true }
                return false
            })

            let device = USBDevice(
                id: "\(vendorId)-\(productId)-\(locationId)",
                name: name,
                vendorId: vendorId,
                productId: productId,
                vendorName: vendorName,
                maxPower: maxPower,
                speed: speed,
                serialPort: serialPort,
                locationId: locationId
            )
            result.append(device)
        }
        IOObjectRelease(iterator)

        // Sort: serial devices first, then by name
        result.sort { a, b in
            if a.isSerial && !b.isSerial { return true }
            if !a.isSerial && b.isSerial { return false }
            return a.name < b.name
        }

        // Log new interesting devices (especially FEL)
        let oldIds = Set(devices.map { $0.id })
        for dev in result where dev.isInteresting && !oldIds.contains(dev.id) {
            deviceLog.insert((Date(), dev), at: 0)
            if deviceLog.count > 50 { deviceLog = Array(deviceLog.prefix(50)) }
        }

        devices = result
    }

    private func getSerialPorts() -> [String] {
        let fm = FileManager.default
        let devEntries = (try? fm.contentsOfDirectory(atPath: "/dev")) ?? []
        return devEntries
            .filter { $0.hasPrefix("cu.usb") }
            .map { "/dev/\($0)" }
    }

    private func getStringProperty(_ service: io_service_t, key: String) -> String? {
        let cfKey = key as CFString
        guard let value = IORegistryEntryCreateCFProperty(service, cfKey, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    private func getIntProperty(_ service: io_service_t, key: String) -> Int {
        let cfKey = key as CFString
        guard let value = IORegistryEntryCreateCFProperty(service, cfKey, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return 0
        }
        return (value as? Int) ?? 0
    }

    // MARK: - Serial Connection

    private func connectSerial(_ device: USBDevice) {
        guard let port = device.serialPort else { return }
        activePort = port

        // Configure and open the serial port
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/stty")
            process.arguments = ["-f", port, String(baudRate)]
            try? process.run()
            process.waitUntilExit()

            // Open for reading
            let fh = FileHandle(forReadingAtPath: port)
            if let fh = fh {
                fileHandles[port] = fh
                fh.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            serialOutput[port, default: ""] += text
                        }
                    }
                }
            }
        }
    }

    private func sendSerial(_ port: String, text: String) {
        guard let fh = FileHandle(forWritingAtPath: port) else { return }
        if let data = (text + "\r\n").data(using: .utf8) {
            fh.write(data)
        }
        fh.closeFile()
    }

    private func disconnectSerial(_ port: String) {
        fileHandles[port]?.readabilityHandler = nil
        fileHandles[port]?.closeFile()
        fileHandles.removeValue(forKey: port)
        if activePort == port { activePort = nil }
    }
}

// MARK: - Device Card

struct USBDeviceCard: View {
    let device: USBDevice
    let isSelected: Bool
    let onSelect: () -> Void
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Friendly name banner (like iTunes for iPod)
            if let friendly = device.friendlyName {
                HStack(spacing: 6) {
                    Image(systemName: device.deviceIcon)
                        .font(.caption)
                    Text(friendly)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(device.isFEL ? Color.yellow : Color.accentColor)
                )
            }

            HStack {
                Image(systemName: device.deviceIcon)
                    .foregroundStyle(device.isInteresting ? Color.accentColor : .secondary)
                Text(device.name)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if device.isSerial {
                    Button(action: onConnect) {
                        Label("Connect", systemImage: "terminal")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Text(device.vendorHex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !device.chipType.isEmpty {
                    Text(device.chipType)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if !device.vendorName.isEmpty {
                    Text(device.vendorName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if device.maxPower > 0 {
                    Text("\(device.maxPower) mA")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let port = device.serialPort {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.green)
                    Text(port)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Device Detail

struct USBDeviceDetailView: View {
    let device: USBDevice

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Device Info")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    infoRow("Name", device.name)
                    infoRow("Vendor", "\(device.vendorName) (\(device.vendorHex))")
                    infoRow("Product ID", device.productHex)
                    if !device.chipType.isEmpty {
                        infoRow("Chip", device.chipType)
                    }
                    infoRow("Speed", device.speed)
                    infoRow("Max Power", "\(device.maxPower) mA")
                    infoRow("Location", String(format: "0x%08X", device.locationId))
                    if let port = device.serialPort {
                        infoRow("Serial Port", port)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        Divider()
    }
}

// MARK: - Serial Terminal

struct SerialTerminalView: View {
    let port: String
    let output: String
    @Binding var input: String
    @Binding var baudRate: Int
    let baudRates: [Int]
    let onSend: (String) -> Void
    let onDisconnect: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            HStack {
                Image(systemName: "terminal")
                    .foregroundStyle(.green)
                Text(port)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
                Spacer()
                Picker("", selection: $baudRate) {
                    ForEach(baudRates, id: \.self) { rate in
                        Text("\(rate)").tag(rate)
                    }
                }
                .frame(width: 100)
                .help("Baud rate")

                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear output")

                Button(action: onDisconnect) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Disconnect")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black)

            // Terminal output
            ScrollView {
                Text(output.isEmpty ? "Connected. Waiting for data...\n" : output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color.black)

            // Input line
            HStack(spacing: 4) {
                Text(">")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
                TextField("", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.green)
                    .onSubmit {
                        onSend(input)
                        input = ""
                    }
                Button(action: {
                    onSend(input)
                    input = ""
                }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty)
            }
            .padding(8)
            .background(Color(white: 0.1))
        }
    }
}
#endif
