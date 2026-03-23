import SwiftUI
import WebKit

struct DocumentEditorView: View {
    @StateObject private var generator = DocumentGenerator()
    @State private var selectedType: DocumentType = .quote
    @State private var data = DocumentData()
    @State private var previewHTML = ""

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
                        field("Part Number", text: $data.partNumber)
                        // Specs are managed via the specs editor
                    }

                    // Line items (quotes, invoices, BOM)
                    if [.quote, .invoice, .bom].contains(selectedType) {
                        Divider()
                        HStack {
                            Text("Line Items").font(.caption).foregroundStyle(.secondary)
                            Spacer()
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
