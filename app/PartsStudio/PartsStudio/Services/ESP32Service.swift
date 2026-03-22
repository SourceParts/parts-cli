import Foundation
import IOKit
import IOKit.usb

// IOKit USB UUIDs (C macros not bridged to Swift)
private let kIOUSBDeviceUserClientTypeID_ESP: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
        0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
private let kIOCFPlugInInterfaceID_ESP: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
        0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
private let kIOUSBDeviceInterfaceID_ESP: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
        0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
private let kIOUSBInterfaceUserClientTypeID_ESP: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4,
        0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
private let kIOUSBInterfaceInterfaceID_ESP: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4,
        0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

/// ESP32-S3 USB communication service.
/// Detects the ESP32-S3 USB-JTAG/serial device and provides:
///   - Serial console read/write (CDC interface)
///   - ROM bootloader firmware flashing (SLIP protocol)
///
/// The ESP32-S3 USB-JTAG serial appears as VID 0x303A, PID 0x1001.
/// Interface 0 = JTAG, Interface 2 = CDC serial (for console + flashing).
@MainActor
class ESP32Service: ObservableObject {
    @Published var connectionState: ESP32State = .disconnected
    @Published var deviceName: String = ""
    @Published var log: [String] = []
    @Published var flashProgress: Double = 0

    enum ESP32State: String {
        case disconnected = "Disconnected"
        case connected = "Connected"
        case flashing = "Flashing"
        case error = "Error"
    }

    // ESP32-S3 USB identifiers
    static let ESP_VID: UInt16 = 0x303A  // Espressif
    static let ESP_PID: UInt16 = 0x1001  // ESP32-S3 USB-JTAG/serial

    // USB state
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceStruct942>?>?
    private var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceStruct550>?>?
    private var pipeIn: UInt8 = 0
    private var pipeOut: UInt8 = 0
    private let usbQueue = DispatchQueue(label: "parts.studio.esp32.usb", qos: .userInitiated)

    // IOKit notification state
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    // SLIP framing constants
    private static let SLIP_END: UInt8 = 0xC0
    private static let SLIP_ESC: UInt8 = 0xDB
    private static let SLIP_ESC_END: UInt8 = 0xDC
    private static let SLIP_ESC_ESC: UInt8 = 0xDD

    // ROM bootloader command opcodes
    private static let ESP_FLASH_BEGIN: UInt8 = 0x02
    private static let ESP_FLASH_DATA: UInt8 = 0x03
    private static let ESP_FLASH_END: UInt8 = 0x04
    private static let ESP_SYNC: UInt8 = 0x08
    private static let ESP_READ_REG: UInt8 = 0x0A
    private static let ESP_WRITE_REG: UInt8 = 0x09
    private static let ESP_SPI_ATTACH: UInt8 = 0x0D
    private static let ESP_CHANGE_BAUDRATE: UInt8 = 0x0F
    private static let ESP_MD5: UInt8 = 0x13

    init() {
        startDeviceWatcher()
    }

