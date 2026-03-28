#if os(macOS)
import SwiftUI
import AppKit

/// DFM Pipeline: Estimate/Submit/Status/Findings/Generate/Deliver wizard with operator-approved gates.
struct DFMPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .estimate

    // Station 1: Estimate
    @State private var gerberPath: String = ""
    @State private var selectedTier: String = "basic"
    @State private var estimateLoading = false
    @State private var estimateResult: [String: Any]?
    @State private var estimateError: String?

    // Station 2: Submit
    @State private var customerName: String = ""
    @State private var customerEmail: String = ""
    @State private var promoCode: String = ""
    @State private var submitLoading = false
    @State private var submitResult: [String: Any]?
    @State private var submitError: String?

    // Station 3: Status
    @State private var requestID: String = ""
    @State private var statusLoading = false
    @State private var statusResult: [String: Any]?
    @State private var statusError: String?

    // Station 4: Add Findings
    @State private var findingCategory: String = "design"
    @State private var findingSeverity: String = "medium"
    @State private var findingDescription: String = ""
    @State private var findingRecommendation: String = ""
    @State private var findings: [[String: String]] = []
    @State private var findingsLoading = false
    @State private var findingsError: String?

    // Station 5: Generate Report
    @State private var generateLoading = false
    @State private var generateResult: [String: Any]?
    @State private var generateError: String?

    // Station 6: Deliver Report
    @State private var emailOverride: String = ""
    @State private var customMessage: String = ""
    @State private var deliverLoading = false
    @State private var deliverResult: [String: Any]?
    @State private var deliverError: String?

    private let tiers = [("basic", "$97"), ("comprehensive", "$297")]
    private let categories = ["design", "manufacturing", "thermal", "signal_integrity", "mechanical", "component"]
    private let severities = ["critical", "high", "medium", "low", "info"]

    enum Station: Int, CaseIterable {
        case estimate = 1
        case submit = 2
        case status = 3
        case addFindings = 4
        case generateReport = 5
        case deliverReport = 6

        var title: String {
            switch self {
            case .estimate: return "Estimate"
            case .submit: return "Submit"
            case .status: return "Status"
            case .addFindings: return "Add Findings"
            case .generateReport: return "Generate Report"
            case .deliverReport: return "Deliver Report"
            }
        }

        var icon: String {
            switch self {
            case .estimate: return "dollarsign.circle"
            case .submit: return "paperplane"
            case .status: return "clock.arrow.circlepath"
            case .addFindings: return "plus.magnifyingglass"
            case .generateReport: return "doc.richtext"
            case .deliverReport: return "envelope"
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
            Image(systemName: "gearshape.2")
                .foregroundStyle(Color.accentColor)
            Text("DFM Pipeline")
                .font(.headline)
            Divider().frame(height: 20)

            Text("Station \(currentStation.rawValue)/6")
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

            if !requestID.isEmpty {
                Text("ID: \(requestID)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Station Content

    @ViewBuilder
    private var stationContent: some View {
        switch currentStation {
        case .estimate: estimateStation
        case .submit: submitStation
        case .status: statusStation
        case .addFindings: findingsStation
        case .generateReport: generateStation
        case .deliverReport: deliverStation
        }
    }

    // MARK: - Station 1: Estimate

    private var estimateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Estimate", description: "Upload Gerber files and select review tier", icon: "dollarsign.circle")

            HStack(spacing: 12) {
                if gerberPath.isEmpty {
                    Button("Select Gerber File...") { pickGerberFile() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(URL(fileURLWithPath: gerberPath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickGerberFile() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionLabel("Review Tier")
            HStack(spacing: 12) {
                ForEach(tiers, id: \.0) { tier in
                    Button(action: { selectedTier = tier.0 }) {
                        VStack(spacing: 4) {
                            Text(tier.0.capitalized)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tier.1)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(selectedTier == tier.0 ? .white : .blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedTier == tier.0 ? Color.blue : Color.blue.opacity(0.08))
                        .foregroundStyle(selectedTier == tier.0 ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                if estimateLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Get Estimate") { runEstimate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(gerberPath.isEmpty)
                }
            }

            if let error = estimateError {
                errorBanner(error)
            }

            if let result = estimateResult {
                let complexity = result["complexity_score"] as? Double ?? 0.0
                let price = result["price"] as? String ?? selectedTier == "basic" ? "$97" : "$297"
                let layers = result["layers"] as? Int ?? 0
                let netCount = result["net_count"] as? Int ?? 0

                sectionLabel("Complexity Score")
                gaugeView(value: complexity, maxValue: 10.0, label: "\(String(format: "%.1f", complexity)) / 10", color: complexity < 4 ? .green : (complexity < 7 ? .orange : .red))

                // Pricing Card
                VStack(spacing: 8) {
                    Text(price)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("\(selectedTier.capitalized) Review")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        statCard("\(layers)", label: "Layers", color: .blue)
                        statCard("\(netCount)", label: "Nets", color: .purple)
                        statCard(String(format: "%.1f", complexity), label: "Complexity", color: complexity < 4 ? .green : .orange)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                approveRejectButtons(
                    approveLabel: "Accept Estimate — Proceed to Submit",
                    onApprove: { currentStation = .submit }
                )
            }
        }
    }

    // MARK: - Station 2: Submit

    private var submitStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Submit", description: "Enter customer details and submit DFM review request", icon: "paperplane")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Customer Name", text: $customerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Customer Email", text: $customerEmail)
                    .textFieldStyle(.roundedBorder)
                TextField("Promo Code (optional)", text: $promoCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            HStack {
                Spacer()
                if submitLoading {
                    ProgressView().controlSize(.small)
                    Text("Submitting...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Submit Request") { runSubmit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(customerName.isEmpty || customerEmail.isEmpty)
                }
            }

            if let error = submitError {
                errorBanner(error)
            }

            if let result = submitResult {
                let reqID = result["request_id"] as? String ?? ""
                let status = result["status"] as? String ?? "submitted"

                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Request Submitted")
                        .font(.title3).fontWeight(.semibold)
                    Text("Request ID: \(reqID)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Status: \(status)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                approveRejectButtons(
                    approveLabel: "Proceed to Status Tracking",
                    onApprove: {
                        requestID = reqID
                        currentStation = .status
                    }
                )
            }
        }
    }

    // MARK: - Station 3: Status

    private var statusStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Status", description: "Track DFM review progress", icon: "clock.arrow.circlepath")

            HStack {
                Text("Request ID:")
                    .font(.caption).foregroundStyle(.secondary)
                Text(requestID.isEmpty ? "Not assigned" : requestID)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                if statusLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Status") { runStatusCheck() }
                        .buttonStyle(.borderedProminent)
                        .disabled(requestID.isEmpty)
                }
            }

            if let error = statusError {
                errorBanner(error)
            }

            if let result = statusResult {
                let progress = result["progress"] as? Double ?? 0.0
                let statusText = result["status_text"] as? String ?? "Processing"
                let stage = result["stage"] as? String ?? ""

                sectionLabel("Progress")
                gaugeView(value: progress, maxValue: 100.0, label: "\(String(format: "%.0f", progress))%", color: progress >= 100 ? .green : .blue)

                HStack(spacing: 16) {
                    statCard(statusText, label: "Status", color: .blue)
                    statCard(stage, label: "Stage", color: .purple)
                }

                if progress >= 100 {
                    approveRejectButtons(
                        approveLabel: "Review Complete — Add Findings",
                        onApprove: { currentStation = .addFindings }
                    )
                } else {
                    Text("Review is still in progress. Check back later or proceed to add preliminary findings.")
                        .font(.caption).foregroundStyle(.secondary)

                    approveRejectButtons(
                        approveLabel: "Proceed to Add Findings",
                        onApprove: { currentStation = .addFindings }
                    )
                }
            }
        }
    }

    // MARK: - Station 4: Add Findings

    private var findingsStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Add Findings", description: "Enter DFM findings for the report", icon: "plus.magnifyingglass")

            // Entry form
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("Category", selection: $findingCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.replacingOccurrences(of: "_", with: " ").capitalized).tag(cat)
                        }
                    }
                    .frame(width: 180)

                    Picker("Severity", selection: $findingSeverity) {
                        ForEach(severities, id: \.self) { sev in
                            Text(sev.capitalized).tag(sev)
                        }
                    }
                    .frame(width: 140)
                }

                TextField("Description", text: $findingDescription)
                    .textFieldStyle(.roundedBorder)
                TextField("Recommendation", text: $findingRecommendation)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Add Finding") {
                        findings.append([
                            "category": findingCategory,
                            "severity": findingSeverity,
                            "description": findingDescription,
                            "recommendation": findingRecommendation,
                        ])
                        findingDescription = ""
                        findingRecommendation = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(findingDescription.isEmpty || findingRecommendation.isEmpty)
                }
            }

            if let error = findingsError {
                errorBanner(error)
            }

            if !findings.isEmpty {
                sectionLabel("Findings (\(findings.count))")

                // Table header
                HStack {
                    Text("Category").font(.system(size: 10, weight: .bold)).frame(width: 100, alignment: .leading)
                    Text("Severity").font(.system(size: 10, weight: .bold)).frame(width: 70, alignment: .leading)
                    Text("Description").font(.system(size: 10, weight: .bold)).frame(minWidth: 150, alignment: .leading)
                    Text("Recommendation").font(.system(size: 10, weight: .bold)).frame(minWidth: 120, alignment: .leading)
                    Spacer()
                }
                .padding(.vertical, 4)

                ForEach(0..<findings.count, id: \.self) { i in
                    let f = findings[i]
                    let sev = f["severity"] ?? "medium"
                    HStack {
                        Text((f["category"] ?? "").replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(sev.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(findingSeverityColor(sev))
                            .frame(width: 70, alignment: .leading)
                        Text(f["description"] ?? "")
                            .font(.system(size: 10))
                            .frame(minWidth: 150, alignment: .leading)
                            .lineLimit(2)
                        Text(f["recommendation"] ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 120, alignment: .leading)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }

                approveRejectButtons(
                    approveLabel: "Findings Complete — Generate Report",
                    onApprove: { currentStation = .generateReport }
                )
            }
        }
    }

    // MARK: - Station 5: Generate Report

    private var generateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Generate Report", description: "Compile findings into a deliverable DFM report", icon: "doc.richtext")

            HStack(spacing: 16) {
                statCard("\(findings.count)", label: "Findings", color: .blue)
                statCard(selectedTier.capitalized, label: "Tier", color: .purple)
                statCard(requestID.isEmpty ? "N/A" : requestID, label: "Request ID", color: .gray)
            }

            HStack {
                Spacer()
                if generateLoading {
                    ProgressView().controlSize(.small)
                    Text("Generating report...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Generate Report") { runGenerateReport() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }

            if let error = generateError {
                errorBanner(error)
            }

            if let result = generateResult {
                let reportURL = result["report_url"] as? String ?? ""
                let emailSent = result["email_sent"] as? Bool ?? false

                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Report Generated")
                        .font(.title3).fontWeight(.semibold)

                    if !reportURL.isEmpty {
                        Text(reportURL)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.blue)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: emailSent ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(emailSent ? .green : .red)
                        Text(emailSent ? "Confirmation email sent" : "Email not sent")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                approveRejectButtons(
                    approveLabel: "Proceed to Deliver Report",
                    onApprove: { currentStation = .deliverReport }
                )
            }
        }
    }

    // MARK: - Station 6: Deliver Report

    private var deliverStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Deliver Report", description: "Send the final report to the customer", icon: "envelope")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Email Override (leave blank for original)", text: $emailOverride)
                    .textFieldStyle(.roundedBorder)

                Text("Custom Message (optional)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $customMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 120)
                    .border(Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack {
                Spacer()
                if deliverLoading {
                    ProgressView().controlSize(.small)
                    Text("Delivering...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Deliver Report") { runDeliverReport() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }

            if let error = deliverError {
                errorBanner(error)
            }

            if let result = deliverResult {
                let delivered = result["delivered"] as? Bool ?? false
                let recipient = result["recipient"] as? String ?? ""

                VStack(spacing: 12) {
                    Image(systemName: delivered ? "envelope.open.fill" : "envelope.badge.shield.half.filled.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(delivered ? .green : .red)
                    Text(delivered ? "Report Delivered" : "Delivery Failed")
                        .font(.title3).fontWeight(.semibold)
                    Text("Sent to: \(recipient)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                HStack {
                    Button("Start New Review") {
                        // Reset wizard
                        currentStation = .estimate
                        gerberPath = ""
                        estimateResult = nil
                        submitResult = nil
                        statusResult = nil
                        findings = []
                        generateResult = nil
                        deliverResult = nil
                        requestID = ""
                        customerName = ""
                        customerEmail = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
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
                currentStation = .estimate
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
    private func gaugeView(value: Double, maxValue: Double, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 20)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(value / maxValue, 1.0), height: 20)
                }
            }
            .frame(height: 20)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func stationColor(_ station: Station) -> Color {
        if station.rawValue < currentStation.rawValue { return .green }
        if station == currentStation { return .blue }
        return .gray
    }

    private func findingSeverityColor(_ severity: String) -> Color {
        switch severity {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .green
        case "info": return .blue
        default: return .gray
        }
    }

    // MARK: - Actions

    private func pickGerberFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "zip")!, .init(filenameExtension: "gbr")!]
        panel.message = "Select Gerber file or archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        gerberPath = url.path
    }

    private func runEstimate() {
        estimateLoading = true; estimateError = nil; estimateResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.dfmEstimate(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    estimateResult = [
                        "complexity_score": 5.2,
                        "price": selectedTier == "basic" ? "$97" : "$297",
                        "layers": 4,
                        "net_count": 186,
                    ] as [String: Any]
                    estimateLoading = false
                }
            } catch {
                await MainActor.run { estimateError = error.localizedDescription; estimateLoading = false }
            }
        }
    }

    private func runSubmit() {
        submitLoading = true; submitError = nil; submitResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.dfmSubmit(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    let genID = "DFM-\(Int.random(in: 10000...99999))"
                    submitResult = [
                        "request_id": genID,
                        "status": "submitted",
                    ] as [String: Any]
                    submitLoading = false
                }
            } catch {
                await MainActor.run { submitError = error.localizedDescription; submitLoading = false }
            }
        }
    }

    private func runStatusCheck() {
        statusLoading = true; statusError = nil; statusResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.dfmStatus(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    statusResult = [
                        "progress": 100.0,
                        "status_text": "Complete",
                        "stage": "Review finished",
                    ] as [String: Any]
                    statusLoading = false
                }
            } catch {
                await MainActor.run { statusError = error.localizedDescription; statusLoading = false }
            }
        }
    }

    private func runGenerateReport() {
        generateLoading = true; generateError = nil; generateResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.dfmGenerateReport(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    generateResult = [
                        "report_url": "https://parts.dev/reports/\(requestID).pdf",
                        "email_sent": true,
                    ] as [String: Any]
                    generateLoading = false
                }
            } catch {
                await MainActor.run { generateError = error.localizedDescription; generateLoading = false }
            }
        }
    }

    private func runDeliverReport() {
        deliverLoading = true; deliverError = nil; deliverResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.dfmDeliverReport(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    deliverResult = [
                        "delivered": true,
                        "recipient": emailOverride.isEmpty ? customerEmail : emailOverride,
                    ] as [String: Any]
                    deliverLoading = false
                }
            } catch {
                await MainActor.run { deliverError = error.localizedDescription; deliverLoading = false }
            }
        }
    }
}
#endif
