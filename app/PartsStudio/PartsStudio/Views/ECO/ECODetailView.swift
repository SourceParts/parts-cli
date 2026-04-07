import SwiftUI
import WebKit

struct ECODetailView: View {
    let document: ECODocument

    private var typeColor: Color {
        switch document.type {
        case .eco: return .purple
        case .ecr: return .blue
        case .ecn: return .teal
        }
    }

    private var statusColor: Color {
        let s = document.status.uppercased()
        if s == "OPEN" { return .green }
        if s.contains("APPROVED") { return .mint }
        if s.contains("PENDING") || s.contains("BLOCK") || s.contains("AWAIT") { return .purple }
        if s.contains("CLOSED") || s.contains("CLOSE") { return .indigo }
        if s.contains("REVIEW") { return .orange }
        if s == "IMPLEMENTED" { return .blue }
        if s.contains("REJECT") { return .red }
        if s.contains("DEFER") { return .yellow }
        return .secondary
    }

    private var severityColor: Color {
        switch document.severity.uppercased() {
        case "CRITICAL": return .red
        case "HIGH": return .orange
        case "MEDIUM": return .yellow
        case "LOW": return .green
        default: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            MarkdownView(markdown: document.body)

            Divider()

            HStack {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(document.filePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button { NotificationCenter.default.post(name: .markdownZoomOut, object: nil) } label: {
                    Image(systemName: "minus.magnifyingglass").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Zoom Out")

                Button { NotificationCenter.default.post(name: .markdownZoomReset, object: nil) } label: {
                    Image(systemName: "1.magnifyingglass").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Reset Zoom")

                Button { NotificationCenter.default.post(name: .markdownZoomIn, object: nil) } label: {
                    Image(systemName: "plus.magnifyingglass").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Zoom In")

                Divider().frame(height: 12)

                Button(action: {
                    NSWorkspace.shared.selectFile(document.filePath, inFileViewerRootedAtPath: "")
                }) {
                    Image(systemName: "folder")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reveal in Finder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(document.type.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(typeColor.opacity(0.2))
                    .foregroundStyle(typeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(document.id)
                    .font(.title2)
                    .fontWeight(.bold)
                    .textSelection(.enabled)

                Spacer()

                if !document.severity.isEmpty {
                    Text(document.severity)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(severityColor.opacity(0.15))
                        .foregroundStyle(severityColor)
                        .clipShape(Capsule())
                }

                Text(document.status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            Text(document.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Component Reference Navigation

extension Notification.Name {
    /// Posted when a component reference is clicked in an ECN. UserInfo: ["ref": "U5"]
    static let navigateToComponent = Notification.Name("partsStudioNavigateToComponent")
    static let markdownZoomIn = Notification.Name("partsStudioMarkdownZoomIn")
    static let markdownZoomOut = Notification.Name("partsStudioMarkdownZoomOut")
    static let markdownZoomReset = Notification.Name("partsStudioMarkdownZoomReset")
}

#if os(iOS)
/// Simple markdown fallback for iOS — renders as plain text in a ScrollView.
struct MarkdownView: View {
    let markdown: String
    var body: some View {
        ScrollView {
            Text(markdown)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#else
/// Renders markdown as styled HTML using WKWebView.
/// Component references (U5, R12, C3, etc.) are auto-linked and clickable.
/// Supports zoom via .markdownZoomIn / .markdownZoomOut / .markdownZoomReset notifications.
struct MarkdownView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.startListening()
        loadMarkdown(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        loadMarkdown(into: webView)
    }

    private func loadMarkdown(into webView: WKWebView) {
        let html = wrapMarkdownInHTML(markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Coordinator intercepts parts:// links and handles zoom notifications.
    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var zoomLevel: Double = 1.0
        private var observers: [Any] = []

        func startListening() {
            guard observers.isEmpty else { return }
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: .markdownZoomIn, object: nil, queue: .main) { [weak self] _ in
                self?.adjustZoom(by: 0.1)
            })
            observers.append(nc.addObserver(forName: .markdownZoomOut, object: nil, queue: .main) { [weak self] _ in
                self?.adjustZoom(by: -0.1)
            })
            observers.append(nc.addObserver(forName: .markdownZoomReset, object: nil, queue: .main) { [weak self] _ in
                self?.zoomLevel = 1.0
                self?.applyZoom()
            })
        }

        private func adjustZoom(by delta: Double) {
            zoomLevel = max(0.5, min(3.0, zoomLevel + delta))
            applyZoom()
        }

        private func applyZoom() {
            webView?.evaluateJavaScript("document.body.style.zoom = '\(zoomLevel)'", completionHandler: nil)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "parts" {
                if url.host == "ref", let ref = url.pathComponents.last, ref != "/" {
                    NotificationCenter.default.post(
                        name: .navigateToComponent,
                        object: nil,
                        userInfo: ["ref": ref]
                    )
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    /// Convert markdown to HTML with a basic parser, then wrap in a styled page.
    private func wrapMarkdownInHTML(_ md: String) -> String {
        let bodyHTML = markdownToHTML(md)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let bgColor = isDark ? "#1e1e1e" : "#ffffff"
        let textColor = isDark ? "#d4d4d4" : "#1e1e1e"
        let codeBackground = isDark ? "#2d2d2d" : "#f4f4f4"
        let borderColor = isDark ? "#444" : "#ddd"
        let linkColor = isDark ? "#4fc1ff" : "#0366d6"
        let headingColor = isDark ? "#e0e0e0" : "#111111"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                font-size: 13px;
                line-height: 1.6;
                color: \(textColor);
                background: \(bgColor);
                padding: 20px 48px;
                margin: 0;
                -webkit-font-smoothing: antialiased;
            }
            h1, h2, h3, h4 {
                color: \(headingColor);
                margin-top: 1.4em;
                margin-bottom: 0.5em;
                font-weight: 600;
            }
            h1 { font-size: 1.5em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.3em; }
            h2 { font-size: 1.3em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.2em; }
            h3 { font-size: 1.1em; }
            h4 { font-size: 1.0em; }
            p { margin: 0.6em 0; }
            strong { font-weight: 600; }
            em { font-style: italic; }
            a { color: \(linkColor); text-decoration: none; }
            a:hover { text-decoration: underline; }
            a.ref {
                color: \(isDark ? "#c792ea" : "#6f42c1");
                font-family: "SF Mono", Menlo, monospace;
                font-weight: 600;
                font-size: 0.95em;
                background: \(isDark ? "rgba(199,146,234,0.1)" : "rgba(111,66,193,0.08)");
                padding: 1px 4px;
                border-radius: 3px;
                cursor: pointer;
            }
            a.ref:hover {
                background: \(isDark ? "rgba(199,146,234,0.25)" : "rgba(111,66,193,0.18)");
                text-decoration: none;
            }
            code {
                font-family: "SF Mono", Menlo, monospace;
                font-size: 0.9em;
                background: \(codeBackground);
                padding: 2px 5px;
                border-radius: 3px;
            }
            pre {
                background: \(codeBackground);
                padding: 12px 16px;
                border-radius: 6px;
                overflow-x: auto;
                border: 1px solid \(borderColor);
            }
            pre code {
                background: none;
                padding: 0;
                font-size: 12px;
            }
            blockquote {
                border-left: 3px solid \(borderColor);
                margin: 0.6em 0;
                padding: 0.3em 1em;
                color: \(isDark ? "#999" : "#666");
            }
            ul, ol { padding-left: 1.5em; margin: 0.4em 0; }
            li { margin: 0.2em 0; }
            hr { border: none; border-top: 1px solid \(borderColor); margin: 1.2em 0; }
            table {
                border-collapse: collapse;
                width: 100%;
                margin: 0.8em 0;
                font-size: 12px;
            }
            th, td {
                border: 1px solid \(borderColor);
                padding: 6px 10px;
                text-align: left;
            }
            th {
                background: \(codeBackground);
                font-weight: 600;
            }
            img { max-width: 100%; border-radius: 4px; }
        </style>
        </head>
        <body>
        \(bodyHTML)
        </body>
        </html>
        """
    }

    /// Minimal markdown-to-HTML converter. Handles the constructs used in ECN/ECR/ECO files.
    private func markdownToHTML(_ md: String) -> String {
        var lines = md.components(separatedBy: "\n")
        var html: [String] = []
        var inCodeBlock = false
        var inTable = false
        var inList = false
        var listType = ""

        for i in 0..<lines.count {
            var line = lines[i]

            // Code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html.append("</code></pre>")
                    inCodeBlock = false
                } else {
                    html.append("<pre><code>")
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                html.append(escapeHTML(line))
                continue
            }

            // Close list if we're in one and hit a non-list line
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isList = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || (trimmed.first?.isNumber == true && trimmed.contains(". "))
            if inList && !isList && !trimmed.isEmpty {
                html.append("</\(listType)>")
                inList = false
            }

            // Blank lines
            if trimmed.isEmpty {
                if inTable { html.append("</table>"); inTable = false }
                continue
            }

            // Horizontal rules
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if inTable { html.append("</table>"); inTable = false }
                html.append("<hr>")
                continue
            }

            // Tables
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                // Skip separator rows
                if trimmed.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ":", with: "").isEmpty {
                    continue
                }
                if !inTable {
                    html.append("<table>")
                    inTable = true
                    // First row is header
                    let cells = parseTableCells(trimmed)
                    html.append("<tr>" + cells.map { "<th>\(inlineMarkdown($0))</th>" }.joined() + "</tr>")
                    continue
                }
                let cells = parseTableCells(trimmed)
                html.append("<tr>" + cells.map { "<td>\(inlineMarkdown($0))</td>" }.joined() + "</tr>")
                continue
            }
            if inTable { html.append("</table>"); inTable = false }

            // Headings
            if trimmed.hasPrefix("####") {
                html.append("<h4>\(inlineMarkdown(String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)))</h4>")
                continue
            }
            if trimmed.hasPrefix("###") {
                html.append("<h3>\(inlineMarkdown(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)))</h3>")
                continue
            }
            if trimmed.hasPrefix("##") {
                html.append("<h2>\(inlineMarkdown(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))</h2>")
                continue
            }
            if trimmed.hasPrefix("#") {
                html.append("<h1>\(inlineMarkdown(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)))</h1>")
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                html.append("<blockquote>\(inlineMarkdown(String(trimmed.dropFirst(2))))</blockquote>")
                continue
            }

            // Lists
            if isList {
                let content: String
                let type: String
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    content = String(trimmed.dropFirst(2))
                    type = "ul"
                } else {
                    content = String(trimmed.drop(while: { $0.isNumber || $0 == "." || $0 == " " }))
                    type = "ol"
                }
                if !inList {
                    html.append("<\(type)>")
                    inList = true
                    listType = type
                }
                html.append("<li>\(inlineMarkdown(content))</li>")
                continue
            }

            // Paragraph
            html.append("<p>\(inlineMarkdown(trimmed))</p>")
        }

        if inCodeBlock { html.append("</code></pre>") }
        if inTable { html.append("</table>") }
        if inList { html.append("</\(listType)>") }

        return html.joined(separator: "\n")
    }

    /// Process inline markdown: bold, italic, code, links, component references.
    private func inlineMarkdown(_ text: String) -> String {
        var result = escapeHTML(text)

        // Inline code (before bold/italic to avoid conflicts)
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Bold + italic
        result = result.replacingOccurrences(
            of: "\\*\\*\\*(.+?)\\*\\*\\*",
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )

        // Bold
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic
        result = result.replacingOccurrences(
            of: "(?<![\\w*])\\*([^*]+?)\\*(?![\\w*])",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Links [text](url)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // Component references: U5, R12, C3, L1, D2, Q1, J3, SW1, FB2, etc.
        // Match designator letter(s) + number, not already inside an <a> tag or <code> block
        result = result.replacingOccurrences(
            of: "(?<![a-zA-Z/\"])\\b([A-Z]{1,3})(\\d{1,4})\\b(?![\"<])",
            with: "<a href=\"parts://ref/$1$2\" class=\"ref\">$1$2</a>",
            options: .regularExpression
        )

        return result
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func parseTableCells(_ row: String) -> [String] {
        let inner = row.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
#endif
