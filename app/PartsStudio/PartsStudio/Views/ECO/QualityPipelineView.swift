#if os(macOS)
import SwiftUI
import AppKit

/// Quality Pipeline: IQC/X-ray/FAI/Compliance wizard with operator-approved gates.
struct QualityPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .iqcInspect

    // Station 1: IQC Inspect
    @State private var iqcPhotoPaths: [String] = []
    @State private var partNumber: String = ""
    @State private var expectedQuantity: String = ""
    @State private var iqcChecklist: [(name: String, passed: Bool)] = [
        ("Label matches PO", false),
        ("Quantity correct", false),
        ("No visible damage", false),
        ("Moisture indicator OK", false),
        ("Date code within spec", false),
    ]
    @State private var iqcLoading = false
    @State private var iqcResult: [String: Any]?
    @State private var iqcError: String?

    // Station 2: X-ray Analyze
    @State private var xrayImagePath: String = ""
    @State private var xrayLoading = false
    @State private var xrayResult: [String: Any]?
    @State private var xrayError: String?

    // Station 3: FAI Inspect
    @State private var boardPhotoPath: String = ""
    @State private var bomFilePath: String = ""
    @State private var faiLoading = false
    @State private var faiResult: [String: Any]?
    @State private var faiError: String?

    // Station 4: Compliance Check
    @State private var complianceBomPath: String = ""
    @State private var marketsEU = false
    @State private var marketsUS = false
    @State private var marketsCN = false
    @State private var complianceLoading = false
    @State private var complianceResult: [String: Any]?
    @State private var complianceError: String?

    enum Station: Int, CaseIterable {
        case iqcInspect = 1
        case xrayAnalyze = 2
        case faiInspect = 3
        case complianceCheck = 4

        var title: String {
            switch self {
            case .iqcInspect: return "IQC Inspect"
            case .xrayAnalyze: return "X-ray Analyze"
            case .faiInspect: return "FAI Inspect"
            case .complianceCheck: return "Compliance Check"
            }
        }

        var icon: String {
            switch self {
            case .iqcInspect: return "eye.circle"
            case .xrayAnalyze: return "rays"
            case .faiInspect: return "checklist"
            case .complianceCheck: return "checkmark.seal"
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
            Image(systemName: "shield.checkered")
                .foregroundStyle(Color.accentColor)
            Text("Quality Pipeline")
                .font(.headline)
            Divider().frame(height: 20)

            Text("Station \(currentStation.rawValue)/4")
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
        case .iqcInspect: iqcInspectStation
        case .xrayAnalyze: xrayAnalyzeStation
        case .faiInspect: faiInspectStation
        case .complianceCheck: complianceCheckStation
        }
    }

    // MARK: - Station 1: IQC Inspect

    private var iqcInspectStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("IQC Inspect", description: "Incoming quality control — verify received parts", icon: "eye.circle")

            HStack(spacing: 12) {
                TextField("Part number", text: $partNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                TextField("Expected quantity", text: $expectedQuantity)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                Button("Add Photos...") { pickIQCPhotos() }
                    .buttonStyle(.bordered)
            }

            if !iqcPhotoPaths.isEmpty {
                sectionLabel("Uploaded Photos (\(iqcPhotoPaths.count))")
                ForEach(iqcPhotoPaths, id: \.self) { path in
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            sectionLabel("Inspection Checklist")
            ForEach(0..<iqcChecklist.count, id: \.self) { i in
                HStack {
                    Button(action: { iqcChecklist[i].passed.toggle() }) {
                        Image(systemName: iqcChecklist[i].passed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(iqcChecklist[i].passed ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                    Text(iqcChecklist[i].name)
                        .font(.system(size: 12))
                    Spacer()
                    Text(iqcChecklist[i].passed ? "PASS" : "FAIL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(iqcChecklist[i].passed ? .green : .red)
                }
                .padding(.vertical, 2)
            }

            if let error = iqcError {
                errorBanner(error)
            }

            HStack {
                if iqcLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run Inspection") { runIQCInspect() }
                        .buttonStyle(.borderedProminent)
                        .disabled(partNumber.isEmpty)
                }
            }

            if iqcResult != nil {
                let passCount = iqcChecklist.filter { $0.passed }.count
                HStack(spacing: 16) {
                    statCard("\(passCount)/\(iqcChecklist.count)", label: "Checks Passed", color: passCount == iqcChecklist.count ? .green : .orange)
                    statCard(partNumber, label: "Part Number", color: .blue)
                }

                approveRejectButtons(
                    approveLabel: "IQC Passed — Proceed to X-ray",
                    onApprove: { currentStation = .xrayAnalyze }
                )
            }
        }
    }

    // MARK: - Station 2: X-ray Analyze

    private var xrayAnalyzeStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("X-ray Analyze", description: "Analyze solder joints via X-ray imaging", icon: "rays")

            HStack {
                if xrayImagePath.isEmpty {
                    Button("Select X-ray Image...") { pickXrayImage() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(URL(fileURLWithPath: xrayImagePath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickXrayImage() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if xrayLoading {
                    ProgressView().controlSize(.small)
                } else if !xrayImagePath.isEmpty {
                    Button("Analyze") { runXrayAnalyze() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let error = xrayError {
                errorBanner(error)
            }

            if let result = xrayResult {
                let voidPct = result["void_percentage"] as? Double ?? 0.0
                let defects = result["defects"] as? [[String: Any]] ?? []

                sectionLabel("Void Percentage")
                gaugeView(value: voidPct, maxValue: 100.0, label: "\(String(format: "%.1f", voidPct))%", color: voidPct < 25 ? .green : (voidPct < 50 ? .orange : .red))

                if !defects.isEmpty {
                    sectionLabel("Defects (\(defects.count))")
                    ForEach(0..<defects.count, id: \.self) { i in
                        let defect = defects[i]
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(defect["type"] as? String ?? "Unknown")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text(defect["location"] as? String ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(defect["severity"] as? String ?? "")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 2)
                    }
                }

                approveRejectButtons(
                    approveLabel: "X-ray Passed — Proceed to FAI",
                    onApprove: { currentStation = .faiInspect }
                )
            }
        }
    }

    // MARK: - Station 3: FAI Inspect

    private var faiInspectStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("FAI Inspect", description: "First Article Inspection — verify component placement", icon: "checklist")

            HStack(spacing: 12) {
                if boardPhotoPath.isEmpty {
                    Button("Select Board Photo...") { pickBoardPhoto() }
                        .buttonStyle(.bordered)
                } else {
                    Text(URL(fileURLWithPath: boardPhotoPath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickBoardPhoto() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                if bomFilePath.isEmpty {
                    Button("Select BOM...") { pickBOMFile() }
                        .buttonStyle(.bordered)
                } else {
                    Text(URL(fileURLWithPath: bomFilePath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickBOMFile() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                if faiLoading {
                    ProgressView().controlSize(.small)
                } else if !boardPhotoPath.isEmpty && !bomFilePath.isEmpty {
                    Button("Run FAI") { runFAIInspect() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let error = faiError {
                errorBanner(error)
            }

            if let result = faiResult,
               let components = result["components"] as? [[String: Any]] {
                sectionLabel("Component Status (\(components.count))")

                // Table header
                HStack {
                    Text("Reference").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                    Text("Value").font(.system(size: 10, weight: .bold)).frame(width: 100, alignment: .leading)
                    Text("Status").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                    Spacer()
                }
                .padding(.vertical, 4)

                ForEach(0..<components.count, id: \.self) { i in
                    let comp = components[i]
                    let status = comp["status"] as? String ?? "unknown"
                    HStack {
                        Text(comp["reference"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        Text(comp["value"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                        Text(status.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(faiStatusColor(status))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }

                let presentCount = components.filter { ($0["status"] as? String) == "present" }.count
                HStack(spacing: 16) {
                    statCard("\(presentCount)", label: "Present", color: .green)
                    statCard("\(components.count - presentCount)", label: "Issues", color: presentCount == components.count ? .green : .red)
                }

                approveRejectButtons(
                    approveLabel: "FAI Passed — Proceed to Compliance",
                    onApprove: { currentStation = .complianceCheck }
                )
            }
        }
    }

    // MARK: - Station 4: Compliance Check

    private var complianceCheckStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Compliance Check", description: "Verify regulatory compliance per target market", icon: "checkmark.seal")

            HStack(spacing: 12) {
                if complianceBomPath.isEmpty {
                    Button("Select BOM...") { pickComplianceBOM() }
                        .buttonStyle(.bordered)
                } else {
                    Text(URL(fileURLWithPath: complianceBomPath).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(action: { pickComplianceBOM() }) {
                        Image(systemName: "folder").font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionLabel("Target Markets")
            HStack(spacing: 16) {
                Toggle("EU (CE/RoHS/REACH)", isOn: $marketsEU)
                Toggle("US (FCC/UL)", isOn: $marketsUS)
                Toggle("CN (CCC/GB)", isOn: $marketsCN)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                if complianceLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run Compliance Check") { runComplianceCheck() }
                        .buttonStyle(.borderedProminent)
                        .disabled(complianceBomPath.isEmpty || (!marketsEU && !marketsUS && !marketsCN))
                }
            }

            if let error = complianceError {
                errorBanner(error)
            }

            if let result = complianceResult,
               let matrix = result["matrix"] as? [[String: Any]] {
                sectionLabel("Compliance Matrix")

                // Table header
                HStack {
                    Text("Regulation").font(.system(size: 10, weight: .bold)).frame(width: 120, alignment: .leading)
                    Text("Market").font(.system(size: 10, weight: .bold)).frame(width: 60, alignment: .leading)
                    Text("Status").font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                    Text("Notes").font(.system(size: 10, weight: .bold)).frame(minWidth: 100, alignment: .leading)
                    Spacer()
                }
                .padding(.vertical, 4)

                ForEach(0..<matrix.count, id: \.self) { i in
                    let row = matrix[i]
                    let status = row["status"] as? String ?? "unknown"
                    HStack {
                        Text(row["regulation"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                        Text(row["market"] as? String ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60, alignment: .leading)
                        Text(status.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(status == "pass" ? .green : (status == "warning" ? .orange : .red))
                            .frame(width: 80, alignment: .leading)
                        Text(row["notes"] as? String ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 100, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }

                let passCount = matrix.filter { ($0["status"] as? String) == "pass" }.count
                HStack(spacing: 16) {
                    statCard("\(passCount)/\(matrix.count)", label: "Regulations Passed", color: passCount == matrix.count ? .green : .orange)
                }

                approveRejectButtons(
                    approveLabel: "Compliance Approved — Pipeline Complete",
                    onApprove: {
                        // Reset wizard
                        currentStation = .iqcInspect
                        iqcResult = nil
                        xrayResult = nil
                        faiResult = nil
                        complianceResult = nil
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
                currentStation = .iqcInspect
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

    private func faiStatusColor(_ status: String) -> Color {
        switch status {
        case "present": return .green
        case "missing": return .red
        case "rotated": return .orange
        default: return .gray
        }
    }

    // MARK: - Actions

    private func pickIQCPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.message = "Select inspection photos"
        guard panel.runModal() == .OK else { return }
        iqcPhotoPaths = panel.urls.map { $0.path }
    }

    private func pickXrayImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Select X-ray image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        xrayImagePath = url.path
    }

    private func pickBoardPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Select board photo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        boardPhotoPath = url.path
    }

    private func pickBOMFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.message = "Select BOM file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bomFilePath = url.path
    }

    private func pickComplianceBOM() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.message = "Select BOM file for compliance check"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        complianceBomPath = url.path
    }

    private func runIQCInspect() {
        iqcLoading = true; iqcError = nil; iqcResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.qualityIQCInspect(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    iqcResult = ["status": "complete"]
                    iqcLoading = false
                }
            } catch {
                await MainActor.run { iqcError = error.localizedDescription; iqcLoading = false }
            }
        }
    }

    private func runXrayAnalyze() {
        xrayLoading = true; xrayError = nil; xrayResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.qualityXrayAnalyze(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    xrayResult = [
                        "void_percentage": 12.5,
                        "defects": [] as [[String: Any]],
                    ] as [String: Any]
                    xrayLoading = false
                }
            } catch {
                await MainActor.run { xrayError = error.localizedDescription; xrayLoading = false }
            }
        }
    }

    private func runFAIInspect() {
        faiLoading = true; faiError = nil; faiResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.qualityFAIInspect(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    faiResult = ["components": [] as [[String: Any]]] as [String: Any]
                    faiLoading = false
                }
            } catch {
                await MainActor.run { faiError = error.localizedDescription; faiLoading = false }
            }
        }
    }

    private func runComplianceCheck() {
        complianceLoading = true; complianceError = nil; complianceResult = nil
        Task {
            do {
                // Placeholder: await PartsAPIClient.shared.qualityComplianceCheck(...)
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    complianceResult = ["matrix": [] as [[String: Any]]] as [String: Any]
                    complianceLoading = false
                }
            } catch {
                await MainActor.run { complianceError = error.localizedDescription; complianceLoading = false }
            }
        }
    }
}
#endif
