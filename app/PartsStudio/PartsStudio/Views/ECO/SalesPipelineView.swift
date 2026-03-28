#if os(macOS)
import SwiftUI
import AppKit

/// Sales Pipeline: Quote-to-commission wizard with operator-approved gates.
struct SalesPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .quoteBuild

    // Station 1: Quote Build
    @State private var bomPath: String = ""
    @State private var quantity: String = ""
    @State private var customerName: String = ""
    @State private var quoteResult: [String: Any]?
    @State private var quoteLoading = false
    @State private var quoteError: String?

    // Station 2: Quote Negotiate
    @State private var revisedQuantity: String = ""
    @State private var negotiateResult: [String: Any]?
    @State private var negotiateLoading = false

    // Station 3: Order Convert
    @State private var convertResult: [String: Any]?
    @State private var convertLoading = false

    // Station 4: Invoice Generate
    @State private var paymentTerms: String = "net30"
    @State private var taxRate: String = ""
    @State private var invoiceResult: [String: Any]?
    @State private var invoiceLoading = false

    // Station 5: Commission Calculate
    @State private var commissionRate: String = ""
    @State private var commissionResult: [String: Any]?
    @State private var commissionLoading = false

    enum Station: Int, CaseIterable {
        case quoteBuild = 1
        case quoteNegotiate = 2
        case orderConvert = 3
        case invoiceGenerate = 4
        case commissionCalculate = 5

        var title: String {
            switch self {
            case .quoteBuild: return "Quote Build"
            case .quoteNegotiate: return "Quote Negotiate"
            case .orderConvert: return "Order Convert"
            case .invoiceGenerate: return "Invoice Generate"
            case .commissionCalculate: return "Commission Calculate"
            }
        }

        var icon: String {
            switch self {
            case .quoteBuild: return "doc.text"
            case .quoteNegotiate: return "arrow.triangle.2.circlepath"
            case .orderConvert: return "cart"
            case .invoiceGenerate: return "dollarsign.circle"
            case .commissionCalculate: return "percent"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stationContent
                    }
                    .padding(24)
                }
                .frame(minWidth: 500)

                stationSidebar
                    .frame(width: 220)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.square")
                .foregroundStyle(Color.accentColor)
            Text("Sales Pipeline")
                .font(.headline)
            Divider().frame(height: 20)

            Text("Station \(currentStation.rawValue)/5")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(currentStation.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Station Content

    @ViewBuilder
    private var stationContent: some View {
        switch currentStation {
        case .quoteBuild: quoteBuildStation
        case .quoteNegotiate: quoteNegotiateStation
        case .orderConvert: orderConvertStation
        case .invoiceGenerate: invoiceGenerateStation
        case .commissionCalculate: commissionCalculateStation
        }
    }

    // MARK: - Station 1: Quote Build

    private var quoteBuildStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Quote Build", description: "Upload BOM and generate initial pricing quote", icon: "doc.text")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("BOM File:")
                        .font(.caption).fontWeight(.medium)
                    if bomPath.isEmpty {
                        Button("Select BOM...") { pickFile(extensions: ["csv", "xlsx"], binding: &bomPath) }
                            .buttonStyle(.bordered)
                    } else {
                        Text(URL(fileURLWithPath: bomPath).lastPathComponent)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button(action: { pickFile(extensions: ["csv", "xlsx"], binding: &bomPath) }) {
                            Image(systemName: "folder").font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Quantity:").font(.caption).fontWeight(.medium)
                    TextField("e.g. 1000", text: $quantity)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                HStack {
                    Text("Customer:").font(.caption).fontWeight(.medium)
                    TextField("Customer name", text: $customerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }

            HStack {
                Spacer()
                if quoteLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate Quote") { runQuoteBuild() }
                        .buttonStyle(.borderedProminent)
                        .disabled(bomPath.isEmpty || quantity.isEmpty || customerName.isEmpty)
                }
            }

            if let error = quoteError {
                errorBanner(error)
            }

            if let result = quoteResult,
               let lines = result["line_items"] as? [[String: Any]] {
                sectionLabel("Pricing Table (\(lines.count) items)")
                VStack(spacing: 0) {
                    HStack {
                        Text("Part").font(.caption2).fontWeight(.bold).frame(width: 120, alignment: .leading)
                        Text("Qty").font(.caption2).fontWeight(.bold).frame(width: 60)
                        Text("Unit").font(.caption2).fontWeight(.bold).frame(width: 80)
                        Text("Ext").font(.caption2).fontWeight(.bold).frame(width: 80)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(Array(lines.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item["part"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 120, alignment: .leading)
                            Text("\(item["qty"] as? Int ?? 0)")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 60)
                            Text(String(format: "$%.2f", item["unit_price"] as? Double ?? 0))
                                .font(.system(size: 10, design: .monospaced)).frame(width: 80)
                            Text(String(format: "$%.2f", item["ext_price"] as? Double ?? 0))
                                .font(.system(size: 10, design: .monospaced)).frame(width: 80)
                            Spacer()
                        }
                        .padding(.vertical, 2).padding(.horizontal, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if let total = result["total"] as? Double {
                    HStack {
                        Spacer()
                        statCard(String(format: "$%.2f", total), label: "Total", color: .blue)
                    }
                }

                approveRejectButtons(
                    approveLabel: "Proceed to Negotiate",
                    onApprove: { currentStation = .quoteNegotiate }
                )
            }
        }
    }

    // MARK: - Station 2: Quote Negotiate

    private var quoteNegotiateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Quote Negotiate", description: "Revise quantities and review margin impact", icon: "arrow.triangle.2.circlepath")

            HStack {
                Text("Revised Quantity:").font(.caption).fontWeight(.medium)
                TextField("e.g. 2000", text: $revisedQuantity)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                if negotiateLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Recalculate") { runNegotiate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(revisedQuantity.isEmpty)
                }
            }

            if let result = negotiateResult {
                let originalMargin = result["original_margin"] as? Double ?? 0
                let revisedMargin = result["revised_margin"] as? Double ?? 0
                let delta = revisedMargin - originalMargin

                HStack(spacing: 16) {
                    statCard(String(format: "%.1f%%", originalMargin), label: "Original Margin", color: .blue)
                    statCard(String(format: "%.1f%%", revisedMargin), label: "Revised Margin", color: .purple)
                    statCard(String(format: "%+.1f%%", delta), label: "Delta", color: delta >= 0 ? .green : .red)
                }

                approveRejectButtons(
                    approveLabel: "Accept Terms — Convert Order",
                    onApprove: { currentStation = .orderConvert }
                )
            }
        }
    }

    // MARK: - Station 3: Order Convert

    private var orderConvertStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Order Convert", description: "Verify stock availability and convert quote to order", icon: "cart")

            HStack {
                Spacer()
                if convertLoading {
                    ProgressView().controlSize(.small)
                    Text("Checking stock...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Check Readiness") { runConvert() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let result = convertResult {
                let allInStock = result["all_in_stock"] as? Bool ?? false
                let items = result["stock_items"] as? [[String: Any]] ?? []

                statCard(allInStock ? "READY" : "SHORTAGES", label: "Order Status", color: allInStock ? .green : .orange)

                if !items.isEmpty {
                    sectionLabel("Stock Check (\(items.count) items)")
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item["part"] as? String ?? "—")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text("need \(item["required"] as? Int ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("have \(item["available"] as? Int ?? 0)")
                                .font(.caption).foregroundStyle((item["available"] as? Int ?? 0) >= (item["required"] as? Int ?? 0) ? .green : .red)
                        }
                        .padding(.vertical, 2)
                    }
                }

                approveRejectButtons(
                    approveLabel: "Convert to Order",
                    onApprove: { currentStation = .invoiceGenerate }
                )
            }
        }
    }

    // MARK: - Station 4: Invoice Generate

    private var invoiceGenerateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Invoice Generate", description: "Set payment terms and generate invoice", icon: "dollarsign.circle")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Payment Terms:").font(.caption).fontWeight(.medium)
                    Picker("", selection: $paymentTerms) {
                        Text("Net 30").tag("net30")
                        Text("Net 60").tag("net60")
                        Text("Prepaid").tag("prepaid")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                HStack {
                    Text("Tax Rate (%):").font(.caption).fontWeight(.medium)
                    TextField("e.g. 8.25", text: $taxRate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            HStack {
                Spacer()
                if invoiceLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate Invoice") { runInvoice() }
                        .buttonStyle(.borderedProminent)
                        .disabled(taxRate.isEmpty)
                }
            }

            if let result = invoiceResult {
                let subtotal = result["subtotal"] as? Double ?? 0
                let tax = result["tax"] as? Double ?? 0
                let total = result["total"] as? Double ?? 0
                let invoiceID = result["invoice_id"] as? String ?? "—"

                sectionLabel("Invoice Preview")
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Invoice ID:").font(.caption).fontWeight(.medium); Spacer(); Text(invoiceID).font(.system(size: 11, design: .monospaced)) }
                    HStack { Text("Terms:").font(.caption).fontWeight(.medium); Spacer(); Text(paymentTerms).font(.caption) }
                    Divider()
                    HStack { Text("Subtotal:").font(.caption); Spacer(); Text(String(format: "$%.2f", subtotal)).font(.system(size: 11, design: .monospaced)) }
                    HStack { Text("Tax:").font(.caption); Spacer(); Text(String(format: "$%.2f", tax)).font(.system(size: 11, design: .monospaced)) }
                    Divider()
                    HStack { Text("Total:").font(.caption).fontWeight(.bold); Spacer(); Text(String(format: "$%.2f", total)).font(.system(size: 12, weight: .bold, design: .monospaced)) }
                }
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                approveRejectButtons(
                    approveLabel: "Approve Invoice — Calculate Commission",
                    onApprove: { currentStation = .commissionCalculate }
                )
            }
        }
    }

    // MARK: - Station 5: Commission Calculate

    private var commissionCalculateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Commission Calculate", description: "Calculate sales commission breakdown", icon: "percent")

            HStack {
                Text("Commission Rate (%):").font(.caption).fontWeight(.medium)
                TextField("e.g. 5.0", text: $commissionRate)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                if commissionLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Calculate") { runCommission() }
                        .buttonStyle(.borderedProminent)
                        .disabled(commissionRate.isEmpty)
                }
            }

            if let result = commissionResult {
                let revenue = result["revenue"] as? Double ?? 0
                let commission = result["commission"] as? Double ?? 0
                let rep = result["rep_name"] as? String ?? "—"

                HStack(spacing: 16) {
                    statCard(String(format: "$%.2f", revenue), label: "Revenue", color: .blue)
                    statCard(String(format: "$%.2f", commission), label: "Commission", color: .green)
                    statCard(rep, label: "Rep", color: .purple)
                }

                if let breakdown = result["breakdown"] as? [[String: Any]] {
                    sectionLabel("Commission Breakdown")
                    ForEach(Array(breakdown.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item["label"] as? String ?? "—")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(String(format: "$%.2f", item["amount"] as? Double ?? 0))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Button("Start Over") {
                        currentStation = .quoteBuild
                        quoteResult = nil; negotiateResult = nil; convertResult = nil
                        invoiceResult = nil; commissionResult = nil
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Pipeline Complete")  {}
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Station Sidebar

    private var stationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pipeline")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()

            ForEach(Station.allCases, id: \.rawValue) { station in
                HStack(spacing: 8) {
                    Image(systemName: station.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(stationColor(station))
                        .frame(width: 16)

                    Text("\(station.rawValue). \(station.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(station == currentStation ? .primary : .secondary)

                    Spacer()

                    if station.rawValue < currentStation.rawValue {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else if station == currentStation {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(station == currentStation ? Color.accentColor.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    if station.rawValue <= currentStation.rawValue {
                        currentStation = station
                    }
                }
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func stationHeader(_ title: String, description: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3).fontWeight(.semibold)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func approveRejectButtons(approveLabel: String, onApprove: @escaping () -> Void) -> some View {
        HStack {
            Button("Reject") {
                currentStation = .quoteBuild
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Spacer()

            Button(approveLabel) { onApprove() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func statCard(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg).font(.caption)
        }
        .padding(8).background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func stationColor(_ station: Station) -> Color {
        if station.rawValue < currentStation.rawValue { return .green }
        if station == currentStation { return .blue }
        return .gray
    }

    // MARK: - File Picker

    private func pickFile(extensions: [String], binding: inout String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
        panel.message = "Select file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        binding = url.path
    }

    // MARK: - Actions

    private func runQuoteBuild() {
        quoteLoading = true; quoteError = nil; quoteResult = nil
        Task {
            do {
                let _ = bomPath; let _ = quantity; let _ = customerName
                // Placeholder: let result = try await PartsAPIClient.shared.salesQuoteBuild(...)
                let result: [String: Any] = [:]
                await MainActor.run { quoteResult = result; quoteLoading = false }
            } catch {
                await MainActor.run { quoteError = error.localizedDescription; quoteLoading = false }
            }
        }
    }

    private func runNegotiate() {
        negotiateLoading = true; negotiateResult = nil
        Task {
            do {
                let _ = revisedQuantity
                // Placeholder: let result = try await PartsAPIClient.shared.salesNegotiate(...)
                let result: [String: Any] = [:]
                await MainActor.run { negotiateResult = result; negotiateLoading = false }
            } catch {
                await MainActor.run { negotiateLoading = false }
            }
        }
    }

    private func runConvert() {
        convertLoading = true; convertResult = nil
        Task {
            do {
                // Placeholder: let result = try await PartsAPIClient.shared.salesConvertOrder(...)
                let result: [String: Any] = [:]
                await MainActor.run { convertResult = result; convertLoading = false }
            } catch {
                await MainActor.run { convertLoading = false }
            }
        }
    }

    private func runInvoice() {
        invoiceLoading = true; invoiceResult = nil
        Task {
            do {
                let _ = paymentTerms; let _ = taxRate
                // Placeholder: let result = try await PartsAPIClient.shared.salesGenerateInvoice(...)
                let result: [String: Any] = [:]
                await MainActor.run { invoiceResult = result; invoiceLoading = false }
            } catch {
                await MainActor.run { invoiceLoading = false }
            }
        }
    }

    private func runCommission() {
        commissionLoading = true; commissionResult = nil
        Task {
            do {
                let _ = commissionRate
                // Placeholder: let result = try await PartsAPIClient.shared.salesCommission(...)
                let result: [String: Any] = [:]
                await MainActor.run { commissionResult = result; commissionLoading = false }
            } catch {
                await MainActor.run { commissionLoading = false }
            }
        }
    }
}
#endif
