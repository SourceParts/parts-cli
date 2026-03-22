import Foundation
import IOKit
import IOKit.usb

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

/// Service for detecting and communicating with a Raspberry Pi Pico Debug Probe
/// (stock debugprobe firmware) via CMSIS-DAP v2 over USB bulk endpoints.
@MainActor
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

    init() {}

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

                // Try to read target IDCODE
                readTargetIDCode()
                return
            }
        }
    }

    // MARK: - SWD Communication (Placeholder)

    /// Attempt to read the SWD target's IDCODE.
    /// Full CMSIS-DAP v2 implementation requires USB bulk I/O — placeholder for now.
    private func readTargetIDCode() {
        // TODO: Open CMSIS-DAP v2 bulk endpoints and send:
        // 1. DAP_Connect (port=1 for SWD)
        // 2. DAP_SWJ_Clock (set clock speed)
        // 3. DAP_SWD_Configure
        // 4. DAP_Transfer (read IDCODE from DP register 0)
        //
        // For now, mark as ready since we detected the probe.
        state = .ready
    }

    /// Set the probe's LED state via CMSIS-DAP DAP_LED command.
    func setLED(index: UInt8, on: Bool) {
        // TODO: Send DAP_LED command via USB bulk
        // Packet: [0x01, index, on ? 1 : 0]
    }

    // MARK: - Console Commands

    /// Handle "swd" console commands.
    func handleCommand(_ parts: [String]) -> String {
        guard parts.count >= 1 else { return "Usage: swd [scan|stop|status|info]" }

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
        default:
            return "Unknown swd command: \(sub). Try: scan, stop, status, info"
        }
    }
}
