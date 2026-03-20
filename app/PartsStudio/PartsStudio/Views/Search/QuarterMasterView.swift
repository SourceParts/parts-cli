import SwiftUI

struct PartsQView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var result: String = ""
    @State private var isLoading: Bool = false
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("Search parts, paste URLs, decode SMD codes...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { runQuery() }

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
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if result.isEmpty && history.isEmpty {
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

        // Add to history
        history.removeAll { $0 == q }
        history.insert(q, at: 0)
        if history.count > 10 { history = Array(history.prefix(10)) }

        isLoading = true
        result = ""

        Task {
            do {
                let output = try await CLIBridge.shared.run(["q", q])
                await MainActor.run {
                    result = output
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    result = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
