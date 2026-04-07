#if os(macOS)
import Foundation
import IOKit
import IOKit.usb
import IOKit.serial

/// Service for ESLR (ESP32-S3 Dual LoRa Radio) devices connected via CP2102 USB-to-Serial.
///
/// Detects CP2102 via IOKit notifications, opens the serial port with POSIX termios,
/// and communicates with the ESP32 interactive console at 115200 baud.
@MainActor
class ESLRService: ObservableObject {
    @Published var connectionState: ESLRConnectionState = .disconnected
    @Published var deviceInfo: ESLRDeviceInfo?
    @Published var log: [String] = []
    @Published var serialPort: String?

    // CP2102 USB identifiers (Silicon Labs)
    static let CP2102_VID: Int = 0x10C4
    static let CP2102_PID: Int = 0xEA60

    // Serial port state
    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let serialQueue = DispatchQueue(label: "parts.studio.eslr.serial", qos: .userInitiated)
    private var lineBuffer = ""
    private var responseLines: [String] = []
    private var responseCompletion: (([String]) -> Void)?
    private var responseTimer: DispatchWorkItem?

    // IOKit notification state
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    // Device identification callback (wired by AppState for DeviceRegistry)
    nonisolated(unsafe) var onDeviceIdentified: ((String, String) -> Void)?

    init() {
        startDeviceWatcher()
    }

