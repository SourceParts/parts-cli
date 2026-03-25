#if os(macOS)
import Foundation
import IOKit
import IOKit.usb

// MARK: - IOKit USB UUIDs (C macros not bridged to Swift)

// These match the UUIDs in FELService.swift — declared private per-file
// because Swift does not export C #define macros from IOKit headers.
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

// MARK: - SWD Probe Errors

enum SWDProbeError: LocalizedError {
    case deviceNotFound
    case interfaceNotFound
    case openFailed(kern_return_t)
    case sendFailed(kern_return_t)
    case recvFailed(kern_return_t)
    case dapError(String)
    case noTarget

    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "Debug probe not found"
        case .interfaceNotFound: return "CMSIS-DAP v2 bulk interface not found"
        case .openFailed(let kr): return "Failed to open probe: \(kr)"
        case .sendFailed(let kr): return "USB bulk send failed: \(kr)"
        case .recvFailed(let kr): return "USB bulk recv failed: \(kr)"
        case .dapError(let msg): return "DAP error: \(msg)"
        case .noTarget: return "No SWD target detected"
        }
    }
}

/// SWD Debug Probe states — controls UI status indicator color.
enum ProbeState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning"        // Red — looking for SWD target
    case connected = "Connected"      // Yellow — SWD link established
    case ready = "Ready"              // Green — target identified, ready to load
    case error = "Error"

    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .scanning: return "red"
        case .connected: return "yellow"
        case .ready: return "green"
        case .error: return "red"
        }
    }
}

/// SWD target info read via CMSIS-DAP.
struct SWDTarget {
    var idcode: UInt32 = 0
    var designer: String = ""
    var partNumber: String = ""
    var revision: UInt8 = 0
}

/// Known target IDCODE table for identification.
private let knownTargets: [(idcode: UInt32, designer: String, part: String)] = [
    (0x0BC11477, "ARM", "Cortex-M0 (RP2040)"),
    (0x2BA01477, "ARM", "Cortex-M3/M4"),
    (0x6BA02477, "ARM", "Cortex-M33 (nRF5340/nRF54H20)"),
    (0x1BA01477, "ARM", "Cortex-M3 (STM32F1)"),
    (0x3BA00477, "ARM", "Cortex-M4 (STM32F4)"),
]

/// Service for detecting and communicating with a Raspberry Pi Pico Debug Probe
/// (stock debugprobe firmware) via CMSIS-DAP v2 over USB bulk endpoints.
class SWDProbeService: ObservableObject {
    @Published var state: ProbeState = .disconnected
    @Published var target: SWDTarget?
    @Published var probeInfo: String = ""

    // Pico Debug Probe USB identifiers
    private static let probeVID: UInt16 = 0x2E8A  // Raspberry Pi
    private static let probePIDs: [UInt16] = [
        0x0004, // Raspberry Pi Debug Probe (CMSIS-DAP)
        0x0005, // Raspberry Pi Debug Probe (CMSIS-DAP v2)
        0x000C, // Pico running debugprobe firmware (alt)
        0x000F, // Pico running debugprobe firmware (alt)
    ]

    // PocketPC SWD target: STM32F103C8 keyboard controller
    private static let expectedDPIDR: UInt32 = 0x1BA01477  // ARM Cortex-M3
    private static let expectedIDCODE: UInt32 = 0x3BA00477  // STM32F103

    private var scanTimer: Timer?
    private var usbNotification: io_iterator_t = 0
    private var probeDevice: io_service_t = 0

    // CMSIS-DAP v2 command IDs
    private static let DAP_INFO: UInt8 = 0x00
    private static let DAP_CONNECT: UInt8 = 0x02
    private static let DAP_DISCONNECT: UInt8 = 0x03
    private static let DAP_SWJ_PINS: UInt8 = 0x10
    private static let DAP_SWJ_CLOCK: UInt8 = 0x11
    private static let DAP_SWD_CONFIGURE: UInt8 = 0x13
    private static let DAP_TRANSFER: UInt8 = 0x05
    private static let DAP_LED: UInt8 = 0x01

