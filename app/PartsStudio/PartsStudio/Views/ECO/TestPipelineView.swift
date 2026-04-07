#if os(macOS)
import SwiftUI
import AppKit

/// Test Pipeline: Coverage/Provisioning/Reliability wizard with operator-approved gates.
struct TestPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .coverageAnalysis

    // Station 1: Coverage Analysis
    @State private var testPointsCSVPath: String = ""
    @State private var pcbFilePath: String = ""
    @State private var coverageLoading = false
    @State private var coverageResult: [String: Any]?
    @State private var coverageError: String?

    // Station 2: Device Provisioning
    @State private var firmwareURL: String = ""
    @State private var deviceIDs: String = ""
    @State private var provisionLoading = false
    @State private var provisionResult: [String: Any]?
    @State private var provisionError: String?

    // Station 3: Reliability Prediction
    @State private var reliabilityBomPath: String = ""
    @State private var ambientTemp: String = "25"
    @State private var selectedEnvironment: String = "ground_benign"
    @State private var reliabilityLoading = false
    @State private var reliabilityResult: [String: Any]?
    @State private var reliabilityError: String?

    private let environments = ["ground_benign", "ground_fixed", "airborne"]

    enum Station: Int, CaseIterable {
        case coverageAnalysis = 1
        case deviceProvisioning = 2
        case reliabilityPrediction = 3

        var title: String {
            switch self {
            case .coverageAnalysis: return "Coverage Analysis"
            case .deviceProvisioning: return "Device Provisioning"
            case .reliabilityPrediction: return "Reliability Prediction"
            }
        }

        var icon: String {
            switch self {
            case .coverageAnalysis: return "target"
            case .deviceProvisioning: return "key.fill"
            case .reliabilityPrediction: return "chart.line.uptrend.xyaxis"
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
            Image(systemName: "testtube.2")
                .foregroundStyle(Color.accentColor)
            Text("Test Pipeline")
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
        case .coverageAnalysis: coverageStation
        case .deviceProvisioning: provisioningStation
        case .reliabilityPrediction: reliabilityStation
        }
    }

    // MARK: - Station 1: Coverage Analysis

    private var coverageStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Coverage Analysis", description: "Analyze test point coverage against PCB design", icon: "target")

            HStack(spacing: 12) {
                if testPointsCSVPath.isEmpty {
                    Button("Select Test Points CSV...") { pickTestPointsCSV() }
                        .buttonStyle(.bordered)
                } else {
                    Text(URL(fileURLWithPath: testPointsCSVPath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickTestPointsCSV() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                if pcbFilePath.isEmpty {
                    Button("Select .kicad_pcb...") { pickPCBFile() }
                        .buttonStyle(.bordered)
                } else {
                    Text(URL(fileURLWithPath: pcbFilePath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickPCBFile() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                if coverageLoading {
                    ProgressView().controlSize(.small)
                } else if !testPointsCSVPath.isEmpty && !pcbFilePath.isEmpty {
                    Button("Analyze Coverage") { runCoverageAnalysis() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let error = coverageError {
                errorBanner(error)
            }

            if let result = coverageResult {
                let coveragePct = result["coverage_percentage"] as? Double ?? 0.0
                let blockedPoints = result["blocked_points"] as? [[String: Any]] ?? []

                sectionLabel("Test Coverage")
                gaugeView(value: coveragePct, maxValue: 100.0, label: "\(String(format: "%.1f", coveragePct))%", color: coveragePct >= 95 ? .green : (coveragePct >= 80 ? .orange : .red))

                HStack(spacing: 16) {
                    statCard("\(String(format: "%.1f", coveragePct))%", label: "Coverage", color: coveragePct >= 95 ? .green : .orange)
                    statCard("\(blockedPoints.count)", label: "Blocked Points", color: blockedPoints.isEmpty ? .green : .red)
                }

                if !blockedPoints.isEmpty {
                    sectionLabel("Blocked Test Points")

                    HStack {
                        Text("Net").font(.system(size: 10, weight: .bold)).frame(width: 120, alignment: .leading)
                        Text("Pad").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                        Text("Reason").font(.system(size: 10, weight: .bold)).frame(minWidth: 100, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    ForEach(0..<blockedPoints.count, id: \.self) { i in
                        let pt = blockedPoints[i]
                        HStack {
                            Text(pt["net"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            Text(pt["pad"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                            Text(pt["reason"] as? String ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 100, alignment: .leading)
                            Spacer()
                        }
                        .padding(.vertical, 1)
                    }
                }

                approveRejectButtons(
                    approveLabel: "Coverage Accepted — Proceed to Provisioning",
                    onApprove: { currentStation = .deviceProvisioning }
                )
            }
        }
    }

    // MARK: - Station 2: Device Provisioning

    private var provisioningStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Device Provisioning", description: "Flash firmware and provision device credentials", icon: "key.fill")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Firmware URL", text: $firmwareURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Device IDs (comma-separated)", text: $deviceIDs)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                if provisionLoading {
                    ProgressView().controlSize(.small)
                    Text("Provisioning...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Provision Devices") { runProvisioning() }
                        .buttonStyle(.borderedProminent)
                        .disabled(firmwareURL.isEmpty || deviceIDs.isEmpty)
                }
            }

            if let error = provisionError {
                errorBanner(error)
            }

            if let result = provisionResult,
               let devices = result["devices"] as? [[String: Any]] {
                sectionLabel("Provisioning Results (\(devices.count) devices)")

                // Table header
                HStack {
                    Text("Device ID").font(.system(size: 10, weight: .bold)).frame(width: 100, alignment: .leading)
                    Text("Serial").font(.system(size: 10, weight: .bold)).frame(width: 100, alignment: .leading)
                    Text("Certificate").font(.system(size: 10, weight: .bold)).frame(width: 120, alignment: .leading)
                    Text("Key").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                    Spacer()
                }
                .padding(.vertical, 4)

                ForEach(0..<devices.count, id: \.self) { i in
                    let dev = devices[i]
                    HStack {
                        Text(dev["device_id"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(dev["serial"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(dev["certificate"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                        Text(dev["key_status"] as? String ?? "")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle((dev["key_status"] as? String) == "ok" ? .green : .red)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }

                let okCount = devices.filter { ($0["key_status"] as? String) == "ok" }.count
                HStack(spacing: 16) {
                    statCard("\(okCount)/\(devices.count)", label: "Provisioned", color: okCount == devices.count ? .green : .orange)
                }

                approveRejectButtons(
                    approveLabel: "Provisioning Complete — Proceed to Reliability",
                    onApprove: { currentStation = .reliabilityPrediction }
                )
            }
        }
    }

    // MARK: - Station 3: Reliability Prediction

    private var reliabilityStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Reliability Prediction", description: "Predict MTBF and identify weakest components", icon: "chart.line.uptrend.xyaxis")

            HStack(spacing: 12) {
                if reliabilityBomPath.isEmpty {
                    Button("Select BOM...") { pickReliabilityBOM() }
                        .buttonStyle(.bordered)
                } else {
                    Text(URL(fileURLWithPath: reliabilityBomPath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickReliabilityBOM() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                TextField("Ambient Temp (C)", text: $ambientTemp)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(environments, id: \.self) { env in
                        Text(env.replacingOccurrences(of: "_", with: " ").capitalized).tag(env)
                    }
                }
                .frame(width: 180)
            }

            HStack {
                Spacer()
                if reliabilityLoading {
                    ProgressView().controlSize(.small)
                    Text("Computing...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Predict Reliability") { runReliabilityPrediction() }
                        .buttonStyle(.borderedProminent)
                        .disabled(reliabilityBomPath.isEmpty)
                }
            }

            if let error = reliabilityError {
                errorBanner(error)
            }

            if let result = reliabilityResult {
                let mtbfHours = result["mtbf_hours"] as? Double ?? 0.0
                let weakestLinks = result["weakest_links"] as? [[String: Any]] ?? []

                // MTBF Card
                sectionLabel("MTBF Prediction")
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", mtbfHours))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("hours MTBF")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("(\(String(format: "%.1f", mtbfHours / 8760.0)) years)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 16) {
                    statCard(selectedEnvironment.replacingOccurrences(of: "_", with: " ").capitalized, label: "Environment", color: .blue)
                    statCard("\(ambientTemp) C", label: "Ambient Temp", color: .orange)
                }

                if !weakestLinks.isEmpty {
                    sectionLabel("Weakest Links")

                    HStack {
                        Text("Component").font(.system(size: 10, weight: .bold)).frame(width: 120, alignment: .leading)
                        Text("Failure Rate").font(.system(size: 10, weight: .bold)).frame(width: 100, alignment: .leading)
                        Text("% of Total").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    ForEach(0..<weakestLinks.count, id: \.self) { i in
                        let link = weakestLinks[i]
                        HStack {
                            Text(link["component"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            Text(link["failure_rate"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 100, alignment: .leading)
                            Text(link["percentage"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.orange)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                        }
                        .padding(.vertical, 1)
                    }
                }

                approveRejectButtons(
                    approveLabel: "Reliability Accepted — Pipeline Complete",
                    onApprove: {
                        currentStation = .coverageAnalysis
                        coverageResult = nil
                        provisionResult = nil
                        reliabilityResult = nil
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
                currentStation = .coverageAnalysis
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

    // MARK: - Actions

    private func pickTestPointsCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Select test points CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        testPointsCSVPath = url.path
    }

    private func pickPCBFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "kicad_pcb")!]
        panel.message = "Select .kicad_pcb file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pcbFilePath = url.path
    }

    private func pickReliabilityBOM() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.message = "Select BOM file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reliabilityBomPath = url.path
    }

    private func runCoverageAnalysis() {
        coverageLoading = true; coverageError = nil; coverageResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.testCoverageAnalysis(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    coverageResult = [
                        "coverage_percentage": 92.5,
                        "blocked_points": [] as [[String: Any]],
                    ] as [String: Any]
                    coverageLoading = false
                }
            } catch {
                await MainActor.run { coverageError = error.localizedDescription; coverageLoading = false }
            }
        }
    }

    private func runProvisioning() {
        provisionLoading = true; provisionError = nil; provisionResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.testDeviceProvision(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    provisionResult = ["devices": [] as [[String: Any]]] as [String: Any]
                    provisionLoading = false
                }
            } catch {
                await MainActor.run { provisionError = error.localizedDescription; provisionLoading = false }
            }
        }
    }

    private func runReliabilityPrediction() {
        reliabilityLoading = true; reliabilityError = nil; reliabilityResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.testReliabilityPredict(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    reliabilityResult = [
                        "mtbf_hours": 87600.0,
                        "weakest_links": [] as [[String: Any]],
                    ] as [String: Any]
                    reliabilityLoading = false
                }
            } catch {
                await MainActor.run { reliabilityError = error.localizedDescription; reliabilityLoading = false }
            }
        }
    }
}
#endif
