import SwiftUI
import PDFKit
import Combine

enum ToolMode: String, CaseIterable, Identifiable {
    case view
    case redact
    case text
    case highlight
    case comment
    case label

    var id: String { rawValue }

    var label: String {
        switch self {
        case .view: return "View"
        case .redact: return "Redact"
        case .text: return "Text"
        case .highlight: return "Highlight"
        case .comment: return "Comment"
        case .label: return "Label"
        }
    }

    var icon: String {
        switch self {
        case .view: return "hand.point.up"
        case .redact: return "rectangle.fill"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .comment: return "bubble.left"
        case .label: return "tag"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .view: return "1"
        case .redact: return "2"
        case .text: return "3"
        case .highlight: return "4"
        case .comment: return "5"
        case .label: return "6"
        }
    }

    var tooltip: String {
        switch self {
        case .view: return "View mode (Cmd+1) — scroll and navigate the PDF"
        case .redact: return "Redact (Cmd+2) — draw black rectangles to permanently hide content"
        case .text: return "Text (Cmd+3) — click to place editable text on the page"
        case .highlight: return "Highlight (Cmd+4) — drag to highlight areas of interest"
        case .comment: return "Comment (Cmd+5) — click to pin a conversation thread to a location"
        case .label: return "Label (Cmd+6) — drag to mark a region with structured data (pin, voltage, etc.)"
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var selectedDatasheet: CachedDatasheet?
    @Published var pdfDocument: PDFDocument?
    @Published var currentPage: Int = 0
    @Published var pageCount: Int = 0
    @Published var currentTool: ToolMode = .view
    @Published var showImportPanel: Bool = false
    @Published var showStripMetadata: Bool = false
    @Published var showExport: Bool = false
    @Published var sidebarSearchText: String = ""
    @Published var selectedECO: ECODocument?
    @Published var selectedIQCItem: IQCItem?
    @Published var showCredits: Bool = false
    @Published var showUSBMonitor: Bool = false
    @Published var showBLE: Bool = false
    @AppStorage("showRightPanel") var showRightPanel: Bool = true
    @AppStorage("lastActiveView") var lastActiveView: String = ""

    let cacheService = CacheService()
    let annotationStore = AnnotationStoreContainer()
    let projectStore = ProjectStore()
    let dataLabelStore = DataLabelStore()
    let ecoStore = ECOStore()
    let ecoChatStore = ECOChatStore()
    let updater = Updater()
    let assemblyStore = AssemblyStore()
    let felBridge = FELBridge()
    let felService = FELService()
    let voiceService = VoiceService()
    let bleService = BLEService()
    let swdProbe = SWDProbeService()
    let esp32Service = ESP32Service()
    let deviceTracker = DeviceStateTracker()
    let userSession = UserSession()
    let deviceRegistry = DeviceRegistry()
    let consoleServer = FELConsoleServer()
    @AppStorage("userRole") var userRoleRaw: String = "admin" {
        didSet { userSession.role = UserRole(rawValue: userRoleRaw) ?? .admin }
    }
    @Published var showFEL: Bool = false {
        didSet { if showFEL { lastActiveView = "fel" } }
    }
    @Published var selectedAssemblyDoc: AssemblyDocument?

    let iqcService = IQCService()
    @Published var iqcItems: [IQCItem] = IQCService.sampleItems

    private var felServiceCancellable: Any?

    /// The effective list of IQC items: live data when available, sample data as fallback.
    var effectiveIQCItems: [IQCItem] {
        iqcService.items.isEmpty ? iqcItems : iqcService.items
    }

    nonisolated init() {
        // Wire up device registry callback immediately (before FEL connects)
        let registry = deviceRegistry
        let felSvc = felService
        felService.onDeviceIdentified = { sid, socName in
            let reg = registry.register(sid: sid, socName: socName)
            // Log device identity with auto-generated serial
            if !reg.boardSerial.isEmpty {
                felSvc.appendLog("Serial: \(reg.boardSerial)")
            }
            // Warn if hardware changed
            if let warning = registry.lastChangeWarning {
                felSvc.appendLog("WARNING: \(warning)")
            }
            return reg
        }

        // Auto-switch to FEL console tab after boot
        felService.onBootComplete = { [weak felService] in
            felService?.appendLog("Serial console ready — switched to Console tab")
        }

        Task { @MainActor in
            await iqcService.fetchItems()
            // Forward FELService changes to AppState so SwiftUI picks them up
            felServiceCancellable = felService.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            // Wire voice commands — app-wide routing, not just FEL console
            voiceService.onCommand = { [weak self] cmd in
                guard let self = self else { return }
                let lower = cmd.lowercased().trimmingCharacters(in: .whitespaces)

                // App navigation commands
                if lower.contains("show") && lower.contains("fel") || lower == "fel" || lower == "device" {
                    self.showFEL = true
                    return
                }
                if lower == "ble" || lower == "bluetooth" || (lower.contains("show") && lower.contains("ble")) {
                    self.showBLE = true
                    return
                }
                if lower.contains("voice") && lower.contains("stop") {
                    self.voiceService.stopListening()
                    return
                }

                // Route to FEL console if in FEL view or if it's a device command
                self.felService.appendLog("[voice] \(cmd)")
                _ = self.consoleServer.onCommand?(cmd)
            }

            // Start console server on localhost:9801
            consoleServer.getLog = { [weak self] in self?.felService.log ?? [] }
            consoleServer.getDeviceJSON = { [weak self] in
                guard let info = self?.felService.deviceInfo else { return "{\"connected\":false}" }
                let sid = info.sid ?? "unknown"
                let reg = self?.felService.registeredDevice
                return "{\"connected\":true,\"soc\":\"\(info.socInfo.name)\",\"sid\":\"\(sid)\",\"name\":\"\(reg?.name ?? "")\",\"owner\":\"\(reg?.owner ?? "")\"}"
            }
            consoleServer.onCommand = { [weak self] cmd in
                guard let self = self else { return "no app state" }
                self.felService.appendLog("> \(cmd)")
                // Execute command and return last log line as result
                let beforeCount = self.felService.log.count
                // Commands are handled by posting to the service log
                let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
                let command = parts[0].lowercased()
                switch command {
                case "status":
                    let state = self.felService.connectionState.rawValue
                    let soc = self.felService.deviceInfo?.displayName ?? "none"
                    let result = "state: \(state)  soc: \(soc)"
                    self.felService.appendLog(result)
                    return result
                case "info":
                    guard let info = self.felService.deviceInfo else { return "not connected" }
                    let result = "\(info.socInfo.name) (0x\(info.version.socIdHex)) SID: \(info.sid ?? "?")"
                    self.felService.appendLog(result)
                    return result
                case "connect", "reconnect":
                    self.felService.connect()
                    return "connecting..."
                case "disconnect":
                    self.felService.disconnect()
                    return "disconnected"
                case "boot":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
                    let ubootPath = "\(home)/Work/PocketPC-Uboot/u-boot.bin"
                    let bl31Path = "\(home)/Work/PocketPC-Uboot/bl31.bin"
                    guard let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else { return "cannot read SPL" }
                    let ubootData = try? Data(contentsOf: URL(fileURLWithPath: ubootPath))
                    let bl31Data = try? Data(contentsOf: URL(fileURLWithPath: bl31Path))
                    self.felService.bootPocketPC(splData: splData, ubootData: ubootData, bl31Data: bl31Data) { _ in }
                    return "boot sequence started"
                case "spl":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    guard let splData = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin")) else { return "cannot read SPL" }
                    self.felService.writeSPL(data: splData) { _ in }
                    return "SPL loading..."
                case "write-uboot":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    guard let ubootData = try? Data(contentsOf: URL(fileURLWithPath: "\(home)/Work/PocketPC-Uboot/u-boot.bin")) else { return "cannot read U-Boot" }
                    self.felService.appendLog("Writing U-Boot (\(ubootData.count) bytes) to 0x4a000000...")
                    self.felService.writeMemory(address: 0x4a000000, data: ubootData) { result in
                        switch result {
                        case .success: self.felService.appendLog("U-Boot written to 0x4a000000")
                        case .failure(let e): self.felService.appendLog("Write failed: \(e.localizedDescription)")
                        }
                    }
                    return "writing U-Boot..."
                case "exec":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let addr: UInt32 = parts.count >= 2 ? (UInt32(parts[1].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0x4a000000) : 0x4a000000
                    self.felService.executeAt(address: addr) { _ in }
                    return "executing at 0x\(String(format: "%x", addr))"
                case "serial":
                    if self.felService.connectionState == .connected {
                        return "cannot open serial while FEL is active"
                    }
                    self.felService.connectSerial()
                    return "serial connecting..."
                case "read":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let readParts = cmd.split(separator: " ").map(String.init)
                    guard readParts.count >= 2 else { return "usage: read <addr> [len]" }
                    let addrStr = readParts[1].replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "0X", with: "")
                    guard let addr = UInt32(addrStr, radix: 16) else { return "invalid address" }
                    let len: UInt32 = readParts.count >= 3 ? (UInt32(readParts[2]) ?? 256) : 256
                    let sem = DispatchSemaphore(value: 0)
                    var resultHex = ""
                    self.felService.readMemory(address: addr, length: len) { result in
                        switch result {
                        case .success(let data):
                            resultHex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                        case .failure(let err):
                            resultHex = "ERROR: \(err.localizedDescription)"
                        }
                        sem.signal()
                    }
                    sem.wait()
                    return resultHex
                case "dump":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let dumpParts = cmd.split(separator: " ").map(String.init)
                    let dumpAddr: UInt32
                    let dumpLen: UInt32
                    let filename: String
                    if dumpParts.count >= 2 && dumpParts[1].lowercased() == "brom" {
                        dumpAddr = 0x00000000
                        dumpLen = 0x8000
                        filename = "a64-brom.bin"
                    } else if dumpParts.count >= 3,
                              let a = UInt32(dumpParts[1].replacingOccurrences(of: "0x", with: ""), radix: 16),
                              let l = UInt32(dumpParts[2]) {
                        dumpAddr = a
                        dumpLen = l
                        filename = "dump-\(String(format: "%08x", a))-\(l).bin"
                    } else {
                        return "usage: dump brom | dump <addr> <len>"
                    }
                    let sem2 = DispatchSemaphore(value: 0)
                    var dumpResult = ""
                    self.felService.dumpMemory(address: dumpAddr, length: dumpLen, progress: { done, total in
                        self.felService.appendLog("  dump: \(done)/\(total)")
                    }) { result in
                        switch result {
                        case .success(let data):
                            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                            let fileURL = desktop.appendingPathComponent(filename)
                            do {
                                try data.write(to: fileURL)
                                dumpResult = "saved \(data.count) bytes to \(fileURL.path)"
                            } catch {
                                dumpResult = "ERROR: \(error.localizedDescription)"
                            }
                        case .failure(let err):
                            dumpResult = "ERROR: \(err.localizedDescription)"
                        }
                        sem2.signal()
                    }
                    sem2.wait()
                    return dumpResult
                case "sync":
                    guard let sid = self.felService.deviceInfo?.sid else { return "no device SID" }
                    let sem3 = DispatchSemaphore(value: 0)
                    var syncResult = ""
                    self.deviceRegistry.sync(sid: sid) { result in
                        switch result {
                        case .success: syncResult = "synced"
                        case .failure(let err): syncResult = "ERROR: \(err.localizedDescription)"
                        }
                        sem3.signal()
                    }
                    sem3.wait()
                    return syncResult
                case "gps":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    if cmdParts.count >= 2 && cmdParts[1].lowercased() == "stop" {
                        self.felService.stopGPS()
                        return "GPS stopped"
                    }
                    let raw = cmdParts.count >= 2 && cmdParts[1].lowercased() == "raw"
                    self.felService.startGPS(raw: raw)
                    return "GPS polling started\(raw ? " (raw)" : "")"

                case "rak", "lora":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    if cmdParts.count >= 2 && cmdParts[1].lowercased() == "reset" {
                        let sem4 = DispatchSemaphore(value: 0)
                        var resetResult = ""
                        self.felService.rakReset { result in
                            switch result {
                            case .success: resetResult = "RAK4200 reset complete"
                            case .failure(let err): resetResult = "ERROR: \(err.localizedDescription)"
                            }
                            sem4.signal()
                        }
                        sem4.wait()
                        return resetResult
                    }
                    // Default: send AT command (or at+version if no args)
                    let atCmd: String
                    let delay: TimeInterval
                    if cmdParts.count < 2 {
                        atCmd = "at+version"
                        delay = 0.3
                    } else if cmdParts[1].lowercased() == "join" {
                        atCmd = "at+join"
                        delay = 5.0
                    } else if cmdParts[1].lowercased() == "send" && cmdParts.count >= 3 {
                        atCmd = "at+send=lora:2:\(cmdParts[2])"
                        delay = 2.0
                    } else {
                        atCmd = cmdParts[1...].joined(separator: " ")
                        delay = 0.3
                    }
                    let sem5 = DispatchSemaphore(value: 0)
                    var rakResult = ""
                    self.felService.ensureUART3 { result in
                        if case .failure(let err) = result {
                            rakResult = "UART3 init failed: \(err.localizedDescription)"
                            sem5.signal()
                            return
                        }
                        self.felService.rakCommand(atCmd, responseDelay: delay) { result in
                            switch result {
                            case .success(let response): rakResult = response
                            case .failure(let err): rakResult = "ERROR: \(err.localizedDescription)"
                            }
                            sem5.signal()
                        }
                    }
                    sem5.wait()
                    return rakResult

                case "swd":
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    return self.swdProbe.handleCommand(cmdParts)

                case "esp32", "esp":
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    return self.esp32Service.handleCommand(cmdParts)

                case "voice":
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    if cmdParts.count >= 2 {
                        switch cmdParts[1].lowercased() {
                        case "start", "on":
                            self.voiceService.startListening()
                            return "Voice recognition started (\(self.voiceService.mode.rawValue) mode)"
                        case "stop", "off":
                            self.voiceService.stopListening()
                            return "Voice recognition stopped"
                        case "direct":
                            self.voiceService.mode = .direct
                            return "Voice mode: direct commands"
                        case "natural":
                            self.voiceService.mode = .natural
                            return "Voice mode: natural language (say 'hey parts')"
                        default:
                            return "Usage: voice [start|stop|direct|natural]"
                        }
                    }
                    return "Voice: \(self.voiceService.isListening ? "listening" : "off") (\(self.voiceService.mode.rawValue) mode)"

                case "ble":
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    if cmdParts.count >= 2 {
                        switch cmdParts[1].lowercased() {
                        case "scan":
                            self.bleService.startScan()
                            return "BLE scanning..."
                        case "stop":
                            self.bleService.stopScan()
                            return "BLE scan stopped"
                        case "devices":
                            let devs = self.bleService.devices.map { "\($0.name) (\($0.rssi))" }.joined(separator: ", ")
                            return devs.isEmpty ? "no devices found" : devs
                        case "connect":
                            if cmdParts.count >= 3 {
                                let name = cmdParts[2...].joined(separator: " ")
                                if let dev = self.bleService.devices.first(where: { $0.name.lowercased().contains(name.lowercased()) }) {
                                    self.bleService.connect(device: dev)
                                    return "connecting to \(dev.name)..."
                                }
                                return "device not found: \(name)"
                            }
                            return "usage: ble connect <name>"
                        case "disconnect":
                            self.bleService.disconnect()
                            return "BLE disconnected"
                        case "send":
                            if cmdParts.count >= 3 {
                                let msg = cmdParts[2...].joined(separator: " ")
                                self.bleService.send(msg)
                                return "sent: \(msg)"
                            }
                            return "usage: ble send <message>"
                        case "flash", "ota":
                            guard cmdParts.count >= 3 else {
                                return "usage: ble flash <firmware.bin>"
                            }
                            let path = cmdParts[2...].joined(separator: " ")
                            guard let fw = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                                return "cannot read: \(path)"
                            }
                            self.bleService.flashOTA(firmware: fw) { result in
                                switch result {
                                case .success: self.bleService.appendLog("[OTA] Flash complete")
                                case .failure(let err): self.bleService.appendLog("[OTA] Failed: \(err.localizedDescription)")
                                }
                            }
                            return "BLE OTA flashing \(fw.count) bytes..."
                        default:
                            return "usage: ble [scan|stop|devices|connect|disconnect|send|flash]"
                        }
                    }
                    return "BLE: \(self.bleService.state == .connected ? "connected to \(self.bleService.connectedDevice?.name ?? "?")" : "disconnected"). Commands: scan, stop, devices, connect, disconnect, send"

                default:
                    return "unknown command: \(cmd). try: status, info, read, dump, gps, rak, swd, voice, ble"
                }
            }
            consoleServer.start()

            // Listen for component reference clicks from ECN markdown
            NotificationCenter.default.addObserver(
                forName: .navigateToComponent, object: nil, queue: .main
            ) { [weak self] notification in
                if let ref = notification.userInfo?["ref"] as? String {
                    self?.navigateToComponent(ref)
                }
            }

            restoreLastView()
        }
    }

    /// Restore the last active view on launch.
    private func restoreLastView() {
        switch lastActiveView {
        case "fel":
            showFEL = true
        case "usb":
            showUSBMonitor = true
        case "ble":
            showBLE = true
        case "credits":
            showCredits = true
        default:
            break // default: datasheet/home view
        }
    }

    func selectDatasheet(_ datasheet: CachedDatasheet) {
        selectedDatasheet = datasheet
        selectedECO = nil
        selectedIQCItem = nil
        selectedAssemblyDoc = nil
        showCredits = false
        showUSBMonitor = false
        showFEL = false
        showBLE = false
        lastActiveView = "datasheet"
        loadPDF(at: datasheet.path)
    }

    func loadPDF(at path: String) {
        let url = URL(fileURLWithPath: path)
        guard let doc = PDFDocument(url: url) else { return }
        pdfDocument = doc
        pageCount = doc.pageCount
        currentPage = 0

        if let ds = selectedDatasheet {
            annotationStore.annotations.load(for: ds)
            annotationStore.conversations.load(for: ds)
            dataLabelStore.load(for: ds)
            applyAnnotations()
            applyDataLabels()
        }
    }

    func goToPage(_ page: Int) {
        guard let doc = pdfDocument, page >= 0, page < doc.pageCount else { return }
        currentPage = page
    }

    /// Search text to highlight in the PDF after navigation.
    @Published var pdfSearchText: String?

    /// Navigate to a component reference in the project schematic PDF.
    /// Finds the first PDF whose filename contains "schematic" (case-insensitive),
    /// searches for the component designator, and jumps to the matching page.
    func navigateToComponent(_ ref: String) {
        // Find the schematic PDF in cached datasheets
        let schematic = cacheService.datasheets.first { ds in
            let name = ds.filename.lowercased()
            return name.contains("schematic") || name.contains("sch")
        }

        guard let ds = schematic else {
            // No schematic found — try the currently loaded PDF
            if let doc = pdfDocument {
                searchAndHighlight(ref, in: doc)
            }
            return
        }

        // Switch to the schematic PDF
        selectDatasheet(ds)

        // Search after PDF loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let doc = self?.pdfDocument {
                self?.searchAndHighlight(ref, in: doc)
            }
        }
    }

    /// Search for text in a PDF and navigate to the first match.
    private func searchAndHighlight(_ text: String, in doc: PDFDocument) {
        let matches = doc.findString(text, withOptions: .caseInsensitive)
        guard let first = matches.first, let page = first.pages.first else {
            pdfSearchText = nil
            return
        }

        // Jump to the page
        let pageIndex = doc.index(for: page)
        if pageIndex != NSNotFound {
            currentPage = pageIndex
        }

        // Store search text so the PDF viewer can highlight it
        pdfSearchText = text

        // Post notification for the PDF view to scroll to the selection
        NotificationCenter.default.post(
            name: .pdfSearchResult,
            object: nil,
            userInfo: ["selection": first]
        )
    }

    func applyAnnotations() {
        guard let doc = pdfDocument else { return }
        for annotation in annotationStore.annotations.annotations {
            guard annotation.page >= 0, annotation.page < doc.pageCount else { continue }
            guard let pdfPage = doc.page(at: annotation.page) else { continue }
            let pdfAnnotation = annotation.toPDFAnnotation()
            pdfPage.addAnnotation(pdfAnnotation)
        }
    }

    func applyDataLabels() {
        guard let doc = pdfDocument else { return }
        for label in dataLabelStore.labels {
            guard label.page >= 0, label.page < doc.pageCount else { continue }
            guard let pdfPage = doc.page(at: label.page) else { continue }
            let pdfAnnotation = label.toPDFAnnotation()
            pdfPage.addAnnotation(pdfAnnotation)
        }
    }
}
