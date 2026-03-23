import Foundation
import WebKit
import PDFKit

/// Document types available for generation.
enum DocumentType: String, CaseIterable, Identifiable {
    case datasheet = "Product Datasheet"
    case quote = "Quote / Proposal"
    case invoice = "Invoice"
    case agreement = "Agreement / NDA"
    case bom = "BOM Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .datasheet: return "doc.richtext"
        case .quote: return "dollarsign.circle"
        case .invoice: return "doc.text"
        case .agreement: return "signature"
        case .bom: return "tablecells"
        }
    }
}

/// Line item for quotes and invoices.
struct LineItem: Identifiable {
    let id = UUID()
    var partNumber: String = ""
    var description: String = ""
    var quantity: Int = 1
    var unitPrice: Double = 0
    var total: Double { Double(quantity) * unitPrice }
}

/// Data model for document generation.
struct DocumentData {
    // Common
    var title: String = ""
    var reference: String = ""
    var date: Date = Date()
    var notes: String = ""

    // Company
    var companyName: String = "Source Parts"
    var companyAddress: String = ""
    var companyEmail: String = ""
    var companyPhone: String = ""

    // Customer / Client
    var clientName: String = ""
    var clientAddress: String = ""
    var clientEmail: String = ""

    // Line items (quotes, invoices)
    var items: [LineItem] = []
    var taxRate: Double = 0
    var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    var tax: Double { subtotal * taxRate / 100 }
    var grandTotal: Double { subtotal + tax }

    // Agreement-specific
    var parties: [String] = []
    var clauses: [String] = []
    var effectiveDate: String = ""

    // Datasheet-specific
    var partNumber: String = ""
    var specs: [(String, String)] = []  // (key, value)
    var features: [String] = []
    var imageURL: String = ""
}

