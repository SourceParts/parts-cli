import SwiftUI

struct PartsQView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var result: String = ""
    @State private var errorInfo: QueryError? = nil
    @State private var isLoading: Bool = false
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                SearchField(text: $query, placeholder: "Search parts, paste URLs, decode SMD codes...", onSubmit: runQuery)
                    .frame(height: 28)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !query.isEmpty {
                    Button(action: runQuery) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let err = errorInfo {
                // Friendly error view
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: err.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(err.color)
                    Text(err.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(err.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    if let hint = err.hint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    HStack(spacing: 12) {
                        Button("Try Again") { runQuery() }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        Button("Clear") { errorInfo = nil; query = "" }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if result.isEmpty && history.isEmpty {
                // Empty state with examples
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 40)

                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)

                        Text("Parts Q")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Smart query — auto-detects what you need")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 12) {
                            queryExample("STM32F407", "Part search", "magnifyingglass")
                            queryExample("https://lcsc.com/product/C12345.html", "URL ingest", "link")
                            queryExample("103", "SMD code decode", "number")
                            queryExample("brown black red gold", "Resistor color bands", "paintpalette")
                            queryExample("nRF54H20", "Component lookup", "cpu")
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .frame(maxWidth: 500)

                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else if !result.isEmpty {
                // Results
                VStack(spacing: 0) {
                    // Result header
                    HStack {
                        Text("Results")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result, forType: .string)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                        Button(action: { result = ""; query = "" }) {
                            Label("Clear", systemImage: "xmark.circle")
                                .font(.caption2)
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)

                    Divider()

                    ScrollView {
                        PartsQResultView(raw: result)
                            .padding(16)
                    }
                }
            }

            // Recent searches
            if !history.isEmpty && result.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recent")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            history = []
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider()

                    ForEach(history, id: \.self) { item in
                        Button(action: {
                            query = item
                            runQuery()
                        }) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
    }

    @ViewBuilder
    private func queryExample(_ example: String, _ description: String, _ icon: String) -> some View {
        Button(action: {
            query = example
            runQuery()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(example)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runQuery() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        history.removeAll { $0 == q }
        history.insert(q, at: 0)
        if history.count > 10 { history = Array(history.prefix(10)) }

        isLoading = true
        result = ""
        errorInfo = nil

        Task {
            do {
                let output = try await CLIBridge.shared.run(["q", q])
                await MainActor.run {
                    if let err = QueryError.parse(output) {
                        errorInfo = err
                    } else {
                        result = output
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorInfo = QueryError.parse(error.localizedDescription)
                        ?? QueryError(icon: "exclamationmark.triangle", color: .orange,
                                      title: "Something went wrong",
                                      message: error.localizedDescription, hint: nil)
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Error Handling

struct QueryError {
    let icon: String
    let color: Color
    let title: String
    let message: String
    let hint: String?

    static func parse(_ output: String) -> QueryError? {
        let lower = output.lowercased()

        if lower.contains("502") || lower.contains("bad gateway") {
            return QueryError(
                icon: "icloud.slash",
                color: .red,
                title: "API Server Unreachable",
                message: "The Source Parts API is currently down or unreachable. This is usually temporary.",
                hint: "Check api.source.parts status or try again in a few minutes"
            )
        }
        if lower.contains("503") || lower.contains("service unavailable") {
            return QueryError(
                icon: "wrench.and.screwdriver",
                color: .orange,
                title: "Service Maintenance",
                message: "The API is temporarily unavailable, likely for maintenance or updates.",
                hint: "This usually resolves within a few minutes"
            )
        }
        if lower.contains("401") || lower.contains("unauthorized") || lower.contains("api key") {
            return QueryError(
                icon: "key.slash",
                color: .orange,
                title: "Authentication Required",
                message: "Your API key is missing or invalid. Run `parts auth login` to authenticate.",
                hint: "parts auth login"
            )
        }
        if lower.contains("429") || lower.contains("rate limit") {
            return QueryError(
                icon: "gauge.with.dots.needle.67percent",
                color: .yellow,
                title: "Rate Limited",
                message: "Too many requests. Wait a moment before trying again.",
                hint: "Upgrade your plan for higher rate limits"
            )
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return QueryError(
                icon: "clock.badge.exclamationmark",
                color: .orange,
                title: "Request Timed Out",
                message: "The server took too long to respond. Try a simpler query or try again.",
                hint: nil
            )
        }
        if lower.contains("no such host") || lower.contains("could not resolve") || lower.contains("network") {
            return QueryError(
                icon: "wifi.slash",
                color: .red,
                title: "No Internet Connection",
                message: "Cannot reach the Source Parts API. Check your network connection.",
                hint: nil
            )
        }
        if lower.contains("not found") || lower.contains("command not found") || lower.contains("no such file") {
            return QueryError(
                icon: "questionmark.app",
                color: .orange,
                title: "Parts CLI Not Found",
                message: "The `parts` command is not installed or not in your PATH.",
                hint: "Install with: go install github.com/SourceParts/parts-cli/cmd/parts@latest"
            )
        }
        if lower.contains("500") || lower.contains("internal server error") {
            return QueryError(
                icon: "exclamationmark.octagon",
                color: .red,
                title: "Server Error",
                message: "The API encountered an internal error. This has been logged for investigation.",
                hint: "Try again or contact support@source.parts"
            )
        }

        // Check if entire output looks like an error (contains "Error:" and no JSON)
        if (lower.contains("error:") || lower.contains("http ")) && !output.contains("{") {
            return QueryError(
                icon: "exclamationmark.triangle",
                color: .orange,
                title: "Request Failed",
                message: output.components(separatedBy: "\n").first(where: { $0.lowercased().contains("error") || $0.lowercased().contains("http") })?.trimmingCharacters(in: .whitespaces) ?? output,
                hint: nil
            )
        }

        return nil
    }
}

// MARK: - Native Search Field

/// NSTextField wrapper that reliably accepts keyboard input in the main content area.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.font = NSFont.systemFont(ofSize: 16)
        field.placeholderString = placeholder
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true

        // Claim focus on appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
