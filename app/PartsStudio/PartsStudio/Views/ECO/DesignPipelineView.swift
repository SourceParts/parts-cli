#if os(macOS)
import SwiftUI
import AppKit

/// Design Pipeline: Schematic review, impedance calculation, and thermal analysis.
struct DesignPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .schematicReview

    // Station 1: Schematic Review
    @State private var schematicPath: String = ""
    @State private var schematicResult: [String: Any]?
    @State private var schematicLoading = false
    @State private var schematicError: String?

    // Station 2: Impedance Calculate
    @State private var traceWidth: String = ""
    @State private var spacing: String = ""
    @State private var dielectricConstant: String = ""
    @State private var dielectricHeight: String = ""
    @State private var copperWeight: String = ""
    @State private var impedanceType: String = "microstrip"
    @State private var impedanceResult: [String: Any]?
    @State private var impedanceLoading = false

    // Station 3: Thermal Analysis
    @State private var thermalBomPath: String = ""
    @State private var ambientTemp: String = ""
    @State private var thermalResult: [String: Any]?
    @State private var thermalLoading = false

    enum Station: Int, CaseIterable {
        case schematicReview = 1
        case impedanceCalculate = 2
        case thermalAnalysis = 3

        var title: String {
            switch self {
            case .schematicReview: return "Schematic Review"
            case .impedanceCalculate: return "Impedance Calculate"
            case .thermalAnalysis: return "Thermal Analysis"
            }
        }

        var icon: String {
            switch self {
            case .schematicReview: return "doc.text.magnifyingglass"
            case .impedanceCalculate: return "waveform.path"
            case .thermalAnalysis: return "thermometer"
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
            Image(systemName: "ruler")
                .foregroundStyle(Color.accentColor)
            Text("Design Pipeline")
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
        case .schematicReview: schematicReviewStation
        case .impedanceCalculate: impedanceCalculateStation
        case .thermalAnalysis: thermalAnalysisStation
        }
    }

    // MARK: - Station 1: Schematic Review

    private var schematicReviewStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Schematic Review", description: "Upload .kicad_sch file for automated design review", icon: "doc.text.magnifyingglass")

            filePickerRow(label: "Schematic File:", path: $schematicPath, extensions: ["kicad_sch"])

            HStack {
                Spacer()
                if schematicLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run Review") { runSchematicReview() }
                        .buttonStyle(.borderedProminent)
                        .disabled(schematicPath.isEmpty)
                }
            }

            if let error = schematicError {
                errorBanner(error)
            }

            if let result = schematicResult {
                let score = result["score"] as? Int ?? 0
                let findings = result["findings"] as? [[String: Any]] ?? []

                HStack(spacing: 16) {
                    statCard("\(score)/100", label: "Score", color: score >= 80 ? .green : score >= 60 ? .orange : .red)
                    statCard("\(findings.count)", label: "Findings", color: findings.isEmpty ? .green : .orange)
                }

                // Score gauge
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Design Score")
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(score >= 80 ? Color.green : score >= 60 ? Color.orange : Color.red)
                                .frame(width: geometry.size.width * CGFloat(score) / 100.0, height: 8)
                        }
                    }
                    .frame(height: 8)
                }

                if !findings.isEmpty {
                    sectionLabel("Findings (\(findings.count))")
                    ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                        HStack(spacing: 8) {
                            let severity = finding["severity"] as? String ?? "info"
                            Text(severity.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    severity == "error" ? Color.red.opacity(0.15) :
                                    severity == "warning" ? Color.orange.opacity(0.15) :
                                    Color.blue.opacity(0.15)
                                )
                                .foregroundStyle(
                                    severity == "error" ? .red :
                                    severity == "warning" ? .orange :
                                    .blue
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(finding["title"] as? String ?? "—")
                                    .font(.system(size: 11, weight: .medium))
                                Text(finding["detail"] as? String ?? "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(finding["reference"] as? String ?? "")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                approveRejectButtons(
                    approveLabel: "Proceed to Impedance",
                    onApprove: { currentStation = .impedanceCalculate }
                )
            }
        }
    }

    // MARK: - Station 2: Impedance Calculate

    private var impedanceCalculateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Impedance Calculate", description: "Calculate controlled impedance for PCB stackup", icon: "waveform.path")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Type:").font(.caption).fontWeight(.medium)
                    Picker("", selection: $impedanceType) {
                        Text("Microstrip").tag("microstrip")
                        Text("Stripline").tag("stripline")
                        Text("Diff Pair").tag("differential")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Trace Width (mil)").font(.caption2).foregroundStyle(.secondary)
                        TextField("e.g. 5.0", text: $traceWidth)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    VStack(alignment: .leading) {
                        Text("Spacing (mil)").font(.caption2).foregroundStyle(.secondary)
                        TextField("e.g. 5.0", text: $spacing)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Dk (Er)").font(.caption2).foregroundStyle(.secondary)
                        TextField("e.g. 4.3", text: $dielectricConstant)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    VStack(alignment: .leading) {
                        Text("Height (mil)").font(.caption2).foregroundStyle(.secondary)
                        TextField("e.g. 4.0", text: $dielectricHeight)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    VStack(alignment: .leading) {
                        Text("Cu Weight (oz)").font(.caption2).foregroundStyle(.secondary)
                        TextField("e.g. 1.0", text: $copperWeight)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                }
            }

            HStack {
                Spacer()
                if impedanceLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Calculate") { runImpedance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(traceWidth.isEmpty || dielectricConstant.isEmpty || dielectricHeight.isEmpty || copperWeight.isEmpty)
                }
            }

            if let result = impedanceResult {
                let impedance = result["impedance_ohms"] as? Double ?? 0
                let delay = result["delay_ps_per_inch"] as? Double ?? 0
                let loss = result["loss_db_per_inch"] as? Double ?? 0

                sectionLabel("Impedance Result")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        statCard(String(format: "%.1f\u{03A9}", impedance), label: "Impedance", color: .blue)
                        statCard(String(format: "%.1f ps/in", delay), label: "Delay", color: .purple)
                        statCard(String(format: "%.3f dB/in", loss), label: "Loss", color: .orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("Type:").font(.caption).fontWeight(.medium); Spacer(); Text(impedanceType).font(.system(size: 11, design: .monospaced)) }
                        HStack { Text("Trace Width:").font(.caption).fontWeight(.medium); Spacer(); Text("\(traceWidth) mil").font(.system(size: 11, design: .monospaced)) }
                        HStack { Text("Dk:").font(.caption).fontWeight(.medium); Spacer(); Text(dielectricConstant).font(.system(size: 11, design: .monospaced)) }
                        HStack { Text("Height:").font(.caption).fontWeight(.medium); Spacer(); Text("\(dielectricHeight) mil").font(.system(size: 11, design: .monospaced)) }
                        HStack { Text("Copper:").font(.caption).fontWeight(.medium); Spacer(); Text("\(copperWeight) oz").font(.system(size: 11, design: .monospaced)) }
                    }
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                approveRejectButtons(
                    approveLabel: "Proceed to Thermal Analysis",
                    onApprove: { currentStation = .thermalAnalysis }
                )
            }
        }
    }

    // MARK: - Station 3: Thermal Analysis

    private var thermalAnalysisStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Thermal Analysis", description: "Analyze power dissipation and thermal hot spots", icon: "thermometer")

            VStack(alignment: .leading, spacing: 8) {
                filePickerRow(label: "BOM File:", path: $thermalBomPath, extensions: ["csv", "xlsx"])

                HStack {
                    Text("Ambient Temp (\u{00B0}C):").font(.caption).fontWeight(.medium)
                    TextField("e.g. 25", text: $ambientTemp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            HStack {
                Spacer()
                if thermalLoading {
                    ProgressView().controlSize(.small)
                    Text("Analyzing...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Run Thermal Analysis") { runThermalAnalysis() }
                        .buttonStyle(.borderedProminent)
                        .disabled(thermalBomPath.isEmpty || ambientTemp.isEmpty)
                }
            }

            if let result = thermalResult {
                let totalPower = result["total_power_w"] as? Double ?? 0
                let hotSpots = result["hot_spots"] as? [[String: Any]] ?? []
                let maxTemp = result["max_temp_c"] as? Double ?? 0

                HStack(spacing: 16) {
                    statCard(String(format: "%.2f W", totalPower), label: "Total Power", color: .orange)
                    statCard(String(format: "%.0f\u{00B0}C", maxTemp), label: "Max Temp", color: maxTemp > 85 ? .red : maxTemp > 60 ? .orange : .green)
                }

                if !hotSpots.isEmpty {
                    sectionLabel("Hot Spots (\(hotSpots.count))")
                    VStack(spacing: 0) {
                        HStack {
                            Text("Component").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                            Text("Power (W)").font(.caption2).fontWeight(.bold).frame(width: 80)
                            Text("Tj (\u{00B0}C)").font(.caption2).fontWeight(.bold).frame(width: 70)
                            Text("Tj max").font(.caption2).fontWeight(.bold).frame(width: 70)
                            Text("Margin").font(.caption2).fontWeight(.bold).frame(width: 70)
                            Spacer()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.1))

                        ForEach(Array(hotSpots.enumerated()), id: \.offset) { _, spot in
                            let tj = spot["tj_c"] as? Double ?? 0
                            let tjMax = spot["tj_max_c"] as? Double ?? 125
                            let margin = tjMax - tj
                            HStack {
                                Text(spot["component"] as? String ?? "—")
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                                Text(String(format: "%.3f", spot["power_w"] as? Double ?? 0))
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 80)
                                Text(String(format: "%.0f", tj))
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 70)
                                Text(String(format: "%.0f", tjMax))
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 70)
                                Text(String(format: "%.0f\u{00B0}C", margin))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(margin < 10 ? .red : margin < 30 ? .orange : .green)
                                    .frame(width: 70)
                                Spacer()
                            }
                            .padding(.vertical, 2).padding(.horizontal, 8)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Button("Start Over") {
                        currentStation = .schematicReview
                        schematicResult = nil; impedanceResult = nil; thermalResult = nil
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Design Review Complete") {}
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
                currentStation = .schematicReview
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

    @ViewBuilder
    private func filePickerRow(label: String, path: Binding<String>, extensions: [String]) -> some View {
        HStack {
            Text(label).font(.caption).fontWeight(.medium)
            if path.wrappedValue.isEmpty {
                Button("Select...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
                    panel.message = "Select file"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path.wrappedValue = url.path
                }
                .buttonStyle(.bordered)
            } else {
                Text(URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
                    panel.message = "Select file"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path.wrappedValue = url.path
                }) {
                    Image(systemName: "folder").font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stationColor(_ station: Station) -> Color {
        if station.rawValue < currentStation.rawValue { return .green }
        if station == currentStation { return .blue }
        return .gray
    }

    // MARK: - Actions

    private func runSchematicReview() {
        schematicLoading = true; schematicError = nil; schematicResult = nil
        Task {
            do {
                let _ = schematicPath
                // Placeholder: let result = try await PartsAPIClient.shared.designSchematicReview(...)
                let result: [String: Any] = [:]
                await MainActor.run { schematicResult = result; schematicLoading = false }
            } catch {
                await MainActor.run { schematicError = error.localizedDescription; schematicLoading = false }
            }
        }
    }

    private func runImpedance() {
        impedanceLoading = true; impedanceResult = nil
        Task {
            do {
                let _ = traceWidth; let _ = spacing; let _ = dielectricConstant
                let _ = dielectricHeight; let _ = copperWeight; let _ = impedanceType
                // Placeholder: let result = try await PartsAPIClient.shared.designImpedance(...)
                let result: [String: Any] = [:]
                await MainActor.run { impedanceResult = result; impedanceLoading = false }
            } catch {
                await MainActor.run { impedanceLoading = false }
            }
        }
    }

    private func runThermalAnalysis() {
        thermalLoading = true; thermalResult = nil
        Task {
            do {
                let _ = thermalBomPath; let _ = ambientTemp
                // Placeholder: let result = try await PartsAPIClient.shared.designThermalAnalysis(...)
                let result: [String: Any] = [:]
                await MainActor.run { thermalResult = result; thermalLoading = false }
            } catch {
                await MainActor.run { thermalLoading = false }
            }
        }
    }
}
#endif