/// Core document generation service.
/// Uses HTML templates → WKWebView → PDF export.
@MainActor
class DocumentGenerator: ObservableObject {
    @Published var isGenerating = false

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    /// Generate a PDF from a template and data.
    func generatePDF(type: DocumentType, data: DocumentData, completion: @escaping (Result<Data, Error>) -> Void) {
        isGenerating = true

        let html: String
        switch type {
        case .datasheet: html = DocumentTemplates.datasheet(data)
        case .quote:     html = DocumentTemplates.quote(data)
        case .invoice:   html = DocumentTemplates.invoice(data)
        case .agreement: html = DocumentTemplates.agreement(data)
        case .bom:       html = DocumentTemplates.bom(data)
        }

        // Render HTML to PDF via offscreen WKWebView
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123), configuration: config)
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for content to load, then create PDF
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            webView.createPDF { result in
                self?.isGenerating = false
                completion(result)
            }
        }
    }

    /// Generate and save PDF to a file.
    func generateAndSave(type: DocumentType, data: DocumentData, to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        generatePDF(type: type, data: data) { result in
            switch result {
            case .success(let pdfData):
                do {
                    try pdfData.write(to: url)
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    /// Get HTML preview for a template + data.
    static func previewHTML(type: DocumentType, data: DocumentData) -> String {
        switch type {
        case .datasheet: return DocumentTemplates.datasheet(data)
        case .quote:     return DocumentTemplates.quote(data)
        case .invoice:   return DocumentTemplates.invoice(data)
        case .agreement: return DocumentTemplates.agreement(data)
        case .bom:       return DocumentTemplates.bom(data)
        }
    }
}

// MARK: - HTML Templates

enum DocumentTemplates {
    private static let css = """
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            color: #1a1a1a; line-height: 1.5; padding: 48px;
            font-size: 11pt;
        }
        .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 32px; }
        .logo { font-size: 20pt; font-weight: 700; color: #0066cc; }
        .logo small { font-size: 9pt; color: #666; font-weight: 400; display: block; }
        .meta { text-align: right; font-size: 9pt; color: #666; }
        .meta strong { color: #333; font-size: 10pt; }
        h1 { font-size: 18pt; margin-bottom: 4px; }
        h2 { font-size: 13pt; color: #0066cc; margin: 24px 0 8px; border-bottom: 1px solid #e0e0e0; padding-bottom: 4px; }
        h3 { font-size: 11pt; margin: 16px 0 4px; }
        table { width: 100%; border-collapse: collapse; margin: 8px 0; font-size: 10pt; }
        th { background: #f5f5f7; text-align: left; padding: 6px 10px; font-weight: 600; border-bottom: 2px solid #ddd; }
        td { padding: 6px 10px; border-bottom: 1px solid #eee; }
        tr:hover td { background: #fafafa; }
        .total-row td { font-weight: 700; border-top: 2px solid #333; background: #f5f5f7; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 8pt; font-weight: 600; }
        .badge-blue { background: #e3f2fd; color: #1565c0; }
        .parties { display: flex; gap: 32px; margin: 16px 0; }
        .party { flex: 1; padding: 12px; background: #f5f5f7; border-radius: 6px; }
        .party h3 { margin: 0 0 4px; font-size: 10pt; color: #666; }
        .party p { font-size: 10pt; }
        .clause { margin: 8px 0; padding-left: 16px; }
        .clause-num { font-weight: 600; color: #0066cc; }
        .signature { margin-top: 48px; display: flex; gap: 48px; }
        .sig-block { flex: 1; border-top: 1px solid #333; padding-top: 8px; font-size: 9pt; color: #666; }
        .footer { margin-top: 48px; padding-top: 12px; border-top: 1px solid #e0e0e0; font-size: 8pt; color: #999; text-align: center; }
        .specs-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 24px; }
        .spec-row { display: flex; justify-content: space-between; padding: 3px 0; border-bottom: 1px solid #f0f0f0; font-size: 10pt; }
        .spec-key { color: #666; }
        .spec-val { font-weight: 500; }
        .features li { margin: 2px 0; font-size: 10pt; }
        @media print { body { padding: 24px; } }
    </style>
    """

    private static func header(_ data: DocumentData, docType: String) -> String {
        let date = DocumentGenerator.dateFormatter.string(from: data.date)
        return """
        <div class="header">
            <div>
                <div class="logo">\(esc(data.companyName))<small>Electronic Components & Manufacturing</small></div>
            </div>
            <div class="meta">
                <span class="badge badge-blue">\(docType)</span><br>
                <strong>\(esc(data.reference))</strong><br>
                \(date)
            </div>
        </div>
        """
    }

    private static func footer() -> String {
        """
        <div class="footer">
            Generated by Parts Studio &bull; source.parts
        </div>
        """
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Product Datasheet

    static func datasheet(_ data: DocumentData) -> String {
        var specs = ""
        if !data.specs.isEmpty {
            specs = "<div class=\"specs-grid\">" + data.specs.map {
                "<div class=\"spec-row\"><span class=\"spec-key\">\(esc($0.0))</span><span class=\"spec-val\">\(esc($0.1))</span></div>"
            }.joined() + "</div>"
        }

        var features = ""
        if !data.features.isEmpty {
            features = "<h2>Features</h2><ul class=\"features\">" + data.features.map {
                "<li>\(esc($0))</li>"
            }.joined() + "</ul>"
        }

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">\(css)</head><body>
        \(header(data, docType: "DATASHEET"))
        <h1>\(esc(data.title))</h1>
        <p style="color:#666; font-size:10pt;">\(esc(data.partNumber))</p>
        <h2>Specifications</h2>
        \(specs)
        \(features)
        \(data.notes.isEmpty ? "" : "<h2>Notes</h2><p style=\"font-size:10pt;\">\(esc(data.notes))</p>")
        \(footer())
        </body></html>
        """
    }

    // MARK: - Quote / Proposal

    static func quote(_ data: DocumentData) -> String {
        let rows = data.items.map {
            "<tr><td>\(esc($0.partNumber))</td><td>\(esc($0.description))</td><td style=\"text-align:right\">\($0.quantity)</td><td style=\"text-align:right\">$\(String(format: "%.2f", $0.unitPrice))</td><td style=\"text-align:right\">$\(String(format: "%.2f", $0.total))</td></tr>"
        }.joined()

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">\(css)</head><body>
        \(header(data, docType: "QUOTE"))
        <h1>\(esc(data.title))</h1>

        <div class="parties">
            <div class="party"><h3>From</h3><p><strong>\(esc(data.companyName))</strong><br>\(esc(data.companyAddress))<br>\(esc(data.companyEmail))</p></div>
            <div class="party"><h3>To</h3><p><strong>\(esc(data.clientName))</strong><br>\(esc(data.clientAddress))<br>\(esc(data.clientEmail))</p></div>
        </div>

        <h2>Line Items</h2>
        <table>
            <tr><th>Part #</th><th>Description</th><th style="text-align:right">Qty</th><th style="text-align:right">Unit Price</th><th style="text-align:right">Total</th></tr>
            \(rows)
            <tr class="total-row"><td colspan="4" style="text-align:right">Subtotal</td><td style="text-align:right">$\(String(format: "%.2f", data.subtotal))</td></tr>
            \(data.taxRate > 0 ? "<tr><td colspan=\"4\" style=\"text-align:right\">Tax (\(String(format: "%.1f", data.taxRate))%)</td><td style=\"text-align:right\">$\(String(format: "%.2f", data.tax))</td></tr>" : "")
            <tr class="total-row"><td colspan="4" style="text-align:right"><strong>Total</strong></td><td style="text-align:right"><strong>$\(String(format: "%.2f", data.grandTotal))</strong></td></tr>
        </table>

        \(data.notes.isEmpty ? "" : "<h2>Terms & Notes</h2><p style=\"font-size:10pt;\">\(esc(data.notes))</p>")
        \(footer())
        </body></html>
        """
    }

    // MARK: - Invoice

    static func invoice(_ data: DocumentData) -> String {
        let rows = data.items.map {
            "<tr><td>\(esc($0.partNumber))</td><td>\(esc($0.description))</td><td style=\"text-align:right\">\($0.quantity)</td><td style=\"text-align:right\">$\(String(format: "%.2f", $0.unitPrice))</td><td style=\"text-align:right\">$\(String(format: "%.2f", $0.total))</td></tr>"
        }.joined()

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">\(css)</head><body>
        \(header(data, docType: "INVOICE"))
        <h1>Invoice \(esc(data.reference))</h1>

        <div class="parties">
            <div class="party"><h3>From</h3><p><strong>\(esc(data.companyName))</strong><br>\(esc(data.companyAddress))<br>\(esc(data.companyEmail))</p></div>
            <div class="party"><h3>Bill To</h3><p><strong>\(esc(data.clientName))</strong><br>\(esc(data.clientAddress))<br>\(esc(data.clientEmail))</p></div>
        </div>

        <table>
            <tr><th>Item</th><th>Description</th><th style="text-align:right">Qty</th><th style="text-align:right">Rate</th><th style="text-align:right">Amount</th></tr>
            \(rows)
            <tr class="total-row"><td colspan="4" style="text-align:right">Subtotal</td><td style="text-align:right">$\(String(format: "%.2f", data.subtotal))</td></tr>
            \(data.taxRate > 0 ? "<tr><td colspan=\"4\" style=\"text-align:right\">Tax (\(String(format: "%.1f", data.taxRate))%)</td><td style=\"text-align:right\">$\(String(format: "%.2f", data.tax))</td></tr>" : "")
            <tr class="total-row"><td colspan="4" style="text-align:right"><strong>Amount Due</strong></td><td style="text-align:right"><strong>$\(String(format: "%.2f", data.grandTotal))</strong></td></tr>
        </table>

        \(data.notes.isEmpty ? "" : "<h2>Payment Terms</h2><p style=\"font-size:10pt;\">\(esc(data.notes))</p>")
        \(footer())
        </body></html>
        """
    }

    // MARK: - Agreement / NDA

    static func agreement(_ data: DocumentData) -> String {
        let clauseHTML = data.clauses.enumerated().map { i, clause in
            "<p class=\"clause\"><span class=\"clause-num\">\(i + 1).</span> \(esc(clause))</p>"
        }.joined()

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">\(css)</head><body>
        \(header(data, docType: "AGREEMENT"))
        <h1>\(esc(data.title))</h1>
        <p style="font-size:10pt; color:#666;">Effective Date: \(esc(data.effectiveDate.isEmpty ? DocumentGenerator.dateFormatter.string(from: data.date) : data.effectiveDate))</p>

        <div class="parties">
            \(data.parties.enumerated().map { i, party in
                "<div class=\"party\"><h3>Party \(String(UnicodeScalar(65 + i)!))</h3><p>\(esc(party))</p></div>"
            }.joined())
        </div>

        <h2>Terms and Conditions</h2>
        \(clauseHTML)

        \(data.notes.isEmpty ? "" : "<h2>Additional Terms</h2><p style=\"font-size:10pt;\">\(esc(data.notes))</p>")

        <div class="signature">
            \(data.parties.enumerated().map { i, party in
                "<div class=\"sig-block\"><p>Signature — Party \(String(UnicodeScalar(65 + i)!))</p><p>\(esc(party))</p><p>Date: _______________</p></div>"
            }.joined())
        </div>

        \(footer())
        </body></html>
        """
    }

    // MARK: - BOM Export

    static func bom(_ data: DocumentData) -> String {
        let rows = data.items.enumerated().map { i, item in
            "<tr><td>\(i + 1)</td><td>\(esc(item.partNumber))</td><td>\(esc(item.description))</td><td style=\"text-align:right\">\(item.quantity)</td><td style=\"text-align:right\">\(item.unitPrice > 0 ? "$\(String(format: "%.4f", item.unitPrice))" : "—")</td><td style=\"text-align:right\">\(item.total > 0 ? "$\(String(format: "%.2f", item.total))" : "—")</td></tr>"
        }.joined()

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">\(css)</head><body>
        \(header(data, docType: "BOM"))
        <h1>\(esc(data.title))</h1>
        <p style="font-size:10pt; color:#666;">\(data.items.count) components</p>

        <table>
            <tr><th>#</th><th>Part Number / MPN</th><th>Description</th><th style="text-align:right">Qty</th><th style="text-align:right">Unit Cost</th><th style="text-align:right">Ext Cost</th></tr>
            \(rows)
            \(data.subtotal > 0 ? "<tr class=\"total-row\"><td colspan=\"5\" style=\"text-align:right\"><strong>Total BOM Cost</strong></td><td style=\"text-align:right\"><strong>$\(String(format: "%.2f", data.subtotal))</strong></td></tr>" : "")
        </table>

        \(data.notes.isEmpty ? "" : "<h2>Notes</h2><p style=\"font-size:10pt;\">\(esc(data.notes))</p>")
        \(footer())
        </body></html>
        """
    }
}
