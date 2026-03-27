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

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
    @Published var showExportAnnotations: Bool = false
    @Published var showExportLabels: Bool = false
    @Published var showExportPagePNG: Bool = false
    @Published var sidebarSearchText: String = ""
    @Published var selectedECO: ECODocument?
    @Published var selectedReport: ReportDocument?
    @Published var selectedIQCItem: IQCItem?
    @Published var showCredits: Bool = false
    @Published var showUSBMonitor: Bool = false
    @Published var showBLE: Bool = false
    @Published var showIQCCalendar: Bool = false
    @Published var showBotInbox: Bool = false
    @Published var selectedPartNumber: String?
    @AppStorage("showRightPanel") var showRightPanel: Bool = true
    @AppStorage("lastActiveView") var lastActiveView: String = ""
    @AppStorage("lastSelectedECO") var lastSelectedECOId: String = ""
    @AppStorage("lastSelectedReport") var lastSelectedReportId: String = ""
    @AppStorage("appearanceMode") var appearanceModeRaw: String = "system"

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    let cacheService = CacheService()
    let annotationStore = AnnotationStoreContainer()
    let projectStore = ProjectStore()
    let dataLabelStore = DataLabelStore()
    let ecoStore = ECOStore()
    let reportsStore = ReportsStore()
    let ecoChatStore = ECOChatStore()
    #if os(macOS)
    let updater = Updater()
    let felBridge = FELBridge()
    let felService = FELService()
    let swdProbe = SWDProbeService()
    let esp32Service = ESP32Service()
    let eslrService = ESLRService()
    let deviceTracker = DeviceStateTracker()
    let consoleServer = FELConsoleServer()
    let pcbVersionStore = PCBVersionStore()
    #endif
    let assemblyStore = AssemblyStore()
    let voiceService = VoiceService()
    let bleService = BLEService()
    let userSession = UserSession()
    let deviceRegistry = DeviceRegistry()
    @Published var showDocuments: Bool = false {
        didSet { if showDocuments { lastActiveView = "documents" } }
    }
    @AppStorage("userRole") var userRoleRaw: String = "admin" {
        didSet { userSession.role = UserRole(rawValue: userRoleRaw) ?? .admin }
    }
    #if os(macOS)
    @Published var showFEL: Bool = false {
        didSet { if showFEL { lastActiveView = "fel" } }
    }
    @Published var showESLR: Bool = false {
        didSet { if showESLR { lastActiveView = "eslr" } }
    }
    @Published var showPCBEditor: Bool = false {
        didSet { if showPCBEditor { lastActiveView = "pcb" } }
    }
    @Published var showCAMProcessor: Bool = false {
        didSet { if showCAMProcessor { lastActiveView = "cam" } }
    }
    @Published var showKiCadCtrl: Bool = false {
        didSet { if showKiCadCtrl { lastActiveView = "kicad-ctrl" } }
    }
    #endif
    @Published var selectedAssemblyDoc: AssemblyDocument?

    let iqcService = IQCService()
    @Published var iqcItems: [IQCItem] = IQCService.sampleItems

    #if os(macOS)
    private var felServiceCancellable: Any?
    private var eslrServiceCancellable: Any?
    #endif

    /// The effective list of IQC items: live data when available, sample data as fallback.
    var effectiveIQCItems: [IQCItem] {
        iqcService.items.isEmpty ? iqcItems : iqcService.items
    }

    #if os(iOS)
    nonisolated init() {
        Task { @MainActor in
            await iqcService.fetchItems()
        }
    }
    #else
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

        // Wire ESLR device identification to DeviceRegistry
        let eslrSvc = eslrService
        eslrService.onDeviceIdentified = { mac, name in
            _ = registry.register(sid: mac, socName: name)
            DispatchQueue.main.async { eslrSvc.appendLog("Registered: \(mac)") }
        }

        Task { @MainActor in
            await iqcService.fetchItems()
            // Forward FELService changes to AppState so SwiftUI picks them up
            felServiceCancellable = felService.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            // Forward ESLRService changes to AppState so SwiftUI picks them up
            eslrServiceCancellable = eslrService.objectWillChange.sink { [weak self] _ in
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
            consoleServer.getESLRDeviceJSON = { [weak self] in
                guard let info = self?.eslrService.deviceInfo else {
                    let port = self?.eslrService.serialPort ?? "none"
                    let state = self?.eslrService.connectionState.rawValue ?? "disconnected"
                    return "{\"connected\":false,\"state\":\"\(state)\",\"port\":\"\(port)\"}"
                }
                return "{\"connected\":true,\"variant\":\"\(info.variant.rawValue)\",\"firmware\":\"\(info.firmwareVersion)\",\"mac\":\"\(info.wifiMAC)\",\"heap\":\(info.freeHeap),\"psram\":\(info.psram),\"ble_name\":\"\(info.bleName)\",\"port\":\"\(info.serialPort)\"}"
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
                case "autoboot":
                    self.felService.appendLog("=== AUTOBOOT SEQUENCE ===")
                    self.runAutoboot()
                    return "autoboot started — check console for progress"

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
                case "mmc":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let mmcParts = cmd.split(separator: " ").map(String.init)
                    // mmc read <sector> [count] — read SD card sectors via bare-metal thunk
                    guard mmcParts.count >= 3, mmcParts[1].lowercased() == "read" else {
                        return "usage: mmc read <sector> [count]"
                    }
                    let sector = UInt32(mmcParts[2]) ?? 0
                    let count = mmcParts.count >= 4 ? (UInt32(mmcParts[3]) ?? 1) : 1
                    self.felService.appendLog("MMC: reading \(count) sector(s) from LBA \(sector)...")

                    // Load thunk binary (C-based, full SD init + read)
                    let srcThunkURL = URL(fileURLWithPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Work/SourceParts/parts-cli/app/PartsStudio/thunks/mmc_init_read.bin")
                    guard let thunkData = try? Data(contentsOf: srcThunkURL) else {
                        return "cannot load mmc_init_read.bin thunk"
                    }

                    // Layout: binary loaded at 0x1A200 (SRAM C / thunk area)
                    // _start entry at offset 0x6A4 (execute at 0x1A8A4)
                    // g_params struct at offset 0x16B4 (address 0x1B8B4)
                    // Uses BROM's stack (push/pop callee-saved regs)
                    let thunkAddr: UInt32 = 0x0001A200
                    let entryAddr: UInt32 = 0x0001A8A4
                    let paramsOffset = 0x16B4  // offset in binary to g_params
                    let bufAddr: UInt32 = 0x00012000   // data output in SRAM A
                    let statAddr: UInt32 = 0x00011F00   // status in scratch area

                    // Determine bus: "mmc read emmc <sector> [count]" for eMMC
                    let mmcParts2 = cmd.split(separator: " ").map(String.init)
                    let isEMMC: UInt32 = (mmcParts2.count >= 3 && mmcParts2[2].lowercased() == "emmc") ? 1 : 0
                    let sectorArg = isEMMC == 1 ? (mmcParts2.count >= 4 ? (UInt32(mmcParts2[3]) ?? 0) : 0) : sector
                    let countArg = isEMMC == 1 ? (mmcParts2.count >= 5 ? (UInt32(mmcParts2[4]) ?? 1) : 1) : count
                    let mmcBase: UInt32 = isEMMC == 1 ? 0x01C11000 : 0x01C0F000

                    self.felService.appendLog("MMC: bus=\(isEMMC == 1 ? "eMMC (MMC2)" : "SD (MMC0)") base=0x\(String(format: "%x", mmcBase))")

                    var patched = thunkData
                    // Patch g_params struct at paramsOffset
                    patched.replaceSubrange(paramsOffset..<paramsOffset+4, with: withUnsafeBytes(of: mmcBase.littleEndian) { Data($0) })
                    patched.replaceSubrange(paramsOffset+4..<paramsOffset+8, with: withUnsafeBytes(of: sectorArg.littleEndian) { Data($0) })
                    patched.replaceSubrange(paramsOffset+8..<paramsOffset+12, with: withUnsafeBytes(of: countArg.littleEndian) { Data($0) })
                    patched.replaceSubrange(paramsOffset+12..<paramsOffset+16, with: withUnsafeBytes(of: bufAddr.littleEndian) { Data($0) })
                    patched.replaceSubrange(paramsOffset+16..<paramsOffset+20, with: withUnsafeBytes(of: statAddr.littleEndian) { Data($0) })
                    patched.replaceSubrange(paramsOffset+20..<paramsOffset+24, with: withUnsafeBytes(of: isEMMC.littleEndian) { Data($0) })

                    let sem = DispatchSemaphore(value: 0)
                    var mmcResult = ""

                    // Write thunk to SRAM
                    self.felService.writeMemory(address: thunkAddr, data: patched) { writeResult in
                        switch writeResult {
                        case .failure(let e):
                            mmcResult = "write thunk failed: \(e.localizedDescription)"
                            sem.signal()
                            return
                        case .success:
                            self.felService.appendLog("MMC: thunk loaded at 0x\(String(format: "%x", thunkAddr))")
                        }

                        // Execute thunk at _start entry point
                        self.felService.executeAt(address: entryAddr) { execResult in
                            switch execResult {
                            case .failure(let e):
                                mmcResult = "exec failed: \(e.localizedDescription)"
                                sem.signal()
                                return
                            case .success:
                                self.felService.appendLog("MMC: thunk returned, reading status...")
                            }

                            // Read status (16 bytes: error, sectors_read, rca, debug)
                            self.felService.readMemory(address: statAddr, length: 16) { statusResult in
                                switch statusResult {
                                case .failure(let e):
                                    mmcResult = "read status failed: \(e.localizedDescription)"
                                    sem.signal()
                                    return
                                case .success(let statusData):
                                    let errCode = statusData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
                                    let sectorsRead = statusData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
                                    let rca = statusData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
                                    let debug = statusData.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }
                                    self.felService.appendLog("MMC: err=\(errCode) sectors=\(sectorsRead) rca=0x\(String(format: "%08x", rca)) debug=0x\(String(format: "%08x", debug))")
                                    if errCode != 0 {
                                        mmcResult = "MMC error \(errCode), \(sectorsRead) sectors read (debug=0x\(String(format: "%08x", debug)))"
                                        sem.signal()
                                        return
                                    }
                                    self.felService.appendLog("MMC: \(sectorsRead) sector(s) read OK")

                                    // Read sector data
                                    let dataLen = UInt32(sectorsRead) * 512
                                    self.felService.readMemory(address: bufAddr, length: dataLen) { dataResult in
                                        switch dataResult {
                                        case .failure(let e):
                                            mmcResult = "read data failed: \(e.localizedDescription)"
                                        case .success(let sectorData):
                                            // Save to Desktop
                                            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                                            let filename = "mmc_sector\(sector)_x\(sectorsRead).bin"
                                            let fileURL = desktop.appendingPathComponent(filename)
                                            do {
                                                try sectorData.write(to: fileURL)
                                                mmcResult = "saved \(sectorData.count) bytes to \(fileURL.path)"
                                                self.felService.appendLog("MMC: \(mmcResult)")
                                                // Show first 32 bytes as hex
                                                let preview = sectorData.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
                                                self.felService.appendLog("MMC: \(preview) ...")
                                            } catch {
                                                mmcResult = "save failed: \(error.localizedDescription)"
                                            }
                                        }
                                        sem.signal()
                                    }
                                }
                            }
                        }
                    }
                    sem.wait()
                    return mmcResult
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

                case "eslr", "radio":
                    let cmdParts = cmd.split(separator: " ").map(String.init)
                    return self.eslrService.handleCommand(cmdParts)

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
                    return "unknown command: \(cmd). try: status, info, read, dump, gps, rak, swd, voice, ble, eslr"
                }
            }
            consoleServer.onReload = { [weak self] in
                let config = PartsConfig.reload()
                self?.assemblyStore.loadDocuments()
                return "{\"reloaded\":true,\"revision\":\"\(config.revision)\",\"assembly\":\"\(config.assemblyPath)\",\"fab_release\":\"\(config.fabReleasePath)\"}"
            }
            consoleServer.onSetRevision = { [weak self] newRev in
                let config = PartsConfig.setRevision(newRev)
                self?.assemblyStore.loadDocuments()
                return "{\"revision\":\"\(config.revision)\",\"assembly\":\"\(config.assemblyPath)\",\"fab_release\":\"\(config.fabReleasePath)\"}"
            }
            consoleServer.onNavigate = { [weak self] navKey in
                guard let self = self else { return "{\"error\":\"no app state\"}" }
                DispatchQueue.main.async {
                    // Parse "view:id" format — id is optional
                    let parts = navKey.split(separator: ":", maxSplits: 1)
                    let view = String(parts[0])
                    let itemId: String? = parts.count > 1 ? String(parts[1]) : nil

                    // Clear all view state first
                    self.selectedDatasheet = nil
                    self.selectedECO = nil
                    self.selectedReport = nil
                    self.selectedIQCItem = nil
                    self.selectedAssemblyDoc = nil
                    self.pdfDocument = nil
                    self.showFEL = false
                    self.showESLR = false
                    self.showUSBMonitor = false
                    self.showCredits = false
                    self.showBLE = false
                    self.showDocuments = false

                    switch view.lowercased() {
                    case "fel":
                        self.showFEL = true
                    case "eslr", "radio":
                        self.showESLR = true
                    case "usb":
                        self.showUSBMonitor = true
                    case "credits":
                        self.showCredits = true
                    case "ble":
                        self.showBLE = true
                    case "iqc":
                        if let first = self.effectiveIQCItems.first {
                            self.selectedIQCItem = first
                        }
                    case "eco":
                        // Explicit ID → select that document
                        // No ID → restore last-viewed, or fall back to first
                        if let id = itemId,
                           let doc = self.ecoStore.documents.first(where: { $0.id == id }) {
                            self.selectedECO = doc
                            self.lastSelectedECOId = id
                        } else if !self.lastSelectedECOId.isEmpty,
                           let last = self.ecoStore.documents.first(where: { $0.id == self.lastSelectedECOId }) {
                            self.selectedECO = last
                        } else if let first = self.ecoStore.documents.first {
                            self.selectedECO = first
                        }
                    case "reports":
                        if let id = itemId,
                           let doc = self.reportsStore.documents.first(where: { $0.id == id }) {
                            self.selectedReport = doc
                            self.lastSelectedReportId = id
                        } else if !self.lastSelectedReportId.isEmpty,
                           let last = self.reportsStore.documents.first(where: { $0.id == self.lastSelectedReportId }) {
                            self.selectedReport = last
                        } else if let first = self.reportsStore.documents.first {
                            self.selectedReport = first
                        }
                    case "search", "partsq":
                        break // clearing everything shows PartsQView (default)
                    case "datasheets":
                        // Select first datasheet
                        if let first = self.cacheService.datasheets.first {
                            self.selectDatasheet(first)
                        }
                    default:
                        break
                    }

                    // Bring window to front
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
                }
                return "{\"navigated\":\"\(navKey)\"}"
            }
            consoleServer.getPCBVersionsJSON = { [weak self] in
                guard let versions = self?.pcbVersionStore.versions else { return "[]" }
                let entries = versions.map { v in
                    "{\"id\":\"\(v.id)\",\"name\":\"\(v.name)\",\"layers\":\(v.layerCount),\"path\":\"\(v.basePath)\"}"
                }
                return "[\(entries.joined(separator: ","))]"
            }
            consoleServer.getPCBLayersJSON = { [weak self] versionId in
                guard let version = self?.pcbVersionStore.versions.first(where: { $0.id == versionId }) else {
                    return "[]"
                }
                let entries = version.layers.map { layer in
                    let visible = layer.isVisible ? "true" : "false"
                    let escaped = layer.filePath.replacingOccurrences(of: "\"", with: "\\\"")
                    return "{\"name\":\"\(layer.displayName)\",\"type\":\"\(layer.type.rawValue)\",\"visible\":\(visible),\"file\":\"\(escaped)\"}"
                }
                return "[\(entries.joined(separator: ","))]"
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
    #endif

    #if os(macOS)
    // MARK: - Autoboot Sequence

    /// Automated boot: halt STM32 → SPL → wait for replug → U-Boot → execute.
    /// The STM32 halt keeps the PocketPC powered during USB replug.
    private func runAutoboot() {
        let fel = felService
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
        let ubootPath = "\(home)/Work/PocketPC-Uboot/u-boot.bin"
        let bl31Path = "\(home)/Work/PocketPC-Uboot/bl31.bin"

        // Step 1: Halt STM32 via debug probe (if connected)
        fel.appendLog("[1/5] Halting STM32 via SWD (no-battery fix)...")
        DispatchQueue.global(qos: .userInitiated).async {
            let halt = Process()
            halt.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/openocd")
            halt.arguments = [
                "-f", "interface/cmsis-dap.cfg",
                "-c", "transport select swd; adapter speed 400",
                "-f", "target/stm32f1x.cfg",
                "-c", """
                init; halt;
                mww 0x40010800 0x44444444; mww 0x40010804 0x44444444;
                mww 0x40010C00 0x44444444; mww 0x40010C04 0x44444444;
                mww 0x40011000 0x44444444; mww 0x40011004 0x44444444;
                shutdown
                """
            ]
            let pipe = Pipe()
            halt.standardOutput = pipe
            halt.standardError = pipe

            do {
                try halt.run()
                halt.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let halted = output.contains("halted")

                DispatchQueue.main.async {
                    if halted {
                        fel.appendLog("[1/5] STM32 halted — PocketPC will stay powered")
                    } else if output.contains("Error") || output.contains("error") {
                        fel.appendLog("[1/5] No debug probe — skipping STM32 halt")
                        fel.appendLog("  (If device shuts down during boot, connect debug probe first)")
                    } else {
                        fel.appendLog("[1/5] OpenOCD: \(output.prefix(100))")
                    }

                    // Step 2: Load SPL
                    self.autobootStep2(splPath: splPath, ubootPath: ubootPath, bl31Path: bl31Path)
                }
            } catch {
                DispatchQueue.main.async {
                    fel.appendLog("[1/5] OpenOCD not found — skipping STM32 halt")
                    self.autobootStep2(splPath: splPath, ubootPath: ubootPath, bl31Path: bl31Path)
                }
            }
        }
    }

    private func autobootStep2(splPath: String, ubootPath: String, bl31Path: String) {
        let fel = felService

        guard fel.connectionState == .connected else {
            fel.appendLog("[2/5] ERROR: FEL device not connected. Plug in PocketPC in FEL mode.")
            return
        }

        guard let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else {
            fel.appendLog("[2/5] ERROR: Cannot read SPL at \(splPath)")
            return
        }

        let ubootData = try? Data(contentsOf: URL(fileURLWithPath: ubootPath))
        let bl31Data = try? Data(contentsOf: URL(fileURLWithPath: bl31Path))

        fel.appendLog("[2/5] Loading SPL (\(splData.count) bytes)...")
        fel.bootPocketPC(splData: splData, ubootData: ubootData, bl31Data: bl31Data) { result in
            switch result {
            case .success:
                fel.appendLog("[5/5] Boot complete!")
            case .failure(let err):
                let msg = err.localizedDescription
                if msg.contains("Replug") || msg.contains("USB") {
                    fel.appendLog("[3/5] SPL done — DRAM initialized. USB PHY died.")
                    fel.appendLog("[4/5] >>> REPLUG USB NOW <<<")
                    fel.appendLog("  Then run: write-uboot → exec 0x4a000000")
                    fel.appendLog("  Or run 'boot' again (DRAM is already initialized)")
                } else {
                    fel.appendLog("[2/5] Boot failed: \(msg)")
                }
            }
        }
    }

    /// Restore the last active view on launch.
    private func restoreLastView() {
        switch lastActiveView {
        case "fel":
            showFEL = true
        case "eslr":
            showESLR = true
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
    #endif

    func selectPart(_ partNumber: String) {
        selectedPartNumber = partNumber
        selectedDatasheet = nil
        selectedECO = nil
        selectedIQCItem = nil
        #if os(macOS)
        selectedAssemblyDoc = nil
        showUSBMonitor = false
        showFEL = false
        showESLR = false
        showDocuments = false
        #endif
        pdfDocument = nil
        showCredits = false
        showBLE = false
        lastActiveView = "part"
    }

    // MARK: - File Open (external)

    /// Open a file by path — used by AppDelegate when files are opened externally
    /// (double-click, `open -a PartsStudio`, drag-and-drop, CLI args).
    func openFile(at path: String) {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let filename = URL(fileURLWithPath: path).lastPathComponent

        // Clear all active views
        selectedDatasheet = nil
        selectedECO = nil
        selectedIQCItem = nil
        selectedReport = nil
        pdfDocument = nil
        #if os(macOS)
        showFEL = false
        showESLR = false
        showUSBMonitor = false
        showPCBEditor = false
        showCAMProcessor = false
        #endif
        showCredits = false
        showBLE = false
        showBotInbox = false

        // Gerber extensions
        let gerberExts: Set<String> = ["gbr", "gtl", "gbl", "gts", "gbs", "gto", "gbo", "gtp", "gbp", "gm1", "gko", "drl", "xln"]
        let isGerber = gerberExts.contains(ext) || (ext.hasPrefix("g") && ext.count <= 4 && Int(ext.dropFirst()) != nil)

        if ext == "pdf" {
            loadPDF(at: path)
        } else if isGerber || ext == "gbrjob" || ext == "csv" || ext == "dxf" || ext == "json" || ext == "md" || ext == "step" || ext == "stp" {
            #if os(macOS)
            let category: String
            switch ext {
            case "csv": category = "BOM"
            case "dxf", "step", "stp": category = "3D Model"
            case "md": category = "Assembly"
            default: category = "Fab"
            }

            let doc = AssemblyDocument(
                id: path,
                name: filename,
                category: category,
                path: path,
                size: (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0,
                revision: ""
            )
            selectedAssemblyDoc = doc
            #endif
        }
    }

    func selectDatasheet(_ datasheet: CachedDatasheet) {
        selectedDatasheet = datasheet
        selectedPartNumber = nil
        selectedECO = nil
        selectedIQCItem = nil
        #if os(macOS)
        selectedAssemblyDoc = nil
        showUSBMonitor = false
        showFEL = false
        showESLR = false
        #endif
        showCredits = false
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
        #if os(macOS)
        NotificationCenter.default.post(
            name: .pdfSearchResult,
            object: nil,
            userInfo: ["selection": first]
        )
        #endif
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
