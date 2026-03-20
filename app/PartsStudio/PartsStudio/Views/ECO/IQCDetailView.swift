import SwiftUI
import WebKit

enum IQCTab: String, CaseIterable {
    case report = "Report"
    case docs = "Documentation"
}

struct IQCDetailView: View {
    let item: IQCItem
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: IQCTab = .report

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(IQCTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .background(.bar)

            Divider()

            switch selectedTab {
            case .report:
                IQCEmailView(item: item)
            case .docs:
                IQCDocumentationView(item: item)
            }
        }
    }
}

// MARK: - Documentation View

struct IQCDocumentationView: View {
    let item: IQCItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Local files (X-ray images, etc.)
                if let localFiles = item.localFiles, !localFiles.isEmpty {
                    sectionCard(title: "Local Files", icon: "doc.on.doc") {
                        let resolvedFiles = localFiles.map { resolvePath($0) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 8) {
                            ForEach(Array(resolvedFiles.enumerated()), id: \.offset) { _, path in
                                LocalImageView(path: path)
                            }
                        }
                    }
                }

                // Detected barcodes
                if let barcodes = item.barcodes, !barcodes.isEmpty {
                    sectionCard(title: "Detected Barcodes", icon: "barcode.viewfinder") {
                        VStack(spacing: 0) {
                            ForEach(barcodes) { barcode in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(barcode.data)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                        Text(barcode.type.uppercased())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let conf = barcode.confidence {
                                        Text("\(Int(conf * 100))%")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(conf > 0.9 ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                            .foregroundStyle(conf > 0.9 ? .green : .orange)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                if barcode.id != barcodes.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    }
                }

                // OCR text
                if let ocrText = item.ocrText, !ocrText.isEmpty {
                    sectionCard(title: "Extracted Text (OCR)", icon: "text.viewfinder") {
                        ScrollView(.vertical) {
                            Text(ocrText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(maxHeight: 200)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    }
                }

                // Discovered URLs
                if let urls = item.discoveredUrls, !urls.isEmpty {
                    sectionCard(title: "Discovered URLs", icon: "link") {
                        VStack(spacing: 0) {
                            ForEach(urls) { discovered in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(discovered.url)
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                            .textSelection(.enabled)
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            if let source = discovered.source {
                                                Text(source)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let domain = discovered.domainType {
                                                Text(domain.uppercased())
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.1))
                                                    .foregroundStyle(.blue)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            }
                                        }
                                    }
                                    Spacer()
                                    if let crawl = discovered.crawlStatus {
                                        Text(crawl)
                                            .font(.caption2)
                                            .foregroundStyle(crawl == "crawled" ? .green : .orange)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                if discovered.id != urls.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    }
                }

                // Metadata
                if let metadata = item.metadata, !metadata.isEmpty {
                    sectionCard(title: "Metadata", icon: "info.circle") {
                        VStack(spacing: 0) {
                            ForEach(Array(metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                                HStack {
                                    Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text(value)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    }
                }

                // Empty state
                let hasContent = (item.localFiles?.isEmpty == false) || (item.barcodes?.isEmpty == false) ||
                    (item.ocrText?.isEmpty == false) || (item.discoveredUrls?.isEmpty == false) || (item.metadata?.isEmpty == false)
                if !hasContent {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No documentation available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Upload images via the API to generate barcodes, OCR, and metadata")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst(1))
        }
        return path
    }
}

// MARK: - Local Image View

struct LocalImageView: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.1), radius: 2)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        }
                        Button("Open in Preview") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    )
            }
        }
        .onAppear {
            image = NSImage(contentsOfFile: path)
        }
        .help(URL(fileURLWithPath: path).lastPathComponent)
    }
}

// MARK: - Email View (unchanged)

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
                <p class="greeting">\(item.partnerName.map { "Dear <strong>\($0)</strong> team," } ?? "Dear valued partner,")</p>
                <p class="greeting">\(statusMessage())</p>
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
                \(item.inspectionNotes.map { "<div class=\"section-title\">Inspection Notes</div><div class=\"notes\">\(escapeHTML($0))</div>" } ?? "")
                \(item.inspectionResult == "pending" ? nextStepsHTML() : completionHTML())
                <div class="signature">Best regards,<br><strong>Source Parts IQC Team</strong><br>iqc@source.parts</div>
            </div>
            <div class="footer"><strong>Source Parts</strong> &mdash; Electronic Component Intelligence<br><a href="https://source.parts">source.parts</a><br><br>This is an automated IQC notification.<br>For questions, contact <a href="mailto:iqc@source.parts">iqc@source.parts</a></div>
        </div>
        </body></html>
        """
    }

    private func statusMessage() -> String {
        switch item.inspectionResult {
        case "pass": return "We have completed the incoming quality inspection for your shipment. <strong>All items have passed inspection</strong> and are cleared for use."
        case "fail": return "We have completed the incoming quality inspection for your shipment. Unfortunately, <strong>the items did not pass inspection</strong>. Please review the details below."
        case "partial": return "We have completed the incoming quality inspection for your shipment. <strong>Some items require further review</strong>. Please see the inspection notes for details."
        default: return "Your package has been received at our facility and is <strong>queued for incoming quality inspection</strong>. We will notify you once the inspection is complete."
        }
    }

    private func resultLabel() -> String {
        switch item.inspectionResult {
        case "pass": return "PASSED"; case "fail": return "FAILED"; case "partial": return "PARTIAL"; default: return "PENDING"
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
        let r = item.conditionRating ?? 0
        return String(repeating: "★", count: r) + String(repeating: "☆", count: max(0, 5 - r))
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
        <div class="highlight">Your complete IQC documentation — including high-resolution photos, inspection report, and condition assessment — is available in the <strong>Documentation</strong> tab above.</div>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
    }
}
