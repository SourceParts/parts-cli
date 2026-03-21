import Foundation
import IOKit
import IOKit.usb

// MARK: - IOKit USB UUIDs (C macros not bridged to Swift)

private let kIOUSBDeviceUserClientTypeID_: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
        0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOCFPlugInInterfaceID_: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
        0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

private let kIOUSBDeviceInterfaceID_: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
        0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceUserClientTypeID_: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4,
        0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceInterfaceID_: CFUUID =
    CFUUIDGetConstantUUIDWithBytes(nil,
        0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4,
        0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

// MARK: - FEL Protocol Constants

private let AW_USB_VENDOR_ID: Int = 0x1F3A
private let AW_USB_PRODUCT_ID: Int = 0xEFE8

private let AW_USB_READ: UInt16 = 0x11
private let AW_USB_WRITE: UInt16 = 0x12

private let AW_FEL_VERSION: UInt32 = 0x001
private let AW_FEL_1_WRITE: UInt32 = 0x101
private let AW_FEL_1_EXEC: UInt32 = 0x102
private let AW_FEL_1_READ: UInt32 = 0x103

private let AW_USB_MAX_BULK_SEND = 512 * 1024

private let DRAM_BASE: UInt32 = 0x40000000

private let SPL_LEN_LIMIT: UInt32 = 0x8000

private let LCODE_ARM_WORDS = 12
private let LCODE_ARM_SIZE = LCODE_ARM_WORDS * 4
private let LCODE_MAX_TOTAL = 0x100
private let LCODE_MAX_WORDS = LCODE_MAX_TOTAL - LCODE_ARM_WORDS

// MARK: - FEL Errors

enum FELError: LocalizedError {
    case deviceNotFound
    case interfaceNotFound
    case openFailed(kern_return_t)
    case sendFailed(kern_return_t)
    case recvFailed(kern_return_t)
    case protocolError(String)
    case invalidSPL(String)
    case invalidUBoot(String)
    case protectedAddress(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "FEL device not found"
        case .interfaceNotFound: return "USB interface not found"
        case .openFailed(let kr): return "Failed to open device: \(kr)"
        case .sendFailed(let kr): return "USB send failed: \(kr)"
        case .recvFailed(let kr): return "USB receive failed: \(kr)"
        case .protocolError(let msg): return "FEL protocol error: \(msg)"
        case .invalidSPL(let msg): return "Invalid SPL: \(msg)"
        case .invalidUBoot(let msg): return "Invalid U-Boot: \(msg)"
        case .protectedAddress(let msg): return "Protected address: \(msg)"
        case .timeout: return "USB timeout"
        }
    }
}

// MARK: - FEL Service

/// Native IOKit USB implementation of the Allwinner FEL protocol.
/// Replaces sunxi-fel CLI and WebUSB dependencies with direct USB access.
class FELService: ObservableObject {
    @Published var connectionState: FELConnectionState = .disconnected
    @Published var deviceInfo: FELDeviceInfo?
    @Published var log: [String] = []

    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>>?
    private var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>>?
    private var pipeIn: UInt8 = 0
    private var pipeOut: UInt8 = 0
    private let usbQueue = DispatchQueue(label: "parts.studio.fel.usb", qos: .userInitiated)

    private var heartbeatTimer: Timer?
    private var consecutiveErrors = 0
    private let maxConsecutiveErrors = 3

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    init() {
        startDeviceWatcher()
    }

    deinit {
        stopHeartbeat()
        closeDevice()
        stopDeviceWatcher()
    }

    // MARK: - Device Watching (IOKit Notifications)

    private func startDeviceWatcher() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = AW_USB_VENDOR_ID
        matchingDict[kUSBProductID] = AW_USB_PRODUCT_ID

