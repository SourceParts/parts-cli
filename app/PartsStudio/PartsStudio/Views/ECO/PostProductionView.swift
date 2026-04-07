#if os(macOS)
import SwiftUI
import AppKit

/// Post-Production Pipeline: RMA/Failure Analysis/ECO Feedback wizard with operator-approved gates.
struct PostProductionView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .rmaProcess

    // Station 1: RMA Process
    @State private var orderID: String = ""
    @State private var serialNumber: String = ""
    @State private var failureDescription: String = ""
    @State private var rmaLoading = false
    @State private var rmaResult: [String: Any]?
    @State private var rmaError: String?

    // Station 2: Failure Analysis
    @State private var failureCSVPath: String = ""
    @State private var failureLoading = false
    @State private var failureResult: [String: Any]?
    @State private var failureError: String?

    // Station 3: ECO Feedback
    @State private var analysisID: String = ""
    @State private var ecoLoading = false
    @State private var ecoResult: [String: Any]?
    @State private var ecoError: String?

    enum Station: Int, CaseIterable {
        case rmaProcess = 1
        case failureAnalysis = 2
        case ecoFeedback = 3

        var title: String {
            switch self {
            case .rmaProcess: return "RMA Process"
            case .failureAnalysis: return "Failure Analysis"
            case .ecoFeedback: return "ECO Feedback"
            }
        }

        var icon: String {
            switch self {
            case .rmaProcess: return "arrow.uturn.backward.circle"
            case .failureAnalysis: return "chart.bar.xaxis"
            case .ecoFeedback: return "doc.text.magnifyingglass"
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
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.accentColor)
            Text("Post-Production")
                .font(.headline)
            Divider().frame(height: 20)

            Text("Station \(currentStation.rawValue)/3")
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
        case .rmaProcess: rmaStation
        case .failureAnalysis: failureStation
        case .ecoFeedback: ecoStation
        }
    }

    // MARK: - Station 1: RMA Process

    private var rmaStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("RMA Process", description: "Process return merchandise authorization requests", icon: "arrow.uturn.backward.circle")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("Order ID", text: $orderID)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    TextField("Serial Number", text: $serialNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                Text("Failure Description")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $failureDescription)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 120)
                    .border(Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack {
                Spacer()
                if rmaLoading {
                    ProgressView().controlSize(.small)
                    Text("Processing RMA...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Submit RMA") { runRMA() }
                        .buttonStyle(.borderedProminent)
                        .disabled(orderID.isEmpty || serialNumber.isEmpty || failureDescription.isEmpty)
                }
            }

            if let error = rmaError {
                errorBanner(error)
            }

            if let result = rmaResult {
                let disposition = result["disposition"] as? String ?? "unknown"
                let rmaNumber = result["rma_number"] as? String ?? ""
                let reason = result["reason"] as? String ?? ""

                sectionLabel("RMA Disposition")
                VStack(spacing: 8) {
                    Text(disposition.uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(dispositionColor(disposition))

                    HStack(spacing: 16) {
                        statCard(rmaNumber, label: "RMA Number", color: .blue)
                        statCard(disposition.capitalized, label: "Disposition", color: dispositionColor(disposition))
                    }

                    if !reason.isEmpty {
                        Text("Reason: \(reason)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                approveRejectButtons(
                    approveLabel: "RMA Approved — Proceed to Failure Analysis",
                    onApprove: { currentStation = .failureAnalysis }
                )
            }
        }
    }

    // MARK: - Station 2: Failure Analysis

    private var failureStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Failure Analysis", description: "Analyze failure patterns with Pareto classification", icon: "chart.bar.xaxis")

            HStack(spacing: 12) {
                if failureCSVPath.isEmpty {
                    Button("Select Failure Data CSV...") { pickFailureCSV() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(URL(fileURLWithPath: failureCSVPath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickFailureCSV() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                if failureLoading {
                    ProgressView().controlSize(.small)
                } else if !failureCSVPath.isEmpty {
                    Button("Analyze Failures") { runFailureAnalysis() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let error = failureError {
                errorBanner(error)
            }

            if let result = failureResult {
                let pareto = result["pareto"] as? [[String: Any]] ?? []
                let lotCorrelation = result["lot_correlation"] as? String ?? "None detected"

                if !pareto.isEmpty {
                    sectionLabel("Pareto Analysis")

                    // Table header
                    HStack {
                        Text("Failure Mode").font(.system(size: 10, weight: .bold)).frame(width: 160, alignment: .leading)
                        Text("Count").font(.system(size: 10, weight: .bold)).frame(width: 60, alignment: .trailing)
                        Text("%").font(.system(size: 10, weight: .bold)).frame(width: 60, alignment: .trailing)
                        Text("Cumulative %").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .trailing)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .background(Color.gray.opacity(0.08))

                    ForEach(0..<pareto.count, id: \.self) { i in
                        let row = pareto[i]
                        let pct = row["percentage"] as? Double ?? 0.0
                        HStack {
                            Text(row["failure_mode"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 160, alignment: .leading)
                            Text("\(row["count"] as? Int ?? 0)")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                            Text(String(format: "%.1f%%", pct))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                            Text(String(format: "%.1f%%", row["cumulative_percentage"] as? Double ?? 0.0))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                            Spacer()

                            // Simple bar representation
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.orange)
                                    .frame(width: geo.size.width * min(pct / 100.0, 1.0), height: 8)
                            }
                            .frame(width: 80, height: 8)
                        }
                        .padding(.vertical, 2)
                    }
                }

                sectionLabel("Lot Correlation")
                Text(lotCorrelation)
                    .font(.system(size: 11))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                approveRejectButtons(
                    approveLabel: "Analysis Complete — Proceed to ECO Feedback",
                    onApprove: { currentStation = .ecoFeedback }
                )
            }
        }
    }

    // MARK: - Station 3: ECO Feedback

    private var ecoStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("ECO Feedback", description: "Generate Engineering Change Orders from failure analysis", icon: "doc.text.magnifyingglass")

            HStack {
                TextField("Analysis ID", text: $analysisID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Spacer()
                if ecoLoading {
                    ProgressView().controlSize(.small)
                    Text("Generating ECNs...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Generate ECO Feedback") { runECOFeedback() }
                        .buttonStyle(.borderedProminent)
                        .disabled(analysisID.isEmpty)
                }
            }

            if let error = ecoError {
                errorBanner(error)
            }

            if let result = ecoResult,
               let ecns = result["suggested_ecns"] as? [[String: Any]] {
                sectionLabel("Suggested ECNs (\(ecns.count))")

                ForEach(0..<ecns.count, id: \.self) { i in
                    let ecn = ecns[i]
                    let severity = ecn["severity"] as? String ?? "low"
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(ecn["ecn_id"] as? String ?? "ECN-???")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Spacer()
                            Text(severity.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(severityColor(severity).opacity(0.15))
                                .foregroundStyle(severityColor(severity))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Text(ecn["title"] as? String ?? "")
                            .font(.system(size: 12, weight: .medium))
                        Text(ecn["rationale"] as? String ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                approveRejectButtons(
                    approveLabel: "ECO Feedback Approved — Pipeline Complete",
                    onApprove: {
                        currentStation = .rmaProcess
                        rmaResult = nil
                        failureResult = nil
                        ecoResult = nil
                    }
                )
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
                currentStation = .rmaProcess
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

    private func stationColor(_ station: Station) -> Color {
        if station.rawValue < currentStation.rawValue { return .green }
        if station == currentStation { return .blue }
        return .gray
    }

    private func dispositionColor(_ disposition: String) -> Color {
        switch disposition {
        case "replace": return .blue
        case "repair": return .orange
        case "refund": return .red
        default: return .gray
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .green
        default: return .gray
        }
    }

    // MARK: - Actions

    private func pickFailureCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Select failure data CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        failureCSVPath = url.path
    }

    private func runRMA() {
        rmaLoading = true; rmaError = nil; rmaResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.postProductionRMA(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    rmaResult = [
                        "disposition": "replace",
                        "rma_number": "RMA-\(Int.random(in: 10000...99999))",
                        "reason": "Component failure within warranty period",
                    ] as [String: Any]
                    rmaLoading = false
                }
            } catch {
                await MainActor.run { rmaError = error.localizedDescription; rmaLoading = false }
            }
        }
    }

    private func runFailureAnalysis() {
        failureLoading = true; failureError = nil; failureResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.postProductionFailureAnalysis(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    failureResult = [
                        "pareto": [] as [[String: Any]],
                        "lot_correlation": "None detected",
                    ] as [String: Any]
                    failureLoading = false
                }
            } catch {
                await MainActor.run { failureError = error.localizedDescription; failureLoading = false }
            }
        }
    }

    private func runECOFeedback() {
        ecoLoading = true; ecoError = nil; ecoResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.postProductionECOFeedback(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    ecoResult = ["suggested_ecns": [] as [[String: Any]]] as [String: Any]
                    ecoLoading = false
                }
            } catch {
                await MainActor.run { ecoError = error.localizedDescription; ecoLoading = false }
            }
        }
    }
}
#endif
