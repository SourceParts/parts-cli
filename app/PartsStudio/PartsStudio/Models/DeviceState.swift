import Foundation
import IOKit
import IOKit.usb

/// Tracks PocketPC device state across the full boot lifecycle.
/// Monitors USB device changes and serial output to determine current state.
enum PocketPCState: String, CaseIterable {
    case disconnected   = "Disconnected"
    case fel            = "Recovery Mode"
    case splLoading     = "Loading SPL"
    case dramInit       = "DRAM Init"
    case uboot          = "U-Boot"
    case kernel         = "Kernel Boot"
    case login          = "Login Ready"
    case running        = "Running"
    case massStorage    = "Mass Storage"

    /// Display name based on user role — engineers see "FEL Mode", others see "Recovery Mode".
    func displayName(for role: UserRole) -> String {
        if self == .fel {
            return role.canSeeInternals ? "FEL Mode" : "Recovery Mode"
        }
        return rawValue
    }

    var icon: String {
        switch self {
        case .disconnected: return "bolt.slash"
        case .fel:          return "bolt.fill"
        case .splLoading:   return "arrow.down.to.line"
        case .dramInit:     return "memorychip"
        case .uboot:        return "terminal"
        case .kernel:       return "gear"
        case .login:        return "person.crop.circle"
        case .running:      return "desktopcomputer"
        case .massStorage:  return "externaldrive"
        }
    }

    var color: String {
        switch self {
        case .disconnected: return "secondary"
        case .fel:          return "yellow"
        case .splLoading:   return "orange"
        case .dramInit:     return "orange"
        case .uboot:        return "blue"
        case .kernel:       return "purple"
        case .login:        return "green"
        case .running:      return "green"
        case .massStorage:  return "cyan"
        }
    }
}

/// Monitors USB and serial to track PocketPC state transitions.
class DeviceStateTracker: ObservableObject {
    @Published var state: PocketPCState = .disconnected
    @Published var stateHistory: [(Date, PocketPCState)] = []
    @Published var serialBuffer: String = ""

    private var scanTimer: Timer?
    private var serialHandle: FileHandle?
    private var serialPort: String?

    /// Known USB signatures
    private let felVID = 0x1F3A
    private let felPID = 0xEFE8
    private let wchVID = 0x1A86
    private let cdcVID = 0x0525

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        scan()
    }

    func stopMonitoring() {
        scanTimer?.invalidate()
        scanTimer = nil
        closeSerial()
    }

    private func scan() {
        let devices = scanUSBDevices()

        let hasFEL = devices.contains { $0.0 == felVID && $0.1 == felPID }
        let hasSerial = findSerialPort() != nil
        let hasCDC = devices.contains { $0.0 == cdcVID }

        let newState: PocketPCState

        switch state {
        case .disconnected:
            if hasFEL {
                newState = .fel
            } else if hasCDC {
                newState = .running
            } else {
                newState = .disconnected
            }

        case .fel:
            if !hasFEL && !hasSerial && !hasCDC {
                // Device dropped off USB — boot in progress
                newState = .splLoading
            } else if hasFEL {
                newState = .fel
            } else if hasCDC {
                newState = .running
            } else {
                newState = .fel
            }

        case .splLoading, .dramInit:
            if hasFEL {
                newState = .fel // boot failed, back to FEL
            } else if hasSerial {
                // Serial appeared — U-Boot is talking
                openSerialIfNeeded()
                newState = .uboot
            } else if hasCDC {
                newState = .running
            } else {
                newState = state // still booting
            }

        case .uboot:
            if hasFEL {
                newState = .fel
            } else if hasCDC {
                newState = .running
            } else {
                // Check serial output for kernel boot indicators
                newState = parseSerialState()
            }

        case .kernel:
            if hasCDC {
                newState = .running
            } else {
                newState = parseSerialState()
            }

        case .login:
            if hasCDC {
                newState = .running
            } else {
                newState = .login
            }

        case .running:
            if hasFEL {
                newState = .fel
            } else if !hasCDC {
                newState = .disconnected
            } else {
                newState = .running
            }

        case .massStorage:
            if hasFEL {
                newState = .fel
            } else {
                newState = .massStorage
            }
        }

        if newState != state {
            transition(to: newState)
        }
    }

    private func transition(to newState: PocketPCState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stateHistory.append((Date(), newState))
            if self.stateHistory.count > 50 {
                self.stateHistory = Array(self.stateHistory.suffix(50))
            }
            self.state = newState
        }
    }

    /// Parse serial buffer to determine boot stage.
    private func parseSerialState() -> PocketPCState {
        let buf = serialBuffer.lowercased()
        if buf.contains("login:") || buf.contains("password:") {
            return .login
        }
        if buf.contains("starting kernel") || buf.contains("linux version") ||
           buf.contains("booting linux") || buf.contains("uncompressing") {
            return .kernel
        }
        if buf.contains("u-boot") || buf.contains("hit any key") || buf.contains("=>") {
            return .uboot
        }
        if buf.contains("dram:") || buf.contains("dram size") {
            return .dramInit
        }
        return state
    }

    // MARK: - USB Scanning

    private func scanUSBDevices() -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let vid = getIntProp(service, "idVendor")
            let pid = getIntProp(service, "idProduct")
            result.append((vid, pid))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private func getIntProp(_ service: io_service_t, _ key: String) -> Int {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return 0 }
        return (value as? Int) ?? 0
    }

    // MARK: - Serial

    private func findSerialPort() -> String? {
        let devEntries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return devEntries.first(where: { $0.hasPrefix("cu.usbserial") }).map { "/dev/\($0)" }
    }

    private func openSerialIfNeeded() {
        guard serialHandle == nil, let port = findSerialPort() else { return }
        serialPort = port

        // Set baud rate
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/stty")
        process.arguments = ["-f", port, "115200"]
        try? process.run()
        process.waitUntilExit()

        let fh = FileHandle(forReadingAtPath: port)
        if let fh = fh {
            serialHandle = fh
            fh.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self?.serialBuffer += text
                        // Keep buffer bounded
                        if let buf = self?.serialBuffer, buf.count > 32768 {
                            self?.serialBuffer = String(buf.suffix(16384))
                        }
                    }
                }
            }
        }
    }

    private func closeSerial() {
        serialHandle?.readabilityHandler = nil
        serialHandle?.closeFile()
        serialHandle = nil
        serialPort = nil
    }
}
