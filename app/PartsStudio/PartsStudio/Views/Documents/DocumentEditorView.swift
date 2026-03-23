import SwiftUI
import WebKit

struct DocumentEditorView: View {
    @StateObject private var generator = DocumentGenerator()
    @State private var selectedType: DocumentType = .quote
    @State private var data = DocumentData()
    @State private var previewHTML = ""
    @State private var apiStatus = ""
    private let api = PartsAPIClient.shared

    var body: some View {
        HSplitView {
            // Left: Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Document type picker
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(.blue)
                        Text("Document Generator")
                            .font(.headline)
                    }

                    Picker("Type", selection: $selectedType) {
                        ForEach(DocumentType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, _ in updatePreview() }

                    Divider()

                    // Common fields
                    Group {
                        field("Title", text: $data.title)
                        field("Reference #", text: $data.reference)
                        field("Company", text: $data.companyName)
                        field("Company Email", text: $data.companyEmail)
                    }

                    // Client fields (quotes, invoices, agreements)
                    if [.quote, .invoice, .agreement].contains(selectedType) {
                        Divider()
                        Text("Client").font(.caption).foregroundStyle(.secondary)
                        field("Client Name", text: $data.clientName)
                        field("Client Address", text: $data.clientAddress)
                        field("Client Email", text: $data.clientEmail)
                    }

                    // Datasheet fields
                    if selectedType == .datasheet {
                        Divider()
                        Text("Product").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            field("Part Number", text: $data.partNumber)
                            Button("Lookup") { lookupPart() }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .disabled(data.partNumber.isEmpty)
                        }
                    }

                    // DFM fields
                    if selectedType == .dfm {
                        Divider()
                        Text("DFM Analysis").font(.caption).foregroundStyle(.secondary)
                        field("Project ID", text: $data.projectId)
                        HStack {
                            Button("Submit DFM") { submitDFM() }
                                .buttonStyle(.borderedProminent)
                                .font(.caption)
                                .disabled(data.projectId.isEmpty)
                            if !apiStatus.isEmpty {
                                Text(apiStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Line items (quotes, invoices, BOM)
                    if [.quote, .invoice, .bom].contains(selectedType) {
                        Divider()
                        HStack {
                            Text("Line Items").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Price All") { priceAllItems() }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                                .disabled(data.items.isEmpty)
                            Button(action: {
                                data.items.append(LineItem())
                                updatePreview()
                            }) {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(data.items.indices, id: \.self) { i in
                            HStack(spacing: 4) {
                                TextField("Part #", text: $data.items[i].partNumber)
                                    .frame(width: 80)
                                TextField("Description", text: $data.items[i].description)
                                TextField("Qty", value: $data.items[i].quantity, format: .number)
                                    .frame(width: 40)
                                TextField("Price", value: $data.items[i].unitPrice, format: .currency(code: "USD"))
                                    .frame(width: 70)
                                Button(action: {
                                    data.items.remove(at: i)
                                    updatePreview()
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 11))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Agreement clauses
                    if selectedType == .agreement {
                        Divider()
                        HStack {
                            Text("Clauses").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(action: {
                                data.clauses.append("")
                                updatePreview()
                            }) {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(data.clauses.indices, id: \.self) { i in
                            HStack {
                                Text("\(i + 1).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("Clause text", text: $data.clauses[i])
                                    .font(.system(size: 11))
                                    .textFieldStyle(.roundedBorder)
                                Button(action: {
                                    data.clauses.remove(at: i)
                                    updatePreview()
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button("Set Parties from Company/Client") {
                            data.parties = [data.companyName, data.clientName]
                            updatePreview()
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                    }

                    // Notes
                    Divider()
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $data.notes)
                        .font(.system(size: 11))
                        .frame(height: 60)
                        .border(Color.secondary.opacity(0.3))

                    // Actions
                    Divider()
                    HStack {
                        Button("Update Preview") { updatePreview() }
                            .buttonStyle(.bordered)

                        Button("Export PDF...") { exportPDF() }
                            .buttonStyle(.borderedProminent)
                            .disabled(generator.isGenerating)

                        if generator.isGenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 320, idealWidth: 360)

            // Right: Live preview
            DocumentPreviewView(html: previewHTML)
                .frame(minWidth: 400)
        }
        .onAppear { updatePreview() }
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            TextField(label, text: text)
                .font(.system(size: 11))
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, _ in updatePreview() }
        }
    }

    private func updatePreview() {
        if selectedType == .agreement && data.parties.count < 2 {
            data.parties = [data.companyName, data.clientName]
        }
        previewHTML = DocumentGenerator.previewHTML(type: selectedType, data: data)
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(data.reference.isEmpty ? selectedType.rawValue : data.reference).pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            generator.generateAndSave(type: selectedType, data: data, to: url) { result in
                if case .failure(let err) = result {
                    print("Export failed: \(err)")
                }
            }
        }
    }
    // MARK: - API Integration

    private func lookupPart() {
        guard !data.partNumber.isEmpty else { return }
        apiStatus = "Looking up..."
        Task {
            do {
                let details = try await api.getPartDetails(partNumber: data.partNumber)
                await MainActor.run {
                    data.title = details.description
                    data.specs = details.specs
                    data.features = details.features
                    if details.imageURL.count > 0 { data.imageURL = details.imageURL }
                    apiStatus = "Found: \(details.manufacturer) \(details.partNumber)"
                    updatePreview()
                }
            } catch {
                await MainActor.run { apiStatus = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func priceAllItems() {
        let parts = data.items.filter { !$0.partNumber.isEmpty }.map { ($0.partNumber, $0.quantity) }
        guard !parts.isEmpty else { return }
        apiStatus = "Pricing..."
        Task {
            do {
                let estimates = try await api.estimateCost(parts: parts)
                await MainActor.run {
                    for est in estimates {
                        if let idx = data.items.firstIndex(where: { $0.partNumber == est.partNumber }) {
                            data.items[idx].unitPrice = est.unitPrice
                        }
                    }
                    apiStatus = "Priced \(estimates.count) items"
                    updatePreview()
                }
            } catch {
                await MainActor.run { apiStatus = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func submitDFM() {
        guard !data.projectId.isEmpty else { return }
        apiStatus = "Submitting DFM..."
        Task {
            do {
                let jobId = try await api.submitDFM(projectId: data.projectId)
                await MainActor.run { apiStatus = "DFM submitted (job: \(jobId)). Polling..." }

                // Poll for results
                for _ in 0..<60 {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                    let result = try await api.checkDFMStatus(jobId: jobId)
                    if result.status == "completed" || result.status == "done" {
                        await MainActor.run {
                            data.dfmScore = result.score
                            data.dfmChecks = result.checks
                            data.dfmWarnings = result.warnings
                            data.dfmRecommendations = result.recommendations
                            apiStatus = "DFM complete — score: \(result.score)"
                            updatePreview()
                        }
                        return
                    } else if result.status == "failed" || result.status == "error" {
                        await MainActor.run { apiStatus = "DFM failed" }
                        return
                    }
                    await MainActor.run { apiStatus = "DFM \(result.status)..." }
                }
                await MainActor.run { apiStatus = "DFM timeout" }
            } catch {
                await MainActor.run { apiStatus = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

// MARK: - HTML Preview

struct DocumentPreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