        // Watch for device arrival
        let addDict = matchingDict.mutableCopy() as! NSMutableDictionary
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            addDict,
            { refcon, iterator in
                guard let refcon = refcon else { return }
                let service = Unmanaged<FELService>.fromOpaque(refcon).takeUnretainedValue()
                service.handleDeviceAdded(iterator)
            },
            selfPtr,
            &addedIterator
        )
        // Drain initial iterator
        handleDeviceAdded(addedIterator)

        // Watch for device removal
        let removeDict = matchingDict.mutableCopy() as! NSMutableDictionary
        IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            removeDict,
            { refcon, iterator in
                guard let refcon = refcon else { return }
                let service = Unmanaged<FELService>.fromOpaque(refcon).takeUnretainedValue()
                service.handleDeviceRemoved(iterator)
            },
            selfPtr,
            &removedIterator
        )
        // Drain initial iterator
        drainIterator(removedIterator)
    }

    private func handleDeviceAdded(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            appendLog("FEL device detected (VID 0x1F3A)")
            // Try to connect on background queue
            usbQueue.async { [weak self] in
                self?.connectToDevice()
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func handleDeviceRemoved(_ iterator: io_iterator_t) {
        drainIterator(iterator)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.connectionState == .connected {
                self.appendLog("FEL device disconnected")
                self.connectionState = .disconnected
                self.deviceInfo = nil
                self.stopHeartbeat()
                self.closeDevice()
            }
        }
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func stopDeviceWatcher() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    // MARK: - USB Transport (Private)

    /// Connect to the FEL device, claim interface, identify pipes.
    private func connectToDevice() {
        DispatchQueue.main.async { self.connectionState = .connecting }

        do {
            try openUSBDevice()
            try findAndOpenInterface()

            // Read version to identify SoC
            let version = try getVersionSync()
            guard let socInfo = SoCInfoTable.lookup(socId: version.socId) else {
                throw FELError.protocolError("Unknown SoC ID: 0x\(version.socIdHex)")
            }

            let info = FELDeviceInfo(version: version, socInfo: socInfo, sid: nil)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.deviceInfo = info
                self.connectionState = .connected
                self.consecutiveErrors = 0
                self.appendLog("Connected: \(socInfo.name) (0x\(version.socIdHex))")
                self.startHeartbeat()
            }

            // Read SID in background
            readSIDAsync(socInfo: socInfo)

        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .error
                self?.appendLog("Connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func openUSBDevice() throws {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = AW_USB_VENDOR_ID
        matchingDict[kUSBProductID] = AW_USB_PRODUCT_ID

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { throw FELError.deviceNotFound }
        defer { IOObjectRelease(iterator) }

        let usbDevice = IOIteratorNext(iterator)
        guard usbDevice != 0 else { throw FELError.deviceNotFound }
        defer { IOObjectRelease(usbDevice) }

        // Get plugin interface
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        let pluginResult = IOCreatePlugInInterfaceForService(
            usbDevice,
            kIOUSBDeviceUserClientTypeID_,
            kIOCFPlugInInterfaceID_,
            &plugInInterface,
            &score
        )
        guard pluginResult == KERN_SUCCESS, let plugin = plugInInterface else {
            throw FELError.openFailed(pluginResult)
        }
        defer { plugin.pointee?.pointee.Release(plugin) }

        // Get device interface
        var deviceInterfacePtr: UnsafeMutableRawPointer?
        let queryResult = plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID_),
            &deviceInterfacePtr
        )
        guard queryResult == S_OK, let rawPtr = deviceInterfacePtr else {
            throw FELError.openFailed(Int32(queryResult ?? -1))
        }

        deviceInterface = rawPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface>.self
        )

        // Open the device
        let openResult = deviceInterface!.pointee.pointee.USBDeviceOpen(deviceInterface!)
        guard openResult == KERN_SUCCESS else {
            throw FELError.openFailed(openResult)
        }

        // Configure
        var configNum: UInt8 = 0
        deviceInterface!.pointee.pointee.GetConfiguration(deviceInterface!, &configNum)
        if configNum == 0 {
            deviceInterface!.pointee.pointee.SetConfiguration(deviceInterface!, 1)
        }
    }

    private func findAndOpenInterface() throws {
        guard let dev = deviceInterface else { throw FELError.deviceNotFound }

        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var iterator: io_iterator_t = 0
        let kr = dev.pointee.pointee.CreateInterfaceIterator(dev, &request, &iterator)
        guard kr == KERN_SUCCESS else { throw FELError.interfaceNotFound }
        defer { IOObjectRelease(iterator) }

        let usbInterface = IOIteratorNext(iterator)
        guard usbInterface != 0 else { throw FELError.interfaceNotFound }
        defer { IOObjectRelease(usbInterface) }

        // Get plugin
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        IOCreatePlugInInterfaceForService(
            usbInterface,
            kIOUSBInterfaceUserClientTypeID_,
            kIOCFPlugInInterfaceID_,
            &plugInInterface,
            &score
        )
        guard let plugin = plugInInterface else { throw FELError.interfaceNotFound }
        defer { plugin.pointee?.pointee.Release(plugin) }

        var ifacePtr: UnsafeMutableRawPointer?
        plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID_),
            &ifacePtr
        )
        guard let rawPtr = ifacePtr else { throw FELError.interfaceNotFound }

        interfaceInterface = rawPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBInterfaceInterface>.self
        )

        // Open the interface
        let openResult = interfaceInterface!.pointee.pointee.USBInterfaceOpen(interfaceInterface!)
        guard openResult == KERN_SUCCESS else { throw FELError.openFailed(openResult) }

        // Find bulk endpoints
        var numEndpoints: UInt8 = 0
        interfaceInterface!.pointee.pointee.GetNumEndpoints(interfaceInterface!, &numEndpoints)

        for i in 1...numEndpoints {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0

            interfaceInterface!.pointee.pointee.GetPipeProperties(
                interfaceInterface!, i,
                &direction, &number, &transferType, &maxPacketSize, &interval
            )

            // Bulk transfer type = 2
            if transferType == 2 {
                if direction == 1 { // IN
                    pipeIn = i
                } else { // OUT
                    pipeOut = i
                }
            }
        }

        guard pipeIn != 0 && pipeOut != 0 else {
            throw FELError.interfaceNotFound
        }
    }

    private func closeDevice() {
        if let iface = interfaceInterface {
            iface.pointee.pointee.USBInterfaceClose(iface)
            iface.pointee.pointee.Release(iface)
            interfaceInterface = nil
        }
        if let dev = deviceInterface {
            dev.pointee.pointee.USBDeviceClose(dev)
            dev.pointee.pointee.Release(dev)
            deviceInterface = nil
        }
        pipeIn = 0
        pipeOut = 0
    }

    /// Send data to the OUT bulk endpoint.
    private func bulkSend(_ data: Data) throws {
        guard let iface = interfaceInterface else { throw FELError.deviceNotFound }

        var offset = 0
        while offset < data.count {
            let chunkSize = min(AW_USB_MAX_BULK_SEND, data.count - offset)
            let chunk = data[offset..<offset + chunkSize]
            let kr = chunk.withUnsafeBytes { ptr in
                iface.pointee.pointee.WritePipe(
                    iface, pipeOut,
                    UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                    UInt32(chunkSize)
                )
            }
            guard kr == KERN_SUCCESS else { throw FELError.sendFailed(kr) }
            offset += chunkSize
        }
    }

    /// Receive data from the IN bulk endpoint.
    private func bulkRecv(_ length: Int) throws -> Data {
        guard let iface = interfaceInterface else { throw FELError.deviceNotFound }

        var buffer = Data(count: length)
        var actualLength = UInt32(length)
        let kr = buffer.withUnsafeMutableBytes { ptr in
            iface.pointee.pointee.ReadPipe(
                iface, pipeIn,
                ptr.baseAddress!,
                &actualLength
            )
        }
        guard kr == KERN_SUCCESS else { throw FELError.recvFailed(kr) }
        return Data(buffer.prefix(Int(actualLength)))
    }

    // MARK: - Protocol Layer (Private)

    /// Build and send the 32-byte AW USB request.
    private func awSendUSBRequest(type: UInt16, length: UInt32) throws {
        var data = Data(count: 32)
        data.withUnsafeMutableBytes { ptr in
            // Signature "AWUC" at offset 0, big-endian
            ptr.storeBytes(of: UInt32(0x41575543).bigEndian, toByteOffset: 0, as: UInt32.self)
            // Length at offset 8, little-endian
            ptr.storeBytes(of: length.littleEndian, toByteOffset: 8, as: UInt32.self)
            // Unknown byte 0x0C at offset 15
            ptr[15] = 0x0C
            // Request type at offset 16, little-endian
            ptr.storeBytes(of: type.littleEndian, toByteOffset: 16, as: UInt16.self)
            // Length again at offset 18, little-endian
            ptr.storeBytes(of: length.littleEndian, toByteOffset: 18, as: UInt32.self)
        }
        try bulkSend(data)
    }

    /// Build and send a 16-byte FEL request.
    private func awSendFELRequest(type: UInt32, address: UInt32, length: UInt32) throws {
        var data = Data(count: 16)
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: type.littleEndian, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: address.littleEndian, toByteOffset: 4, as: UInt32.self)
            ptr.storeBytes(of: length.littleEndian, toByteOffset: 8, as: UInt32.self)
            // pad at offset 12 stays zero
        }
        try awUSBWrite(data: data, length: UInt32(data.count))
    }

    /// Read USB response (status/data).
    private func awReadUSBResponse(length: Int) throws -> Data {
        return try bulkRecv(length)
    }

    /// USB-level write: send request header, send data, read 13-byte status.
    private func awUSBWrite(data: Data, length: UInt32) throws {
        try awSendUSBRequest(type: AW_USB_WRITE, length: length)
        try bulkSend(data)
        _ = try awReadUSBResponse(length: 13)
    }

    /// USB-level read: send request header, read data, read 13-byte status.
    private func awUSBRead(length: UInt32) throws -> Data {
        try awSendUSBRequest(type: AW_USB_READ, length: length)
        let response = try awReadUSBResponse(length: Int(length))
        _ = try awReadUSBResponse(length: 13)
        return response
    }

    /// Read FEL status (8 bytes).
    private func awReadFELStatus() throws {
        _ = try awUSBRead(length: 8)
    }

    /// FEL read: send FEL_READ request, read data via USB, read status.
    private func awFELRead(offset: UInt32, length: UInt32) throws -> Data {
        try awSendFELRequest(type: AW_FEL_1_READ, address: offset, length: length)
        let response = try awUSBRead(length: length)
        try awReadFELStatus()
        return response
    }

    /// FEL write: send FEL_WRITE request, write data via USB, read status.
    private func awFELWrite(data: Data, offset: UInt32) throws {
        try awSendFELRequest(type: AW_FEL_1_WRITE, address: offset, length: UInt32(data.count))
        try awUSBWrite(data: data, length: UInt32(data.count))
        try awReadFELStatus()
    }

    /// FEL execute: send FEL_EXEC request, read status.
    private func awFELExecute(offset: UInt32) throws {
        try awSendFELRequest(type: AW_FEL_1_EXEC, address: offset, length: 0)
        try awReadFELStatus()
    }

    // MARK: - Public API

    /// Get FEL version (called on USB queue).
    private func getVersionSync() throws -> FELVersion {
        try awSendFELRequest(type: AW_FEL_VERSION, address: 0, length: 0)
        let data = try awUSBRead(length: 32)
        try awReadFELStatus()

        guard let version = FELVersion(data: data) else {
            throw FELError.protocolError("Invalid version response")
        }
        return version
    }

    /// Read SID asynchronously and update deviceInfo.
    private func readSIDAsync(socInfo: SoCInfo) {
        usbQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let sid = try self.readSID(socInfo: socInfo)
                DispatchQueue.main.async {
                    self.deviceInfo?.sid = sid
                    self.appendLog("SID: \(sid)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("SID read failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Read the 128-bit Serial ID from SID registers.
    private func readSID(socInfo: SoCInfo) throws -> String {
        guard socInfo.sidBase != 0 else { return "unavailable" }

        var words: [UInt32]

        if socInfo.sidFix {
            // Use ARM thunk code to read SID registers
            words = try readSIDViaThunk(socInfo: socInfo)
        } else {
            // Read SID directly from memory
            let data = try awFELRead(
                offset: socInfo.sidBase + socInfo.sidOffset,
                length: 16
            )
            words = data.withUnsafeBytes { ptr in
                (0..<4).map { ptr.load(fromByteOffset: $0 * 4, as: UInt32.self).littleEndian }
            }
        }

        return words.map { String(format: "%08x", $0) }.joined(separator: ":")
    }

    /// Read SID via ARM thunk (for SoCs that need the register-based workaround).
    private func readSIDViaThunk(socInfo: SoCInfo) throws -> [UInt32] {
        // ARM code that reads SID registers via the control register
        var armCode = Data(count: 76)
        let instructions: [(Int, UInt32)] = [
            (0, 0xe59f0040),   // ldr   r0, [pc, #64]     ; load SID base
            (4, 0xe3a01000),   // mov   r1, #0
            (8, 0xe28f303c),   // add   r3, pc, #60       ; result buffer
            // sid_read_loop:
            (12, 0xe1a02801),  // lsl   r2, r1, #16
            (16, 0xe3822b2b),  // orr   r2, r2, #44032
            (20, 0xe3822002),  // orr   r2, r2, #2
            (24, 0xe5802040),  // str   r2, [r0, #64]
            // sid_read_wait:
            (28, 0xe5902040),  // ldr   r2, [r0, #64]
            (32, 0xe3120002),  // tst   r2, #2
            (36, 0x1afffffc),  // bne   sid_read_wait
            (40, 0xe5902060),  // ldr   r2, [r0, #96]
            (44, 0xe7832001),  // str   r2, [r3, r1]
            (48, 0xe2811004),  // add   r1, r1, #4
            (52, 0xe3510010),  // cmp   r1, #16
            (56, 0x3afffff3),  // bcc   sid_read_loop
            (60, 0xe3a02000),  // mov   r2, #0
            (64, 0xe5802040),  // str   r2, [r0, #64]
            (68, 0xe12fff1e),  // bx    lr
        ]
        armCode.withUnsafeMutableBytes { ptr in
            for (offset, value) in instructions {
                ptr.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self)
            }
            ptr.storeBytes(of: socInfo.sidBase.littleEndian, toByteOffset: 72, as: UInt32.self)
        }

        try awFELWrite(data: armCode, offset: socInfo.scratchAddr)
        try awFELExecute(offset: socInfo.scratchAddr)
        let result = try awFELRead(offset: socInfo.scratchAddr + 76, length: 16)

        return result.withUnsafeBytes { ptr in
            (0..<4).map { ptr.load(fromByteOffset: $0 * 4, as: UInt32.self).littleEndian }
        }
    }

    /// Read memory at the given address. Runs on the USB queue.
    func readMemory(address: UInt32, length: UInt32, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        let validation = FELAddressValidator.validateRead(address: address, length: length, soc: socInfo)
        if case .protected(let name) = validation {
            completion(.failure(FELError.protectedAddress(name)))
            return
        }

        usbQueue.async { [weak self] in
            do {
                let data = try self?.awFELRead(offset: address, length: length)
                DispatchQueue.main.async { completion(.success(data ?? Data())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Write data to memory at the given address. Runs on the USB queue.
    func writeMemory(address: UInt32, data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        let validation = FELAddressValidator.validateWrite(address: address, length: UInt32(data.count), soc: socInfo)
        if case .protected(let name) = validation {
            completion(.failure(FELError.protectedAddress(name)))
            return
        }

        usbQueue.async { [weak self] in
            do {
                try self?.awFELWrite(data: data, offset: address)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Execute code at the given address. Runs on the USB queue.
    func executeAt(address: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        usbQueue.async { [weak self] in
            do {
                try self?.awFELExecute(offset: address)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Write and execute SPL. Validates eGON header and checksum.
    func writeSPL(data splData: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        usbQueue.async { [weak self] in
            do {
                try self?.writeSPLSync(data: splData, socInfo: socInfo)
                DispatchQueue.main.async {
                    self?.appendLog("SPL loaded and executed successfully")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func writeSPLSync(data splData: Data, socInfo: SoCInfo) throws {
        guard splData.count >= 32 else {
            throw FELError.invalidSPL("Too small")
        }

        // Verify eGON.BT0 signature at offset 4
        let eGONSig = String(data: splData[4..<12], encoding: .ascii) ?? ""
        guard eGONSig == "eGON.BT0" else {
            throw FELError.invalidSPL("eGON header not found (got: \(eGONSig))")
        }

        // Verify checksum
        let splCheckValue = splData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 12, as: UInt32.self).littleEndian
        }
        let splLen = splData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 16, as: UInt32.self).littleEndian
        }

        guard splLen <= splData.count && splLen % 4 == 0 else {
            throw FELError.invalidSPL("Bad length in eGON header")
        }

        var checksum: UInt32 = 2 &* splCheckValue &- 0x5F0A6C39
        splData.withUnsafeBytes { ptr in
            for i in stride(from: 0, to: Int(splLen), by: 4) {
                checksum = checksum &- ptr.load(fromByteOffset: i, as: UInt32.self).littleEndian
            }
        }
        guard checksum == 0 else {
            throw FELError.invalidSPL("Checksum failed")
        }

        appendLogSync("SPL verified: \(splLen) bytes, eGON.BT0")

        // Enable L2 cache if needed
        if socInfo.needsL2EN {
            try enableL2Cache(socInfo: socInfo)
        }

        // Write SPL data, handling swap buffers
        var len = Int(splLen)
        var buf = 0
        var curAddr = socInfo.splAddr > 0 ? socInfo.splAddr : socInfo.scratchAddr
        let swapBuffers = socInfo.swapBuffers

        for swap in swapBuffers {
            if len > 0 && curAddr < swap.buf1 {
                let tmp = min(Int(swap.buf1 - curAddr), len)
                try awFELWrite(data: splData[buf..<buf + tmp], offset: curAddr)
                curAddr += UInt32(tmp)
                buf += tmp
                len -= tmp
            }
            if len > 0 && curAddr == swap.buf1 {
                let tmp = min(Int(swap.size), len)
                try awFELWrite(data: splData[buf..<buf + tmp], offset: swap.buf2)
                curAddr += UInt32(tmp)
                buf += tmp
                len -= tmp
            }
        }

        // Write remaining SPL data
        if len > 0 {
            try awFELWrite(data: splData[buf..<buf + len], offset: curAddr)
        }

        // Build and write thunk code
        let thunkCode = buildSPLThunk(socInfo: socInfo)
        try awFELWrite(data: thunkCode, offset: socInfo.thunkAddr)
        try awFELExecute(offset: socInfo.thunkAddr)

        appendLogSync("SPL executing...")

        // Wait for DRAM init
        Thread.sleep(forTimeInterval: 0.25)

        // Verify: read back and check for "eGON.FEL" response
        let splAddr = socInfo.splAddr > 0 ? socInfo.splAddr : socInfo.scratchAddr
        let response = try awFELRead(offset: splAddr + 4, length: 8)
        let responseStr = String(data: response, encoding: .ascii) ?? ""
        guard responseStr == "eGON.FEL" else {
            throw FELError.invalidSPL("Execution failed, got: \(responseStr)")
        }
    }

    /// Build the FEL-to-SPL thunk code with swap buffer data appended.
    private func buildSPLThunk(socInfo: SoCInfo) -> Data {
        // The thunk is 264 bytes of ARM code + 4 bytes SPL addr + swap buffer entries + terminator
        var thunk = Data(count: 264)

        // ARM thunk instructions (from fel.js fel_to_spl_thunk)
        let instructions: [(Int, UInt32)] = [
            (0, 0xea000015),   // b  setup_stack
            // stack_begin (NOPs for stack space)
            (4, 0xe1a00000), (8, 0xe1a00000), (12, 0xe1a00000), (16, 0xe1a00000),
            (20, 0xe1a00000), (24, 0xe1a00000), (28, 0xe1a00000), (32, 0xe1a00000),
            // stack_end
            (36, 0xe1a00000),
            // swap_all_buffers
            (40, 0xe28f40dc),  // add  r4, pc, #220
            // swap_next_buffer
            (44, 0xe4940004),  // ldr  r0, [r4], #4
            (48, 0xe4941004),  // ldr  r1, [r4], #4
            (52, 0xe4946004),  // ldr  r6, [r4], #4
            (56, 0xe3560000),  // cmp  r6, #0
            (60, 0x012fff1e),  // bxeq lr
            // swap_next_word
            (64, 0xe5902000),  // ldr  r2, [r0]
            (68, 0xe5913000),  // ldr  r3, [r1]
            (72, 0xe2566004),  // subs r6, r6, #4
            (76, 0xe4812004),  // str  r2, [r1], #4
            (80, 0xe4803004),  // str  r3, [r0], #4
            (84, 0x1afffff9),  // bne  swap_next_word
            (88, 0xeafffff3),  // b    swap_next_buffer
            // setup_stack
            (92, 0xe59f80a4),  // ldr  r8, [pc, #164]
            (96, 0xe24f0044),  // sub  r0, pc, #68
            (100, 0xe520d004), // str  sp, [r0, #-4]!
            (104, 0xe1a0d000), // mov  sp, r0
            (108, 0xe10f2000), // mrs  r2, CPSR
            (112, 0xe92d4004), // push {r2, lr}
            (116, 0xe38220c0), // orr  r2, r2, #192
            (120, 0xe121f002), // msr  CPSR_c, r2
            (124, 0xee112f10), // mrc  15, 0, r2, cr1, cr0, {0}
            (128, 0xe3013004), // movw r3, #4100
            (132, 0xe1120003), // tst  r2, r3
            (136, 0x1a000012), // bne  cache_is_unsupported
            (140, 0xebffffe5), // bl   swap_all_buffers
            // verify_checksum
            (144, 0xe3067c39), // movw r7, #27705
            (148, 0xe3457f0a), // movt r7, #24330
            (152, 0xe1a00008), // mov  r0, r8
            (156, 0xe5905010), // ldr  r5, [r0, #16]
            // check_next_word
            (160, 0xe4902004), // ldr  r2, [r0], #4
            (164, 0xe2555004), // subs r5, r5, #4
            (168, 0xe0877002), // add  r7, r7, r2
            (172, 0x1afffffb), // bne  check_next_word
            (176, 0xe598200c), // ldr  r2, [r8, #12]
            (180, 0xe0577082), // subs r7, r7, r2, lsl #1
            (184, 0x1a00000a), // bne  checksum_is_bad
            (188, 0xe304262e), // movw r2, #17966
            (192, 0xe3442c45), // movt r2, #19525
            (196, 0xe5882008), // str  r2, [r8, #8]
            (200, 0xf57ff04f), // dsb  sy
            (204, 0xf57ff06f), // isb  sy
            (208, 0xe12fff38), // blx  r8
            (212, 0xea000006), // b    return_to_fel
            // cache_is_unsupported
            (216, 0xe3032f2e), // movw r2, #16174
            (220, 0xe3432f3f), // movt r2, #16191
            (224, 0xe5882008), // str  r2, [r8, #8]
            (228, 0xea000003), // b    return_to_fel_noswap
            // checksum_is_bad
            (232, 0xe304222e), // movw r2, #16942
            (236, 0xe3442441), // movt r2, #17473
            (240, 0xe5882008), // str  r2, [r8, #8]
            // return_to_fel
            (244, 0xebffffcb), // bl   swap_all_buffers
            // return_to_fel_noswap
            (248, 0xe8bd4004), // pop  {r2, lr}
            (252, 0xe121f002), // msr  CPSR_c, r2
            (256, 0xe59dd000), // ldr  sp, [sp]
            (260, 0xe12fff1e), // bx   lr
        ]

        thunk.withUnsafeMutableBytes { ptr in
            for (offset, value) in instructions {
                ptr.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self)
            }
        }

        // Append SPL address
        let splAddr = socInfo.splAddr > 0 ? socInfo.splAddr : socInfo.scratchAddr
        var splAddrData = Data(count: 4)
        splAddrData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: splAddr.littleEndian, toByteOffset: 0, as: UInt32.self)
        }
        thunk.append(splAddrData)

        // Append swap buffer entries
        for swap in socInfo.swapBuffers {
            thunk.append(swap.data)
        }

        // Terminator (12 zero bytes)
        thunk.append(Data(count: 12))

        return thunk
    }

    /// Enable L2 cache (for A10/A13/A20).
    private func enableL2Cache(socInfo: SoCInfo) throws {
        var armCode = Data(count: 16)
        let instructions: [(Int, UInt32)] = [
            (0, 0xee112f30),   // mrc  15, 0, r2, cr1, cr0, {1}
            (4, 0xe3822002),   // orr  r2, r2, #2
            (8, 0xee012f30),   // mcr  15, 0, r2, cr1, cr0, {1}
            (12, 0xe12fff1e),  // bx   lr
        ]
        armCode.withUnsafeMutableBytes { ptr in
            for (offset, value) in instructions {
                ptr.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self)
            }
        }
        try awFELWrite(data: armCode, offset: socInfo.scratchAddr)
        try awFELExecute(offset: socInfo.scratchAddr)
    }

    /// Write U-Boot image. Validates mkimage header and CRC32.
    func writeUBoot(data ubootData: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        usbQueue.async { [weak self] in
            do {
                try self?.writeUBootSync(data: ubootData)
                DispatchQueue.main.async {
                    self?.appendLog("U-Boot image written successfully")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func writeUBootSync(data ubootData: Data) throws {
        let headerSize = 64
        guard ubootData.count > headerSize else {
            throw FELError.invalidUBoot("Image too small")
        }

        // Check mkimage magic
        let magic = ubootData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: UInt32.self).bigEndian
        }
        guard magic == 0x27051956 else {
            throw FELError.invalidUBoot("Bad magic number: 0x\(String(format: "%08x", magic))")
        }

        // Check ARM architecture
        let arch = ubootData[29]
        guard arch == 2 else {
            throw FELError.invalidUBoot("Wrong architecture (expected ARM)")
        }

        // Check firmware type
        let imageType = ubootData[30]
        guard imageType == 5 else {
            throw FELError.invalidUBoot("Expected firmware type, got \(imageType)")
        }

        // Verify header CRC
        let storedHCRC = ubootData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 4, as: UInt32.self).bigEndian
        }
        var headerForCRC = Data(ubootData.prefix(headerSize))
        headerForCRC.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt32(0), toByteOffset: 4, as: UInt32.self)
        }
        let computedHCRC = crc32(headerForCRC)
        guard storedHCRC == computedHCRC else {
            throw FELError.invalidUBoot("Header CRC mismatch")
        }

        let dataSize = ubootData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 12, as: UInt32.self).bigEndian
        }
        let loadAddr = ubootData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 16, as: UInt32.self).bigEndian
        }

        // Verify data CRC
        let storedDCRC = ubootData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 24, as: UInt32.self).bigEndian
        }
        let imageData = ubootData[headerSize..<headerSize + Int(dataSize)]
        let computedDCRC = crc32(Data(imageData))
        guard storedDCRC == computedDCRC else {
            throw FELError.invalidUBoot("Data CRC mismatch")
        }

        appendLogSync("U-Boot: \(dataSize) bytes -> 0x\(String(format: "%08x", loadAddr))")

        // Write the image data (skip header) to the load address
        try awFELWrite(data: Data(imageData), offset: loadAddr)
    }

    /// Boot the device using RMR warm reset (for AArch64 SoCs like A64).
    func startBoot(entryPoint: UInt32? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        usbQueue.async { [weak self] in
            do {
                if socInfo.rvbarReg != 0 {
                    try self?.rmrRequest(entryPoint: entryPoint ?? DRAM_BASE, socInfo: socInfo)
                } else {
                    // For 32-bit SoCs, just execute at the entry point
                    try self?.awFELExecute(offset: entryPoint ?? DRAM_BASE)
                }
                DispatchQueue.main.async {
                    self?.appendLog("Boot initiated")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// RMR warm reset — writes entry point to RVBAR and triggers reset.
    private func rmrRequest(entryPoint: UInt32, socInfo: SoCInfo) throws {
        let rmrMode: UInt32 = (1 << 1) | 1 // RR + AA64

        var armCode = Data(count: 60)
        let instructions: [(Int, UInt32)] = [
            (0, 0xe59f0028),   // ldr  r0, [rvbar_reg]
            (4, 0xe59f1028),   // ldr  r1, [entry_point]
            (8, 0xe5801000),   // str  r1, [r0]
            (12, 0xf57ff04f),  // dsb  sy
            (16, 0xf57ff06f),  // isb  sy
            (20, 0xe59f101c),  // ldr  r1, [rmr_mode]
            (24, 0xee1c0f50),  // mrc  15, 0, r0, cr12, cr0, {2}
            (28, 0xe1800001),  // orr  r0, r0, r1
            (32, 0xee0c0f50),  // mcr  15, 0, r0, cr12, cr0, {2}
            (36, 0xf57ff06f),  // isb  sy
            (40, 0xe320f003),  // wfi
            (44, 0xeafffffd),  // b    wfi
        ]
        armCode.withUnsafeMutableBytes { ptr in
            for (offset, value) in instructions {
                ptr.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self)
            }
            ptr.storeBytes(of: socInfo.rvbarReg.littleEndian, toByteOffset: 48, as: UInt32.self)
            ptr.storeBytes(of: entryPoint.littleEndian, toByteOffset: 52, as: UInt32.self)
            ptr.storeBytes(of: rmrMode.littleEndian, toByteOffset: 56, as: UInt32.self)
        }

        appendLogSync("RMR: entry=0x\(String(format: "%08x", entryPoint)) rvbar=0x\(String(format: "%08x", socInfo.rvbarReg))")
        try awFELWrite(data: armCode, offset: socInfo.scratchAddr)
        try awFELExecute(offset: socInfo.scratchAddr)
    }

    /// Full boot sequence: load SPL, wait for DRAM, write U-Boot, start boot.
    func bootPocketPC(splData: Data, ubootData: Data? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let socInfo = deviceInfo?.socInfo else {
            completion(.failure(FELError.deviceNotFound))
            return
        }

        usbQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                self.appendLogSync("=== FEL Boot Sequence ===")

                // Step 1: Write and execute SPL
                try self.writeSPLSync(data: splData, socInfo: socInfo)

                // Step 2: Wait for DRAM init
                self.appendLogSync("Waiting for DRAM init...")
                Thread.sleep(forTimeInterval: 1.5)

                // Step 3: Write U-Boot if provided
                if let ubootData = ubootData, ubootData.count > 64 {
                    try self.writeUBootSync(data: ubootData)
                }

                // Step 4: Start boot
                if socInfo.rvbarReg != 0 {
                    try self.rmrRequest(entryPoint: DRAM_BASE, socInfo: socInfo)
                }

                DispatchQueue.main.async {
                    self.appendLog("Boot sequence complete")
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    self.appendLog("Boot failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }

    /// Manually trigger a connection attempt.
    func connect() {
        usbQueue.async { [weak self] in
            self?.connectToDevice()
        }
    }

    /// Disconnect from the device.
    func disconnect() {
        stopHeartbeat()
        closeDevice()
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .disconnected
            self?.deviceInfo = nil
            self?.appendLog("Disconnected")
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.heartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func heartbeat() {
        usbQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                _ = try self.getVersionSync()
                DispatchQueue.main.async {
                    self.consecutiveErrors = 0
                }
            } catch {
                DispatchQueue.main.async {
                    self.consecutiveErrors += 1
                    if self.consecutiveErrors >= self.maxConsecutiveErrors {
                        self.appendLog("Heartbeat lost (\(self.consecutiveErrors) errors)")
                        self.connectionState = .disconnected
                        self.deviceInfo = nil
                        self.stopHeartbeat()
                        self.closeDevice()
                    }
                }
            }
        }
    }

    // MARK: - CRC32

    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var tmp = UInt32(i)
            for _ in 0..<8 {
                tmp = (tmp & 1 != 0) ? (0xEDB88320 ^ (tmp >> 1)) : (tmp >> 1)
            }
            return tmp
        }
    }()

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = Self.crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - Logging

    func appendLog(_ msg: String) {
        let entry = "[\(Self.timestamp())] \(msg)"
        if Thread.isMainThread {
            log.append(entry)
            if log.count > 500 { log = Array(log.suffix(500)) }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.log.append(entry)
                if let count = self?.log.count, count > 500 {
                    self?.log = Array(self!.log.suffix(500))
                }
            }
        }
    }

    private func appendLogSync(_ msg: String) {
        let entry = "[\(Self.timestamp())] \(msg)"
        DispatchQueue.main.async { [weak self] in
            self?.log.append(entry)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