    nonisolated deinit {}

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(ts)] \(msg)")
        if log.count > 2000 { log.removeFirst(500) }
    }

    // MARK: - IOKit Device Watching

    private func startDeviceWatcher() {
        let matchDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        // Scan for existing serial ports periodically (IOKit serial matching doesn't filter by VID/PID)
        // Use a timer to poll /dev/cu.usbserial-* for simplicity
        startSerialPortPolling()
    }

    private var pollTimer: DispatchSourceTimer?

    private func startSerialPortPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            self?.checkForSerialPort()
        }
        timer.resume()
        pollTimer = timer
    }

    private func checkForSerialPort() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else { return }

        let usbSerials = entries.filter { $0.hasPrefix("cu.usbserial-") }

        if let port = usbSerials.first {
            let path = "/dev/\(port)"
            if serialPort != path && connectionState == .disconnected {
                appendLog("Detected serial port: \(path)")
                serialPort = path
                connect()
            }
        } else if connectionState == .connected && serialPort != nil {
            appendLog("Serial port removed")
            disconnect()
        }
    }

    // MARK: - Serial Port Operations

    func connect() {
        guard let port = serialPort else {
            appendLog("No serial port detected")
            return
        }

        connectionState = .connecting
        appendLog("Opening \(port) at 115200...")

        serialQueue.async { [weak self] in
            guard let self else { return }
            let fd = self.openSerialPort(port)

            DispatchQueue.main.async {
                if fd >= 0 {
                    self.fileDescriptor = fd
                    self.startReading()

                    // Toggle DTR/RTS to wake the ESP32
                    self.serialQueue.async {
                        var status: Int32 = 0
                        ioctl(fd, TIOCMGET, &status)
                        status |= TIOCM_DTR | TIOCM_RTS
                        ioctl(fd, TIOCMSET, &status)
                        usleep(100_000)
                        status &= ~(TIOCM_RTS)
                        ioctl(fd, TIOCMSET, &status)
                    }

                    // Query device info after a short delay to let it settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.queryDeviceInfo()
                    }
                } else {
                    self.connectionState = .error
                    self.appendLog("Failed to open serial port")
                }
            }
        }
    }

    func disconnect() {
        readSource?.cancel()
        readSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        connectionState = .disconnected
        deviceInfo = nil
        serialPort = nil
        appendLog("Disconnected")
    }

    private nonisolated func openSerialPort(_ path: String) -> Int32 {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return -1 }

        // Exclusive access
        if ioctl(fd, TIOCEXCL) != 0 {
            close(fd)
            return -1
        }

        // Clear non-blocking after open
        var flags = fcntl(fd, F_GETFL)
        flags &= ~O_NONBLOCK
        fcntl(fd, F_SETFL, flags)

        // Configure termios: 115200 8N1, no flow control
        var options = termios()
        tcgetattr(fd, &options)

        cfsetispeed(&options, speed_t(B115200))
        cfsetospeed(&options, speed_t(B115200))

        // Input flags: no software flow control, no CR translation
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY | ICRNL | INLCR)

        // Output flags: raw output
        options.c_oflag &= ~tcflag_t(OPOST)

        // Control flags: 8N1, enable receiver, local line
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE)
        options.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)

        // Local flags: raw input (no echo, no canonical, no signals)
        options.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)

        // Read timeout: VMIN=0, VTIME=10 (1 second)
        options.c_cc.16 = 0   // VMIN
        options.c_cc.17 = 10  // VTIME (tenths of a second)

        tcsetattr(fd, TCSANOW, &options)
        tcflush(fd, TCIOFLUSH)

        return fd
    }

    private func startReading() {
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: serialQueue)
        source.setEventHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }

            var buffer = [UInt8](repeating: 0, count: 1024)
            let bytesRead = read(self.fileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
                let text = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    self.processIncoming(text)
                }
            } else if bytesRead == 0 || (bytesRead < 0 && errno != EAGAIN) {
                DispatchQueue.main.async {
                    self.appendLog("Serial port closed")
                    self.disconnect()
                }
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        source.resume()
        readSource = source
    }

    private func processIncoming(_ text: String) {
        lineBuffer += text

        while let newlineRange = lineBuffer.rangeOfCharacter(from: .newlines) {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])

            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }

            // Filter out periodic status lines for response collection
            let isStatusLine = cleaned.hasPrefix("[") && cleaned.contains("heap:") && cleaned.contains("ble:")

            if !isStatusLine {
                appendLog(cleaned)
            }

            // Collect response lines if we're waiting for a command response
            if responseCompletion != nil && !isStatusLine && !cleaned.hasPrefix("esp32>") {
                responseLines.append(cleaned)
            }
        }
    }

    // MARK: - Command Interface

    func sendCommand(_ command: String, timeout: TimeInterval = 2.0, completion: @escaping (String) -> Void) {
        guard fileDescriptor >= 0 else {
            completion("not connected")
            return
        }

        // Cancel any pending response collection
        responseTimer?.cancel()
        if let pending = responseCompletion {
            pending(responseLines)
        }
        responseLines = []

        // Set up response collector
        responseCompletion = { [weak self] lines in
            self?.responseCompletion = nil
            self?.responseTimer = nil
            completion(lines.joined(separator: "\n"))
        }

        // Send the command
        let data = (command + "\r\n").data(using: .utf8) ?? Data()
        serialQueue.async { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            _ = data.withUnsafeBytes { ptr in
                write(self.fileDescriptor, ptr.baseAddress!, data.count)
            }
        }

        // Timeout: deliver whatever we've collected
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let lines = self.responseLines
            self.responseLines = []
            self.responseCompletion?(lines)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timer)
        responseTimer = timer
    }

    func sendRaw(_ text: String) {
        guard fileDescriptor >= 0 else { return }
        let data = (text + "\r\n").data(using: .utf8) ?? Data()
        serialQueue.async { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            _ = data.withUnsafeBytes { ptr in
                write(self.fileDescriptor, ptr.baseAddress!, data.count)
            }
        }
        appendLog("> \(text)")
    }

    private func queryDeviceInfo() {
        sendCommand("info", timeout: 3.0) { [weak self] response in
            guard let self else { return }
            if let info = ESLRDeviceInfo.parse(from: response) {
                var parsed = info
                parsed.serialPort = self.serialPort ?? ""
                self.deviceInfo = parsed
                self.connectionState = .connected
                self.appendLog("Connected: \(parsed.displayName) (MAC: \(parsed.wifiMAC))")

                // Notify DeviceRegistry
                if !parsed.wifiMAC.isEmpty {
                    let mac = parsed.wifiMAC
                    let name = "ESP32-S3-ESLR"
                    self.onDeviceIdentified?(mac, name)
                }
            } else {
                // Device responded but info didn't parse — still connected
                self.connectionState = .connected
                self.appendLog("Connected (could not parse device info)")
            }
        }
    }

    // MARK: - Command Handler (for console server routing)

    func handleCommand(_ parts: [String]) -> String {
        let sub = parts.count > 1 ? parts[1].lowercased() : "status"
        switch sub {
        case "status":
            let state = connectionState.rawValue
            let name = deviceInfo?.displayName ?? "none"
            let port = serialPort ?? "none"
            return "ESLR: \(state) — \(name) [\(port)]"

        case "connect":
            if connectionState == .connected { return "already connected" }
            checkForSerialPort()
            if serialPort != nil {
                connect()
                return "connecting..."
            }
            return "no serial port detected"

        case "disconnect":
            disconnect()
            return "disconnected"

        case "info":
            guard connectionState == .connected else { return "not connected" }
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand("info", timeout: 3.0) { response in
                result = response
                sem.signal()
            }
            sem.wait()
            return result

        case "scan":
            guard connectionState == .connected else { return "not connected" }
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand("scan", timeout: 10.0) { response in
                result = response
                sem.signal()
            }
            sem.wait()
            return result

        case "send":
            guard connectionState == .connected else { return "not connected" }
            guard parts.count >= 3 else { return "usage: eslr send <command>" }
            let cmd = parts[2...].joined(separator: " ")
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand(cmd) { response in
                result = response
                sem.signal()
            }
            sem.wait()
            return result

        case "heap", "temp", "uptime", "ping":
            guard connectionState == .connected else { return "not connected" }
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand(sub) { response in
                result = response
                sem.signal()
            }
            sem.wait()
            return result

        case "led":
            guard connectionState == .connected else { return "not connected" }
            let arg = parts.count >= 3 ? parts[2] : "on"
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand("led \(arg)") { response in
                result = response.isEmpty ? "led \(arg)" : response
                sem.signal()
            }
            sem.wait()
            return result

        case "blink":
            guard connectionState == .connected else { return "not connected" }
            guard parts.count >= 3 else { return "usage: eslr blink <ms>" }
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand("blink \(parts[2])") { response in
                result = response.isEmpty ? "blink \(parts[2])ms" : response
                sem.signal()
            }
            sem.wait()
            return result

        case "reset":
            guard connectionState == .connected else { return "not connected" }
            sendRaw("reset")
            return "reset sent"

        case "ble":
            guard connectionState == .connected else { return "not connected" }
            let sem = DispatchSemaphore(value: 0)
            var result = ""
            sendCommand("ble") { response in
                result = response
                sem.signal()
            }
            sem.wait()
            return result

        case "log":
            let n = min(log.count, 20)
            return n > 0 ? log.suffix(n).joined(separator: "\n") : "(empty log)"

        case "help":
            return """
            ESLR commands:
              eslr status        Connection state
              eslr connect       Open serial port
              eslr disconnect    Close serial port
              eslr info          Query device info
              eslr scan          WiFi network scan
              eslr send <cmd>    Send raw command
              eslr heap          Show memory usage
              eslr temp          Read temperature
              eslr uptime        Show uptime
              eslr led on|off    Control LED
              eslr blink <ms>    Set blink rate
              eslr ping          BLE latency test
              eslr reset         Restart device
              eslr ble           BLE status
              eslr log           Recent log lines
            """

        default:
            return "unknown: eslr \(sub). Try: eslr help"
        }
    }
}
#endif
