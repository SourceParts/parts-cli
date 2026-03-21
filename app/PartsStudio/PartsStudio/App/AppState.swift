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
        felService.onDeviceIdentified = { sid, socName in
            registry.register(sid: sid, socName: socName)
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
                case "connect":
                    self.felService.connect()
                    return "connecting..."
                case "boot":
                    guard self.felService.connectionState == .connected else { return "not connected" }
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let splPath = "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
                    let ubootPath = "\(home)/Work/PocketPC-Uboot/u-boot.bin"
                    guard let splData = try? Data(contentsOf: URL(fileURLWithPath: splPath)) else { return "cannot read SPL" }
                    let ubootData = try? Data(contentsOf: URL(fileURLWithPath: ubootPath))
                    self.felService.bootPocketPC(splData: splData, ubootData: ubootData) { _ in }
                    return "boot sequence started"
                case "serial":
                    self.felService.connectSerial()
                    return "serial connecting..."
                default:
                    self.felService.appendLog("Remote: \(cmd)")
                    return "unknown command"
                }
            }
            consoleServer.start()

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