    nonisolated deinit {
        // Cleanup handled by OS on process exit
    }

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(ts)] \(msg)")
        if log.count > 2000 { log.removeFirst(500) }
    }

    // MARK: - Device Watching

    private func startDeviceWatcher() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = Self.ESP_VID
        matchingDict[kUSBProductID] = Self.ESP_PID

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let addDict = matchingDict.mutableCopy() as! NSMutableDictionary
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, addDict, { refcon, iterator in
            guard let refcon = refcon else { return }
            let svc = Unmanaged<ESP32Service>.fromOpaque(refcon).takeUnretainedValue()
            svc.handleDeviceAdded(iterator)
        }, selfPtr, &addedIterator)
        handleDeviceAdded(addedIterator)

        let removeDict = matchingDict.mutableCopy() as! NSMutableDictionary
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, removeDict, { refcon, iterator in
            guard let refcon = refcon else { return }
            let svc = Unmanaged<ESP32Service>.fromOpaque(refcon).takeUnretainedValue()
            svc.handleDeviceRemoved(iterator)
        }, selfPtr, &removedIterator)
        drainIterator(removedIterator)
    }

    private func stopDeviceWatcher() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notificationPort { IONotificationPortDestroy(port); notificationPort = nil }
    }

    private func handleDeviceAdded(_ iterator: io_iterator_t) {
        var found = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            found = true
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        guard found, connectionState == .disconnected else { return }

        appendLog("ESP32-S3 detected (VID 0x\(String(format: "%04x", Self.ESP_VID)))")
        usbQueue.async { [weak self] in
            self?.connectToDevice()
        }
    }

    private func handleDeviceRemoved(_ iterator: io_iterator_t) {
        drainIterator(iterator)
        if connectionState != .disconnected {
            closeDevice()
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .disconnected
                self?.deviceName = ""
                self?.appendLog("ESP32-S3 disconnected")
            }
        }
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 { IOObjectRelease(service); service = IOIteratorNext(iterator) }
    }

    // MARK: - USB Connection

    private func connectToDevice() {
        var matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as! [String: Any]
        matchingDict[kUSBVendorID] = Self.ESP_VID
        matchingDict[kUSBProductID] = Self.ESP_PID

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict as CFDictionary, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        let usbDevice = IOIteratorNext(iterator)
        guard usbDevice != 0 else { return }
        defer { IOObjectRelease(usbDevice) }

        // Get device interface
        var score: Int32 = 0
        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?

        guard IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID_ESP, kIOCFPlugInInterfaceID_ESP, &pluginInterface, &score) == KERN_SUCCESS,
              let plugin = pluginInterface else { return }

        var deviceInterfacePtr: UnsafeMutableRawPointer?
        _ = plugin.pointee?.pointee.QueryInterface(
            plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID_ESP), &deviceInterfacePtr
        )
        plugin.pointee?.pointee.Release(plugin)

        guard let rawDeviceInterface = deviceInterfacePtr else { return }
        let devIface = rawDeviceInterface.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceStruct942>?.self)
        self.deviceInterface = devIface

        // Open device
        guard devIface.pointee?.pointee.USBDeviceOpenSeize(devIface) == KERN_SUCCESS else {
            DispatchQueue.main.async { [weak self] in
                self?.appendLog("Failed to open ESP32 USB device")
            }
            return
        }

        // Find CDC serial interface (interface 2 on ESP32-S3 JTAG/serial)
        if findCDCInterface() {
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .connected
                self?.deviceName = "ESP32-S3 JTAG/Serial"
                self?.appendLog("Connected to ESP32-S3")
                self?.appendLog("  Pipe In: \(self?.pipeIn ?? 0), Pipe Out: \(self?.pipeOut ?? 0)")
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.appendLog("Failed to find CDC serial interface")
                self?.connectionState = .error
            }
        }
    }

    private func findCDCInterface() -> Bool {
        guard let devIface = deviceInterface else { return false }

        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kUSBVendorSpecificClass),  // 0xFF for vendor-specific
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var iterator: io_iterator_t = 0

        // Try vendor-specific first, then CDC
        for interfaceClass: UInt16 in [0xFF, 0x0A, 0x02] {
            request.bInterfaceClass = interfaceClass
            guard devIface.pointee?.pointee.CreateInterfaceIterator(devIface, &request, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var interfaceService = IOIteratorNext(iterator)
            while interfaceService != 0 {
                defer { IOObjectRelease(interfaceService); interfaceService = IOIteratorNext(iterator) }

                var score: Int32 = 0
                var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?

                guard IOCreatePlugInInterfaceForService(interfaceService, kIOUSBInterfaceUserClientTypeID_ESP, kIOCFPlugInInterfaceID_ESP, &pluginInterface, &score) == KERN_SUCCESS,
                      let plugin = pluginInterface else { continue }

                var ifacePtr: UnsafeMutableRawPointer?
                _ = plugin.pointee?.pointee.QueryInterface(
                    plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID_ESP), &ifacePtr
                )
                plugin.pointee?.pointee.Release(plugin)

                guard let rawIface = ifacePtr else { continue }
                let iface = rawIface.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBInterfaceStruct550>?.self)

                guard iface.pointee?.pointee.USBInterfaceOpenSeize(iface) == KERN_SUCCESS else { continue }

                // Find bulk endpoints
                var numEndpoints: UInt8 = 0
                iface.pointee?.pointee.GetNumEndpoints(iface, &numEndpoints)

                var foundIn: UInt8 = 0
                var foundOut: UInt8 = 0

                for ep: UInt8 in 1...max(numEndpoints, 1) {
                    var direction: UInt8 = 0
                    var number: UInt8 = 0
                    var transferType: UInt8 = 0
                    var maxPacketSize: UInt16 = 0
                    var interval: UInt8 = 0

                    iface.pointee?.pointee.GetPipeProperties(iface, ep, &direction, &number, &transferType, &maxPacketSize, &interval)

                    // Bulk endpoints (transferType 2)
                    if transferType == 2 {
                        if direction == 1 { foundIn = ep }  // IN
                        if direction == 0 { foundOut = ep }  // OUT
                    }
                }

                if foundIn > 0 && foundOut > 0 {
                    self.interfaceInterface = iface
                    self.pipeIn = foundIn
                    self.pipeOut = foundOut
                    return true
                }

                iface.pointee?.pointee.USBInterfaceClose(iface)
            }
        }

        return false
    }

    private func closeDevice() {
        if let iface = interfaceInterface {
            iface.pointee?.pointee.USBInterfaceClose(iface)
            interfaceInterface = nil
        }
        if let dev = deviceInterface {
            dev.pointee?.pointee.USBDeviceClose(dev)
            deviceInterface = nil
        }
        pipeIn = 0
        pipeOut = 0
    }

    // MARK: - Serial Read/Write

    /// Write data to ESP32 serial port.
    func serialWrite(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let iface = interfaceInterface, pipeOut > 0 else {
            completion(.failure(NSError(domain: "ESP32", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }

        usbQueue.async {
            var mutableData = data
            let kr = mutableData.withUnsafeMutableBytes { ptr -> IOReturn in
                guard let base = ptr.baseAddress else { return kIOReturnError }
                return iface.pointee?.pointee.WritePipe(iface, self.pipeOut, base, UInt32(data.count)) ?? kIOReturnError
            }

            DispatchQueue.main.async {
                if kr == kIOReturnSuccess {
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(domain: "ESP32", code: Int(kr), userInfo: [NSLocalizedDescriptionKey: "USB write failed: \(kr)"])))
                }
            }
        }
    }

    /// Read data from ESP32 serial port.
    func serialRead(maxBytes: Int = 512, timeout: UInt32 = 3000, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let iface = interfaceInterface, pipeIn > 0 else {
            completion(.failure(NSError(domain: "ESP32", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }

        usbQueue.async {
            var buffer = [UInt8](repeating: 0, count: maxBytes)
            var bytesRead = UInt32(maxBytes)

            let kr = iface.pointee?.pointee.ReadPipeTO(iface, self.pipeIn, &buffer, &bytesRead, timeout, timeout) ?? kIOReturnError

            DispatchQueue.main.async {
                if kr == kIOReturnSuccess && bytesRead > 0 {
                    completion(.success(Data(buffer[0..<Int(bytesRead)])))
                } else if kr == kIOReturnSuccess {
                    completion(.success(Data()))
                } else {
                    completion(.failure(NSError(domain: "ESP32", code: Int(kr), userInfo: [NSLocalizedDescriptionKey: "USB read failed: \(kr)"])))
                }
            }
        }
    }

    /// Send a string command to ESP32 serial console.
    func send(_ command: String) {
        let data = Data("\(command)\r\n".utf8)
        appendLog("> \(command)")
        serialWrite(data) { [weak self] result in
            if case .failure(let err) = result {
                self?.appendLog("Send failed: \(err.localizedDescription)")
            }
        }
    }

    /// Read available serial data and log it.
    func readConsole() {
        serialRead(maxBytes: 1024, timeout: 500) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    for line in text.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        self.appendLog(line.trimmingCharacters(in: .newlines))
                    }
                }
            case .failure:
                break // timeout is normal
            }
        }
    }

    // MARK: - SLIP Framing (ROM Bootloader Protocol)

    /// Encode data with SLIP framing.
    private static func slipEncode(_ data: Data) -> Data {
        var encoded = Data([SLIP_END])
        for byte in data {
            switch byte {
            case SLIP_END: encoded.append(contentsOf: [SLIP_ESC, SLIP_ESC_END])
            case SLIP_ESC: encoded.append(contentsOf: [SLIP_ESC, SLIP_ESC_ESC])
            default: encoded.append(byte)
            }
        }
        encoded.append(SLIP_END)
        return encoded
    }

    /// Decode SLIP-framed data.
    private static func slipDecode(_ data: Data) -> Data {
        var decoded = Data()
        var escaped = false
        for byte in data {
            if escaped {
                switch byte {
                case SLIP_ESC_END: decoded.append(SLIP_END)
                case SLIP_ESC_ESC: decoded.append(SLIP_ESC)
                default: decoded.append(byte)
                }
                escaped = false
            } else if byte == SLIP_ESC {
                escaped = true
            } else if byte != SLIP_END {
                decoded.append(byte)
            }
        }
        return decoded
    }

    // MARK: - ROM Bootloader Commands

    /// Build a bootloader command packet.
    private func buildCommand(opcode: UInt8, data: Data, checksum: UInt32 = 0) -> Data {
        var packet = Data()
        packet.append(0x00) // direction: request
        packet.append(opcode)
        var size = UInt16(data.count).littleEndian
        packet.append(Data(bytes: &size, count: 2))
        var chk = checksum.littleEndian
        packet.append(Data(bytes: &chk, count: 4))
        packet.append(data)
        return Self.slipEncode(packet)
    }

    /// Send SYNC command to enter bootloader mode.
    func syncBootloader(completion: @escaping (Result<Void, Error>) -> Void) {
        var syncData = Data([0x07, 0x07, 0x12, 0x20])
        syncData.append(contentsOf: [UInt8](repeating: 0x55, count: 32))

        let packet = buildCommand(opcode: Self.ESP_SYNC, data: syncData)
        serialWrite(packet) { [weak self] result in
            if case .failure(let err) = result { completion(.failure(err)); return }

            // Read response
            self?.serialRead(maxBytes: 512, timeout: 3000) { result in
                switch result {
                case .success(let data):
                    if data.contains(0x01) { // response marker
                        completion(.success(()))
                    } else {
                        completion(.failure(NSError(domain: "ESP32", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sync failed — no response"])))
                    }
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    /// Flash a firmware binary to the ESP32.
    func flash(firmware: Data, offset: UInt32 = 0x10000, completion: @escaping (Result<Void, Error>) -> Void) {
        guard connectionState == .connected else {
            completion(.failure(NSError(domain: "ESP32", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }

        connectionState = .flashing
        flashProgress = 0
        appendLog("Flashing \(firmware.count) bytes to 0x\(String(format: "%x", offset))...")

        let blockSize = 4096
        let totalBlocks = (firmware.count + blockSize - 1) / blockSize

        // Step 1: FLASH_BEGIN
        var beginData = Data(count: 16)
        beginData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(firmware.count).littleEndian, toByteOffset: 0, as: UInt32.self)  // size
            ptr.storeBytes(of: UInt32(totalBlocks).littleEndian, toByteOffset: 4, as: UInt32.self)     // blocks
            ptr.storeBytes(of: UInt32(blockSize).littleEndian, toByteOffset: 8, as: UInt32.self)       // block size
            ptr.storeBytes(of: offset.littleEndian, toByteOffset: 12, as: UInt32.self)                 // offset
        }

        let beginPacket = buildCommand(opcode: Self.ESP_FLASH_BEGIN, data: beginData)
        serialWrite(beginPacket) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result {
                self.connectionState = .connected
                completion(.failure(err))
                return
            }

            // Step 2: FLASH_DATA blocks
            self.flashBlocks(firmware: firmware, blockSize: blockSize, blockIndex: 0, totalBlocks: totalBlocks, completion: completion)
        }
    }

    private func flashBlocks(firmware: Data, blockSize: Int, blockIndex: Int, totalBlocks: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard blockIndex < totalBlocks else {
            // Step 3: FLASH_END
            let endPacket = buildCommand(opcode: Self.ESP_FLASH_END, data: Data([0x00, 0x00, 0x00, 0x00]))
            serialWrite(endPacket) { [weak self] result in
                self?.connectionState = .connected
                self?.flashProgress = 1.0
                self?.appendLog("Flash complete!")
                completion(result)
            }
            return
        }

        let start = blockIndex * blockSize
        let end = min(start + blockSize, firmware.count)
        var block = firmware[start..<end]

        // Pad to block size
        if block.count < blockSize {
            block.append(contentsOf: [UInt8](repeating: 0xFF, count: blockSize - block.count))
        }

        // Checksum (XOR of all bytes with seed 0xEF)
        var checksum: UInt32 = 0xEF
        for byte in block { checksum ^= UInt32(byte) }

        // Build FLASH_DATA header: size(4) + seq(4) + 0(4) + 0(4)
        var header = Data(count: 16)
        header.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(block.count).littleEndian, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt32(blockIndex).littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        header.append(block)

        let packet = buildCommand(opcode: Self.ESP_FLASH_DATA, data: header, checksum: checksum)
        serialWrite(packet) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result {
                self.connectionState = .connected
                completion(.failure(err))
                return
            }

            self.flashProgress = Double(blockIndex + 1) / Double(totalBlocks)
            self.appendLog("  Block \(blockIndex + 1)/\(totalBlocks) (\(Int(self.flashProgress * 100))%)")

            // Next block
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.flashBlocks(firmware: firmware, blockSize: blockSize, blockIndex: blockIndex + 1, totalBlocks: totalBlocks, completion: completion)
            }
        }
    }

    // MARK: - Console Commands

    func handleCommand(_ parts: [String]) -> String {
        let sub = parts.count > 1 ? parts[1].lowercased() : "status"
        switch sub {
        case "status":
            return "ESP32: \(connectionState.rawValue)\(deviceName.isEmpty ? "" : " — \(deviceName)")"
        case "read":
            readConsole()
            return "Reading ESP32 serial..."
        case "log":
            let n = min(log.count, 20)
            return n > 0 ? log.suffix(n).joined(separator: "\n") : "(empty log)"
        case "send":
            guard parts.count >= 3 else { return "Usage: esp32 send <command>" }
            let cmd = parts[2...].joined(separator: " ")
            send(cmd)
            return "Sent: \(cmd)"
        case "sync":
            syncBootloader { [weak self] result in
                switch result {
                case .success: self?.appendLog("Bootloader sync OK")
                case .failure(let err): self?.appendLog("Sync failed: \(err.localizedDescription)")
                }
            }
            return "Syncing bootloader..."
        case "flash":
            guard parts.count >= 3 else { return "Usage: esp32 flash <firmware.bin>" }
            let path = parts[2...].joined(separator: " ")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return "Cannot read: \(path)"
            }
            flash(firmware: data) { [weak self] result in
                switch result {
                case .success: self?.appendLog("Flash complete")
                case .failure(let err): self?.appendLog("Flash failed: \(err.localizedDescription)")
                }
            }
            return "Flashing \(data.count) bytes..."
        default:
            return "Usage: esp32 [status|read|send|sync|flash]"
        }
    }
}
