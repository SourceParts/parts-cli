import SwiftUI
import WebKit

struct IQCDetailView: View {
    let item: IQCItem
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            IQCEmailView(item: item)
        }
    }
}

/// Renders the IQC report as a signed email using WKWebView,
/// matching the Source Parts IQC email template design.
struct IQCEmailView: NSViewRepresentable {
    let item: IQCItem

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(renderEmail(), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(renderEmail(), baseURL: nil)
    }

    private func renderEmail() -> String {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bg = isDark ? "#1a1a1a" : "#f3f4f6"
        let cardBg = isDark ? "#262626" : "#ffffff"
        let textPrimary = isDark ? "#e5e5e5" : "#1f2937"
        let textSecondary = isDark ? "#a3a3a3" : "#6b7280"
        let textTertiary = isDark ? "#737373" : "#9ca3af"
        let border = isDark ? "#404040" : "#e5e7eb"
        let infoBg = isDark ? "#1e293b" : "#f9fafb"
        let highlightBg = isDark ? "#1e3a5f" : "#eff6ff"
        let highlightBorder = isDark ? "#3b82f6" : "#2563eb"

        let (resultEmoji, resultColor, resultBg) = inspectionBadge()
        let stars = starRating()

        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: \(bg); color: \(textPrimary); -webkit-font-smoothing: antialiased; }
        .container { max-width: 600px; margin: 24px auto; background: \(cardBg); border-radius: 8px; border: 1px solid \(border); overflow: hidden; }
        .header { background: linear-gradient(135deg, #2563eb, #1d4ed8); color: white; padding: 28px 32px; }
        .header h1 { font-size: 20px; font-weight: 700; margin-bottom: 4px; }
        .header .subtitle { font-size: 13px; opacity: 0.85; }
        .body-content { padding: 28px 32px; }
        .greeting { font-size: 15px; margin-bottom: 16px; line-height: 1.5; }
        .info-box { background: \(infoBg); border: 1px solid \(border); border-radius: 8px; padding: 16px 20px; margin: 16px 0; }
        .info-row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 13px; border-bottom: 1px solid \(border); }
        .info-row:last-child { border-bottom: none; }
        .info-label { color: \(textSecondary); font-weight: 500; }
        .info-value { font-weight: 600; text-align: right; }
        .highlight { background: \(highlightBg); border-left: 4px solid \(highlightBorder); border-radius: 0 8px 8px 0; padding: 14px 18px; margin: 16px 0; font-size: 13px; line-height: 1.5; }
        .result-badge { display: inline-block; padding: 4px 14px; border-radius: 12px; font-size: 12px; font-weight: 700; background: \(resultBg); color: \(resultColor); }
        .damage-alert { background: \(isDark ? "#4c1d1d" : "#fee2e2"); border: 1px solid \(isDark ? "#991b1b" : "#fca5a5"); border-radius: 8px; padding: 12px 16px; margin: 12px 0; font-size: 13px; color: \(isDark ? "#fca5a5" : "#991b1b"); }
        .section-title { font-size: 14px; font-weight: 600; color: \(textPrimary); margin: 20px 0 8px 0; }
        .notes { background: \(infoBg); border-radius: 8px; padding: 14px 18px; font-size: 13px; line-height: 1.6; color: \(textPrimary); border: 1px solid \(border); }
        .stars { color: #f59e0b; font-size: 16px; letter-spacing: 2px; }
        .cta { display: block; width: 260px; margin: 20px auto; text-align: center; background: #2563eb; color: white !important; text-decoration: none; padding: 12px 24px; border-radius: 6px; font-size: 14px; font-weight: 700; }
        hr { border: none; border-top: 1px solid \(border); margin: 20px 0; }
        .steps { margin: 16px 0; }
        .step { display: flex; align-items: flex-start; gap: 12px; margin: 10px 0; font-size: 13px; line-height: 1.5; }
        .step-num { background: #2563eb; color: white; width: 24px; height: 24px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; flex-shrink: 0; }
        .signature { margin-top: 24px; font-size: 13px; color: \(textSecondary); line-height: 1.6; }
        .footer { background: \(infoBg); border-top: 1px solid \(border); padding: 20px 32px; text-align: center; font-size: 11px; color: \(textTertiary); line-height: 1.6; }
        .footer a { color: #2563eb; text-decoration: none; }
        .photos-badge { display: inline-block; background: #dbeafe; color: #1d4ed8; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }
        </style></head>
        <body>
        <div class="container">

            <div class="header">
                <h1>\(item.inspectionResult == "pending" ? "📦 Package Received" : "✅ IQC Inspection Report")</h1>
                <div class="subtitle">Source Parts Incoming Quality Control &mdash; \(item.code)</div>
            </div>

            <div class="body-content">
                <p class="greeting">
                    \(item.partnerName.map { "Dear <strong>\($0)</strong> team," } ?? "Dear valued partner,")
                </p>

                <p class="greeting">
                    \(statusMessage())
                </p>

                <div class="info-box">
                    <div class="info-row"><span class="info-label">Receipt ID</span><span class="info-value">\(item.code)</span></div>
                    \(item.trackingNumber.map { "<div class=\"info-row\"><span class=\"info-label\">Tracking Number</span><span class=\"info-value\">\($0)</span></div>" } ?? "")
                    \(item.carrier.map { "<div class=\"info-row\"><span class=\"info-label\">Carrier</span><span class=\"info-value\">\($0)</span></div>" } ?? "")
                    \(item.receivedDate.map { "<div class=\"info-row\"><span class=\"info-label\">Received</span><span class=\"info-value\">\($0)</span></div>" } ?? "")
                    <div class="info-row"><span class="info-label">Location</span><span class="info-value">\(item.receivedLocation ?? "Shenzhen Laboratory")</span></div>
                    <div class="info-row"><span class="info-label">Status</span><span class="info-value"><span class="result-badge">\(resultEmoji) \(resultLabel())</span></span></div>
                    \(item.conditionRating.map { _ in "<div class=\"info-row\"><span class=\"info-label\">Condition</span><span class=\"info-value\"><span class=\"stars\">\(stars)</span></span></div>" } ?? "")
                    \(item.photoCount.map { "<div class=\"info-row\"><span class=\"info-label\">Documentation</span><span class=\"info-value\"><span class=\"photos-badge\">📸 \($0) photos</span></span></div>" } ?? "")
                </div>

                \(item.hasDamage == true ? "<div class=\"damage-alert\">⚠️ <strong>Damage Detected</strong> — Physical damage was observed during inspection. See notes below for details.</div>" : "")

                \(item.inspectionNotes.map { notes in
                    "<div class=\"section-title\">Inspection Notes</div><div class=\"notes\">\(escapeHTML(notes))</div>"
                } ?? "")

                \(item.inspectionResult == "pending" ? nextStepsHTML() : completionHTML())

                <div class="signature">
                    Best regards,<br>
                    <strong>Source Parts IQC Team</strong><br>
                    iqc@source.parts
                </div>
            </div>

            <div class="footer">
                <strong>Source Parts</strong> &mdash; Electronic Component Intelligence<br>
                <a href="https://source.parts">source.parts</a><br><br>
                This is an automated IQC notification. Please do not reply directly to this email.<br>
                For questions, contact <a href="mailto:iqc@source.parts">iqc@source.parts</a>
            </div>

        </div>
        </body>
        </html>
        """
    }

    private func statusMessage() -> String {
        switch item.inspectionResult {
        case "pass":
            return "We have completed the incoming quality inspection for your shipment. <strong>All items have passed inspection</strong> and are cleared for use."
        case "fail":
            return "We have completed the incoming quality inspection for your shipment. Unfortunately, <strong>the items did not pass inspection</strong>. Please review the details below."
        case "partial":
            return "We have completed the incoming quality inspection for your shipment. <strong>Some items require further review</strong>. Please see the inspection notes for details."
        default:
            return "Your package has been received at our facility and is <strong>queued for incoming quality inspection</strong>. We will notify you once the inspection is complete."
        }
    }

    private func resultLabel() -> String {
        switch item.inspectionResult {
        case "pass": return "PASSED"
        case "fail": return "FAILED"
        case "partial": return "PARTIAL"
        default: return "PENDING"
        }
    }

    private func inspectionBadge() -> (String, String, String) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch item.inspectionResult {
        case "pass": return ("✅", isDark ? "#22c55e" : "#166534", isDark ? "#14532d" : "#dcfce7")
        case "fail": return ("❌", isDark ? "#ef4444" : "#991b1b", isDark ? "#450a0a" : "#fee2e2")
        case "partial": return ("⚠️", isDark ? "#f59e0b" : "#92400e", isDark ? "#451a03" : "#fef3c7")
        default: return ("🔍", isDark ? "#60a5fa" : "#1e40af", isDark ? "#1e3a5f" : "#dbeafe")
        }
    }

    private func starRating() -> String {
        let rating = item.conditionRating ?? 0
        return String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
    }

    private func nextStepsHTML() -> String {
        """
        <div class="section-title">What Happens Next</div>
        <div class="steps">
            <div class="step"><div class="step-num">1</div><div>📸 High-resolution photography of all components and packaging</div></div>
            <div class="step"><div class="step-num">2</div><div>🔍 Visual inspection for physical damage, correct markings, and counterfeit indicators</div></div>
            <div class="step"><div class="step-num">3</div><div>📋 Documentation of lot codes, date codes, and moisture sensitivity levels</div></div>
            <div class="step"><div class="step-num">4</div><div>✅ Final report with pass/fail determination emailed to you</div></div>
        </div>
        """
    }

    private func completionHTML() -> String {
        """
        <hr>
        <div class="highlight">
            Your complete IQC documentation — including high-resolution photos, inspection report, and condition assessment — is available in your Source Parts dashboard.
        </div>
        <a class="cta" href="#">View IQC Documentation</a>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
