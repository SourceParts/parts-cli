import SwiftUI
import PDFKit

enum ToolMode: String, CaseIterable, Identifiable {
    case view
    case redact
    case text
    case highlight
    case comment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .view: return "View"
        case .redact: return "Redact"
        case .text: return "Text"
        case .highlight: return "Highlight"
        case .comment: return "Comment"
        }
    }

    var icon: String {
        switch self {
        case .view: return "hand.point.up"
        case .redact: return "rectangle.fill"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .comment: return "bubble.left"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .view: return "1"
        case .redact: return "2"
        case .text: return "3"
        case .highlight: return "4"
        case .comment: return "5"
        }
    }

    var tooltip: String {
        switch self {
        case .view: return "View mode (Cmd+1) — scroll and navigate the PDF"
        case .redact: return "Redact (Cmd+2) — draw black rectangles to permanently hide content"
        case .text: return "Text (Cmd+3) — click to place editable text on the page"
        case .highlight: return "Highlight (Cmd+4) — drag to highlight areas of interest"
        case .comment: return "Comment (Cmd+5) — click to pin a conversation thread to a location"
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

    let cacheService = CacheService()
    let annotationStore = AnnotationStoreContainer()
    let projectStore = ProjectStore()
    let dataLabelStore = DataLabelStore()
    let ecoStore = ECOStore()
    let ecoChatStore = ECOChatStore()

    @Published var iqcItems: [IQCItem] = [
        IQCItem(code: "SP-100234", status: "accepted", createdAt: "2026-03-18",
                inspectionNotes: "All parameters within spec. Reel packaging intact, MSL-3 indicators show no moisture exposure.",
                trackingNumber: "SF1234567890", carrier: "SF Express", receivedDate: "2026-03-18 09:42 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Jixing Electronics",
                photoCount: 8, conditionRating: 5, hasDamage: false, inspectionResult: "pass",
                barcodes: [
                    IQCBarcode(data: "8901234567890", type: "ean13", confidence: 0.98),
                    IQCBarcode(data: "https://www.lcsc.com/product-detail/C404280.html", type: "qr_code", confidence: 0.95),
                ],
                ocrText: "JIXING ELECTRONICS\nP/N: USB-C-16P-WP\nLOT: 2026-03-12\nQTY: 200 PCS\nRoHS COMPLIANT\nMSL-3\nMADE IN CHINA",
                discoveredUrls: [
                    IQCDiscoveredURL(url: "https://www.lcsc.com/product-detail/C404280.html", source: "qr_code", domainType: "lcsc", crawlStatus: "crawled"),
                ],
                metadata: ["camera_make": "Sony", "camera_model": "Alpha A7III", "dimensions": "4000x3000", "date_taken": "2026-03-18 09:40:12", "file_size": "4.2 MB", "format": "JPEG"]),
        IQCItem(code: "SP-100235", status: "pending_inspection", createdAt: "2026-03-19",
                trackingNumber: "YT9876543210", carrier: "YTO Express", receivedDate: "2026-03-19 14:15 PM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "LCSC Electronics",
                photoCount: 0, inspectionResult: "pending"),
        IQCItem(code: "SP-100236", status: "rejected", createdAt: "2026-03-17",
                inspectionNotes: "Moisture sensitivity level exceeded. MSL-3 indicator triggered. Vacuum seal was compromised during shipping. Recommend return to supplier.",
                trackingNumber: "ZTO2024031700", carrier: "ZTO Express", receivedDate: "2026-03-17 11:30 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Shenzhen Huaqiang",
                photoCount: 12, conditionRating: 2, hasDamage: true, inspectionResult: "fail"),
        IQCItem(code: "SP-100237", status: "inspected", createdAt: "2026-03-18",
                inspectionNotes: "Visual inspection passed, awaiting electrical test. Component markings match datasheet. Pin count and pitch verified.",
                trackingNumber: "JD0088776655", carrier: "JD Logistics", receivedDate: "2026-03-18 16:20 PM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "DigiKey Asia",
                photoCount: 6, conditionRating: 4, hasDamage: false, inspectionResult: "partial"),
        IQCItem(code: "SP-100238", status: "accepted", createdAt: "2026-03-16",
                inspectionNotes: "Batch accepted. X-ray inspection confirms BGA ball alignment within spec.",
                trackingNumber: "EMS1122334455", carrier: "EMS", receivedDate: "2026-03-16 08:55 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Mouser Electronics",
                photoCount: 4, conditionRating: 5, hasDamage: false, inspectionResult: "pass",
                localFiles: [
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/1-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/1-2.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/2.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/2-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/3.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/3-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/4.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/4-1.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/5.bmp",
                    "~/Work/Consulting/nRF54H20-Main-Board/IQC/X-Ray/3.10/5-1.bmp",
                ],
                metadata: ["inspection_type": "X-Ray", "equipment": "Dage XD7600NT", "magnification": "10x-100x"]),
        IQCItem(code: "SP-100239", status: "pending_inspection", createdAt: "2026-03-19",
                inspectionNotes: "Batch of 500 units received. Awaiting allocation to inspection queue.",
                trackingNumber: "DHL8899001122", carrier: "DHL Express", receivedDate: "2026-03-19 10:05 AM",
                receivedLocation: "Shenzhen Laboratory", partnerName: "Arrow Electronics",
                photoCount: 2, inspectionResult: "pending"),
    ]

    func selectDatasheet(_ datasheet: CachedDatasheet) {
        selectedDatasheet = datasheet
        selectedECO = nil
        selectedIQCItem = nil
        showCredits = false
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
}