    // DAP_INFO sub-IDs
    private static let INFO_VENDOR: UInt8 = 0x01
    private static let INFO_PRODUCT: UInt8 = 0x02
    private static let INFO_SER_NUM: UInt8 = 0x03
    private static let INFO_FW_VER: UInt8 = 0x04
    private static let INFO_CAPABILITIES: UInt8 = 0x00

    // CMSIS-DAP v2 bulk packet size
    private static let DAP_PACKET_SIZE = 512

    // USB bulk I/O state
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>>?
    private var interfaceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>>?
    private var pipeIn: UInt8 = 0
    private var pipeOut: UInt8 = 0
    private let usbQueue = DispatchQueue(label: "parts.studio.swd.usb", qos: .userInitiated)
    private let usbTimeoutMS: UInt32 = 5000  // 5 second timeout for DAP commands

    init() {}

    deinit {
        closeUSBDevice()
    }

    // MARK: - Probe Detection

    /// Start scanning for the debug probe USB device.
    func startScanning() {
        guard state == .disconnected else { return }
        state = .scanning

        // Poll for USB device presence
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForProbe()
        }
        checkForProbe()
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        closeUSBDevice()
        state = .disconnected
        target = nil
        probeInfo = ""
    }

    private func checkForProbe() {
        // Use IOKit to find the debug probe
        var matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as! [String: Any]
        matchingDict[kUSBVendorID] = Self.probeVID

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict as CFDictionary, &iterator)
        guard kr == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            // Check PID
            var pidRef: Unmanaged<CFTypeRef>?
            IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0).map { pidRef = $0 }
            guard let pidNum = pidRef?.takeRetainedValue() as? NSNumber else { continue }
            let pid = pidNum.uint16Value

            if Self.probePIDs.contains(pid) {
                // Found the debug probe
                state = .connected
                probeInfo = "Pico Debug Probe (VID:0x\(String(format: "%04x", Self.probeVID)) PID:0x\(String(format: "%04x", pid)))"
                scanTimer?.invalidate()
                scanTimer = nil

                // Try to read target IDCODE via USB bulk
                readTargetIDCode()
                return
            }
        }
    }

    // MARK: - USB Bulk I/O (IOKit)

    /// Open the USB device, claim the CMSIS-DAP v2 bulk interface, and find IN/OUT pipes.
    private func openUSBDevice() throws {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = Int(Self.probeVID)

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { throw SWDProbeError.deviceNotFound }
        defer { IOObjectRelease(iterator) }

        // Find the first matching PID
        var foundDevice: io_service_t = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var pidRef: Unmanaged<CFTypeRef>?
            IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0).map { pidRef = $0 }
            if let pidNum = pidRef?.takeRetainedValue() as? NSNumber,
               Self.probePIDs.contains(pidNum.uint16Value) {
                foundDevice = service
                break
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        guard foundDevice != 0 else { throw SWDProbeError.deviceNotFound }
        defer { IOObjectRelease(foundDevice) }

        // Get plugin interface
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        let pluginResult = IOCreatePlugInInterfaceForService(
            foundDevice,
            kIOUSBDeviceUserClientTypeID_,
            kIOCFPlugInInterfaceID_,
            &plugInInterface,
            &score
        )
        guard pluginResult == KERN_SUCCESS, let plugin = plugInInterface else {
            throw SWDProbeError.openFailed(pluginResult)
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
            throw SWDProbeError.openFailed(Int32(queryResult ?? -1))
        }

        deviceInterface = rawPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface>.self
        )

        // Open the device
        let openResult = deviceInterface!.pointee.pointee.USBDeviceOpen(deviceInterface!)
        guard openResult == KERN_SUCCESS else {
            throw SWDProbeError.openFailed(openResult)
        }

        // Configure
        var configNum: UInt8 = 0
        deviceInterface!.pointee.pointee.GetConfiguration(deviceInterface!, &configNum)
        if configNum == 0 {
            deviceInterface!.pointee.pointee.SetConfiguration(deviceInterface!, 1)
        }
    }

    /// Iterate USB interfaces to find the CMSIS-DAP v2 bulk interface and open it.
    /// CMSIS-DAP v2 uses vendor-specific class (0xFF) with bulk endpoints.
    private func findAndOpenInterface() throws {
        guard let dev = deviceInterface else { throw SWDProbeError.deviceNotFound }

        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var iterator: io_iterator_t = 0
        let kr = dev.pointee.pointee.CreateInterfaceIterator(dev, &request, &iterator)
        guard kr == KERN_SUCCESS else { throw SWDProbeError.interfaceNotFound }
        defer { IOObjectRelease(iterator) }

        // Iterate all interfaces looking for one with bulk IN + OUT endpoints.
        // The debug probe exposes multiple interfaces (CDC, HID, bulk CMSIS-DAP v2).
        // The CMSIS-DAP v2 bulk interface is vendor-specific class 0xFF.
        var usbInterface = IOIteratorNext(iterator)
        while usbInterface != 0 {
            defer { IOObjectRelease(usbInterface) }

            if tryOpenBulkInterface(usbInterface) {
                return  // Success — pipeIn and pipeOut are set
            }

            usbInterface = IOIteratorNext(iterator)
        }

        throw SWDProbeError.interfaceNotFound
    }

    /// Attempt to open a single USB interface and check for bulk IN/OUT pipes.
    /// Returns true if this is the CMSIS-DAP v2 bulk interface.
    private func tryOpenBulkInterface(_ usbInterface: io_service_t) -> Bool {
        var score: Int32 = 0
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        IOCreatePlugInInterfaceForService(
            usbInterface,
            kIOUSBInterfaceUserClientTypeID_,
            kIOCFPlugInInterfaceID_,
            &plugInInterface,
            &score
        )
        guard let plugin = plugInInterface else { return false }
        defer { plugin.pointee?.pointee.Release(plugin) }

        var ifacePtr: UnsafeMutableRawPointer?
        plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID_),
            &ifacePtr
        )
        guard let rawPtr = ifacePtr else { return false }

        let iface = rawPtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBInterfaceInterface>.self
        )

        // Check interface class — CMSIS-DAP v2 bulk is vendor-specific (0xFF)
        var ifaceClass: UInt8 = 0
        iface.pointee.pointee.GetInterfaceClass(iface, &ifaceClass)
        guard ifaceClass == 0xFF else {
            iface.pointee.pointee.Release(iface)
            return false
        }

        // Open the interface
        let openResult = iface.pointee.pointee.USBInterfaceOpen(iface)
        guard openResult == KERN_SUCCESS else {
            iface.pointee.pointee.Release(iface)
            return false
        }

        // Find bulk endpoints
        var numEndpoints: UInt8 = 0
        iface.pointee.pointee.GetNumEndpoints(iface, &numEndpoints)

        var foundIn: UInt8 = 0
        var foundOut: UInt8 = 0

        for i: UInt8 in 1...numEndpoints {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0

            iface.pointee.pointee.GetPipeProperties(
                iface, i,
                &direction, &number, &transferType, &maxPacketSize, &interval
            )

            // Bulk transfer type = 2
            if transferType == 2 {
                if direction == 1 { // IN
                    foundIn = i
                } else { // OUT
                    foundOut = i
                }
            }
        }

        guard foundIn != 0 && foundOut != 0 else {
            iface.pointee.pointee.USBInterfaceClose(iface)
            iface.pointee.pointee.Release(iface)
            return false
        }

        // This is the CMSIS-DAP v2 bulk interface
        interfaceInterface = iface
        pipeIn = foundIn
        pipeOut = foundOut
        return true
    }

    /// Close all USB handles.
    private func closeUSBDevice() {
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

    /// Send raw bytes to the bulk OUT endpoint.
    private func bulkSend(_ data: Data) throws {
        guard let iface = interfaceInterface else { throw SWDProbeError.deviceNotFound }

        let kr = data.withUnsafeBytes { ptr in
            iface.pointee.pointee.WritePipeTO(
                iface, pipeOut,
                UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                UInt32(data.count),
                usbTimeoutMS, usbTimeoutMS
            )
        }
        guard kr == KERN_SUCCESS else { throw SWDProbeError.sendFailed(kr) }
    }

    /// Receive bytes from the bulk IN endpoint.
    private func bulkRecv(_ maxLength: Int) throws -> Data {
        guard let iface = interfaceInterface else { throw SWDProbeError.deviceNotFound }

        var buffer = Data(count: maxLength)
        var actualLength = UInt32(maxLength)
        let kr = buffer.withUnsafeMutableBytes { ptr in
            iface.pointee.pointee.ReadPipeTO(
                iface, pipeIn,
                ptr.baseAddress!,
                &actualLength,
                usbTimeoutMS, usbTimeoutMS
            )
        }
        guard kr == KERN_SUCCESS else { throw SWDProbeError.recvFailed(kr) }
        return Data(buffer.prefix(Int(actualLength)))
    }

    // MARK: - CMSIS-DAP v2 Protocol

    /// Send a CMSIS-DAP command and return the response.
    /// CMSIS-DAP v2 uses 512-byte USB bulk packets. The command is zero-padded
    /// to the full packet size. Response is read as a single 512-byte bulk transfer.
    private func sendDAP(_ command: [UInt8]) throws -> [UInt8] {
        // Pad command to 512-byte CMSIS-DAP v2 packet
        var packet = Data(count: Self.DAP_PACKET_SIZE)
        for (i, byte) in command.enumerated() {
            packet[i] = byte
        }

        try bulkSend(packet)
        let response = try bulkRecv(Self.DAP_PACKET_SIZE)
        return Array(response)
    }

    // MARK: - SWD Communication

    /// Open USB, connect via SWD, and read the target IDCODE.
    private func readTargetIDCode() {
        usbQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.openUSBDevice()
                try self.findAndOpenInterface()

                // 1. DAP_Connect — port=1 (SWD mode)
                let connectResp = try self.sendDAP([Self.DAP_CONNECT, 0x01])
                guard connectResp.count >= 2 && connectResp[0] == Self.DAP_CONNECT else {
                    throw SWDProbeError.dapError("DAP_Connect: invalid response")
                }
                guard connectResp[1] == 0x01 else {
                    throw SWDProbeError.dapError("DAP_Connect failed: port=\(connectResp[1]) (expected SWD=1)")
                }

                // 2. DAP_SWJ_Clock — 1 MHz = 0x000E1000 (little-endian: 00 10 0E 00)
                let clockResp = try self.sendDAP([Self.DAP_SWJ_CLOCK, 0x00, 0x10, 0x0E, 0x00])
                guard clockResp.count >= 2 && clockResp[0] == Self.DAP_SWJ_CLOCK && clockResp[1] == 0x00 else {
                    throw SWDProbeError.dapError("DAP_SWJ_Clock failed")
                }

                // 3. DAP_SWD_Configure — turnaround=1, no data phase on FAULT/WAIT
                let swdCfgResp = try self.sendDAP([Self.DAP_SWD_CONFIGURE, 0x00])
                guard swdCfgResp.count >= 2 && swdCfgResp[0] == Self.DAP_SWD_CONFIGURE && swdCfgResp[1] == 0x00 else {
                    throw SWDProbeError.dapError("DAP_SWD_Configure failed")
                }

                // 4. DAP_Transfer — read DP IDCODE register (reg 0, read)
                //    Format: [CMD, DAP_Index, TransferCount, TransferRequest, ...]
                //    TransferRequest: 0x02 = DP read, register 0 (IDCODE)
                let xferResp = try self.sendDAP([
                    Self.DAP_TRANSFER,
                    0x00,       // DAP index
                    0x01,       // Transfer count = 1
                    0x02,       // Read DP register 0 (IDCODE)
                ])
                guard xferResp.count >= 7 && xferResp[0] == Self.DAP_TRANSFER else {
                    throw SWDProbeError.dapError("DAP_Transfer: invalid response (len=\(xferResp.count))")
                }

                let transferCount = xferResp[1]
                let transferResponse = xferResp[2]
                guard transferCount == 1 && (transferResponse & 0x07) == 0x01 else {
                    throw SWDProbeError.dapError(
                        "DAP_Transfer failed: count=\(transferCount) response=0x\(String(format: "%02x", transferResponse))")
                }

                // Parse IDCODE from response bytes [3..6] (little-endian)
                let idcode = UInt32(xferResp[3])
                    | (UInt32(xferResp[4]) << 8)
                    | (UInt32(xferResp[5]) << 16)
                    | (UInt32(xferResp[6]) << 24)

                // Identify the target
                let identified = identifyTarget(idcode: idcode)

                DispatchQueue.main.async {
                    self.target = identified
                    self.state = .ready
                    self.probeInfo += " | Target: 0x\(String(format: "%08X", idcode))"
                    if !identified.designer.isEmpty {
                        self.probeInfo += " (\(identified.designer) \(identified.partNumber))"
                    }
                }

            } catch {
                self.closeUSBDevice()
                DispatchQueue.main.async {
                    self.state = .error
                    self.probeInfo += " | Error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Identify a target from its IDCODE using the known targets table.
    private func identifyTarget(idcode: UInt32) -> SWDTarget {
        // IDCODE fields (ARM CoreSight):
        //   [31:28] = revision
        //   [27:12] = PARTNO
        //   [11:1]  = designer (JEDEC)
        //   [0]     = always 1
        let revision = UInt8((idcode >> 28) & 0x0F)

        // Check known targets
        for entry in knownTargets {
            if entry.idcode == idcode {
                return SWDTarget(
                    idcode: idcode,
                    designer: entry.designer,
                    partNumber: entry.part,
                    revision: revision
                )
            }
        }

        // Unknown target — report raw fields
        let partno = (idcode >> 12) & 0xFFFF
        let designer = (idcode >> 1) & 0x7FF
        return SWDTarget(
            idcode: idcode,
            designer: "JEDEC:0x\(String(format: "%03X", designer))",
            partNumber: "PARTNO:0x\(String(format: "%04X", partno))",
            revision: revision
        )
    }

    /// Set the probe's LED state via CMSIS-DAP DAP_LED command.
    func setLED(index: UInt8, on: Bool) {
        usbQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.interfaceInterface != nil else { return }

            do {
                let resp = try self.sendDAP([Self.DAP_LED, index, on ? 0x01 : 0x00])
                guard resp.count >= 2 && resp[0] == Self.DAP_LED && resp[1] == 0x00 else {
                    DispatchQueue.main.async {
                        self.probeInfo += " | LED command failed"
                    }
                    return
                }
            } catch {
                DispatchQueue.main.async {
                    self.probeInfo += " | LED error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Console Commands

    /// Handle "swd" console commands.
    func handleCommand(_ parts: [String]) -> String {
        guard parts.count >= 1 else { return "Usage: swd [scan|stop|status|info|led]" }

        let sub = parts.count > 1 ? parts[1].lowercased() : "status"
        switch sub {
        case "scan":
            startScanning()
            return "Scanning for debug probe..."
        case "stop":
            stopScanning()
            return "Probe scanning stopped"
        case "status":
            var result = "Probe: \(state.rawValue)"
            if !probeInfo.isEmpty { result += " — \(probeInfo)" }
            if let t = target {
                result += "\nTarget IDCODE: 0x\(String(format: "%08x", t.idcode))"
                if !t.designer.isEmpty { result += " (\(t.designer) \(t.partNumber))" }
            }
            return result
        case "info":
            return probeInfo.isEmpty ? "No probe connected" : probeInfo
        case "led":
            let on = parts.count > 2 && parts[2].lowercased() == "on"
            setLED(index: 0x00, on: on)
            return "LED \(on ? "on" : "off")"
        default:
            return "Unknown swd command: \(sub). Try: scan, stop, status, info, led"
        }
    }
}
#endif
