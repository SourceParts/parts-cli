#if os(macOS)
import SwiftUI
import AppKit

/// Assembly Pipeline: PCB assembly readiness through functional test.
struct AssemblyPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .readiness

    // Station 1: Readiness
    @State private var bomPath: String = ""
    @State private var gerberPath: String = ""
    @State private var positionPath: String = ""
    @State private var readinessResult: [String: Any]?
    @State private var readinessLoading = false
    @State private var readinessError: String?

    // Station 2: Feeder Setup
    @State private var machineType: String = "neoden"
    @State private var feederResult: [String: Any]?
    @State private var feederLoading = false

    // Station 3: Reflow Profile
    @State private var reflowResult: [String: Any]?
    @State private var reflowLoading = false

    // Station 4: AOI Inspect
    @State private var photoPath: String = ""
    @State private var aoiResult: [String: Any]?
    @State private var aoiLoading = false

    // Station 5: Functional Test
    @State private var testCSVPath: String = ""
    @State private var testResult: [String: Any]?
    @State private var testLoading = false

    enum Station: Int, CaseIterable {
        case readiness = 1
        case feederSetup = 2
        case reflowProfile = 3
        case aoiInspect = 4
        case functionalTest = 5

        var title: String {
            switch self {
            case .readiness: return "Readiness"
            case .feederSetup: return "Feeder Setup"
            case .reflowProfile: return "Reflow Profile"
            case .aoiInspect: return "AOI Inspect"
            case .functionalTest: return "Functional Test"
            }
        }

        var icon: String {
            switch self {
            case .readiness: return "checklist"
            case .feederSetup: return "tray.2"
            case .reflowProfile: return "flame"
            case .aoiInspect: return "eye"
            case .functionalTest: return "waveform.path.ecg"
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
            Image(systemName: "hammer")
                .foregroundStyle(Color.accentColor)
            Text("Assembly Pipeline")
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
        case .readiness: readinessStation
        case .feederSetup: feederSetupStation
        case .reflowProfile: reflowProfileStation
        case .aoiInspect: aoiInspectStation
        case .functionalTest: functionalTestStation
        }
    }

    // MARK: - Station 1: Readiness

    private var readinessStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Readiness Check", description: "Upload BOM, Gerbers, and position file for assembly readiness", icon: "checklist")

            VStack(alignment: .leading, spacing: 8) {
                filePickerRow(label: "BOM File:", path: $bomPath, extensions: ["csv", "xlsx"])
                filePickerRow(label: "Gerber ZIP:", path: $gerberPath, extensions: ["zip"])
                filePickerRow(label: "Position CSV:", path: $positionPath, extensions: ["csv"])
            }

            HStack {
                Spacer()
                if readinessLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Readiness") { runReadiness() }
                        .buttonStyle(.borderedProminent)
                        .disabled(bomPath.isEmpty || gerberPath.isEmpty || positionPath.isEmpty)
                }
            }

            if let error = readinessError {
                errorBanner(error)
            }

            if let result = readinessResult,
               let checks = result["checks"] as? [[String: Any]] {
                sectionLabel("Readiness Checklist (\(checks.count) items)")
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    HStack {
                        let pass = check["pass"] as? Bool ?? false
                        Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(pass ? .green : .red)
                            .font(.system(size: 12))
                        Text(check["name"] as? String ?? "—")
                            .font(.system(size: 11))
                        Spacer()
                        Text(pass ? "PASS" : "FAIL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(pass ? .green : .red)
                    }
                    .padding(.vertical, 2)
                }

                approveRejectButtons(
                    approveLabel: "Proceed to Feeder Setup",
                    onApprove: { currentStation = .feederSetup }
                )
            }
        }
    }

    // MARK: - Station 2: Feeder Setup

    private var feederSetupStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Feeder Setup", description: "Select machine and generate feeder map", icon: "tray.2")

            HStack {
                Text("Machine:").font(.caption).fontWeight(.medium)
                Picker("", selection: $machineType) {
                    Text("Neoden").tag("neoden")
                    Text("Juki").tag("juki")
                    Text("Samsung").tag("samsung")
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                if feederLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate Feeder Map") { runFeederSetup() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let result = feederResult,
               let feeders = result["feeder_map"] as? [[String: Any]] {
                sectionLabel("Feeder Map (\(feeders.count) slots)")
                VStack(spacing: 0) {
                    HStack {
                        Text("Slot").font(.caption2).fontWeight(.bold).frame(width: 50, alignment: .leading)
                        Text("Part").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                        Text("Package").font(.caption2).fontWeight(.bold).frame(width: 80, alignment: .leading)
                        Text("Qty").font(.caption2).fontWeight(.bold).frame(width: 60)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(Array(feeders.enumerated()), id: \.offset) { _, feeder in
                        HStack {
                            Text("\(feeder["slot"] as? Int ?? 0)")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 50, alignment: .leading)
                            Text(feeder["part"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                            Text(feeder["package"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 80, alignment: .leading)
                            Text("\(feeder["qty"] as? Int ?? 0)")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 60)
                            Spacer()
                        }
                        .padding(.vertical, 2).padding(.horizontal, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                approveRejectButtons(
                    approveLabel: "Proceed to Reflow Profile",
                    onApprove: { currentStation = .reflowProfile }
                )
            }
        }
    }

    // MARK: - Station 3: Reflow Profile

    private var reflowProfileStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Reflow Profile", description: "Review thermal constraints and recommended profile", icon: "flame")

            HStack {
                Spacer()
                if reflowLoading {
                    ProgressView().controlSize(.small)
                    Text("Analyzing...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Analyze Thermal Profile") { runReflowProfile() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let result = reflowResult {
                let profile = result["profile"] as? String ?? "—"
                let peakTemp = result["peak_temp"] as? Double ?? 0
                let mslLevels = result["msl_levels"] as? [[String: Any]] ?? []
                let constraints = result["thermal_constraints"] as? [[String: Any]] ?? []

                HStack(spacing: 16) {
                    statCard(profile, label: "Profile", color: .orange)
                    statCard(String(format: "%.0f\u{00B0}C", peakTemp), label: "Peak Temp", color: .red)
                }

                if !constraints.isEmpty {
                    sectionLabel("Thermal Constraints")
                    ForEach(Array(constraints.enumerated()), id: \.offset) { _, c in
                        HStack {
                            Text(c["component"] as? String ?? "—")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text("max \(c["max_temp"] as? Int ?? 0)\u{00B0}C")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !mslLevels.isEmpty {
                    sectionLabel("MSL Levels")
                    ForEach(Array(mslLevels.enumerated()), id: \.offset) { _, m in
                        HStack {
                            Text(m["component"] as? String ?? "—")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            let level = m["msl"] as? Int ?? 1
                            Text("MSL \(level)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(level >= 4 ? .red : level >= 3 ? .orange : .green)
                        }
                        .padding(.vertical, 2)
                    }
                }

                approveRejectButtons(
                    approveLabel: "Profile Accepted — Proceed to AOI",
                    onApprove: { currentStation = .aoiInspect }
                )
            }
        }
    }

    // MARK: - Station 4: AOI Inspect

    private var aoiInspectStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("AOI Inspection", description: "Upload board photo for automated optical inspection", icon: "eye")

            filePickerRow(label: "Board Photo:", path: $photoPath, extensions: ["png", "jpg", "jpeg", "tiff"])

            HStack {
                Spacer()
                if aoiLoading {
                    ProgressView().controlSize(.small)
                    Text("Inspecting...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Run AOI") { runAOI() }
                        .buttonStyle(.borderedProminent)
                        .disabled(photoPath.isEmpty)
                }
            }

            if let result = aoiResult,
               let defects = result["defects"] as? [[String: Any]] {
                let totalDefects = defects.count
                statCard("\(totalDefects)", label: "Defects Found", color: totalDefects == 0 ? .green : .red)

                if !defects.isEmpty {
                    sectionLabel("Defect List")
                    ForEach(Array(defects.enumerated()), id: \.offset) { _, defect in
                        HStack {
                            let severity = defect["severity"] as? String ?? "low"
                            Image(systemName: severity == "critical" ? "exclamationmark.octagon.fill" : severity == "major" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .foregroundStyle(severity == "critical" ? .red : severity == "major" ? .orange : .blue)
                                .font(.system(size: 12))
                            Text(defect["description"] as? String ?? "—")
                                .font(.system(size: 11))
                            Spacer()
                            Text(defect["location"] as? String ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(severity.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(severity == "critical" ? Color.red.opacity(0.15) : severity == "major" ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                                .foregroundStyle(severity == "critical" ? .red : severity == "major" ? .orange : .blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.vertical, 2)
                    }
                }

                approveRejectButtons(
                    approveLabel: "AOI Passed — Proceed to Functional Test",
                    onApprove: { currentStation = .functionalTest }
                )
            }
        }
    }

    // MARK: - Station 5: Functional Test

    private var functionalTestStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Functional Test", description: "Upload test results and review yield metrics", icon: "waveform.path.ecg")

            filePickerRow(label: "Test Results CSV:", path: $testCSVPath, extensions: ["csv"])

            HStack {
                Spacer()
                if testLoading {
                    ProgressView().controlSize(.small)
                    Text("Analyzing...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Analyze Results") { runFunctionalTest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(testCSVPath.isEmpty)
                }
            }

            if let result = testResult {
                let yieldPct = result["yield_pct"] as? Double ?? 0
                let totalUnits = result["total_units"] as? Int ?? 0
                let passCount = result["pass_count"] as? Int ?? 0
                let failCount = result["fail_count"] as? Int ?? 0
                let outliers = result["outliers"] as? [[String: Any]] ?? []

                HStack(spacing: 16) {
                    statCard(String(format: "%.1f%%", yieldPct), label: "Yield", color: yieldPct >= 95 ? .green : yieldPct >= 85 ? .orange : .red)
                    statCard("\(totalUnits)", label: "Total Units", color: .blue)
                    statCard("\(passCount)", label: "Pass", color: .green)
                    statCard("\(failCount)", label: "Fail", color: .red)
                }

                if !outliers.isEmpty {
                    sectionLabel("Outliers (\(outliers.count))")
                    VStack(spacing: 0) {
                        HStack {
                            Text("Unit").font(.caption2).fontWeight(.bold).frame(width: 80, alignment: .leading)
                            Text("Test").font(.caption2).fontWeight(.bold).frame(width: 120, alignment: .leading)
                            Text("Value").font(.caption2).fontWeight(.bold).frame(width: 80)
                            Text("Limit").font(.caption2).fontWeight(.bold).frame(width: 80)
                            Spacer()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.1))

                        ForEach(Array(outliers.enumerated()), id: \.offset) { _, outlier in
                            HStack {
                                Text(outlier["unit_id"] as? String ?? "—")
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 80, alignment: .leading)
                                Text(outlier["test_name"] as? String ?? "—")
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 120, alignment: .leading)
                                Text(outlier["value"] as? String ?? "—")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.red).frame(width: 80)
                                Text(outlier["limit"] as? String ?? "—")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 80)
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
                        currentStation = .readiness
                        readinessResult = nil; feederResult = nil; reflowResult = nil
                        aoiResult = nil; testResult = nil
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Assembly Complete") {}
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
                currentStation = .readiness
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

    private func runReadiness() {
        readinessLoading = true; readinessError = nil; readinessResult = nil
        Task {
            do {
                let _ = bomPath; let _ = gerberPath; let _ = positionPath
                // Placeholder: let result = try await PartsAPIClient.shared.assemblyReadiness(...)
                let result: [String: Any] = [:]
                await MainActor.run { readinessResult = result; readinessLoading = false }
            } catch {
                await MainActor.run { readinessError = error.localizedDescription; readinessLoading = false }
            }
        }
    }

    private func runFeederSetup() {
        feederLoading = true; feederResult = nil
        Task {
            do {
                let _ = machineType
                // Placeholder: let result = try await PartsAPIClient.shared.assemblyFeederMap(...)
                let result: [String: Any] = [:]
                await MainActor.run { feederResult = result; feederLoading = false }
            } catch {
                await MainActor.run { feederLoading = false }
            }
        }
    }

    private func runReflowProfile() {
        reflowLoading = true; reflowResult = nil
        Task {
            do {
                // Placeholder: let result = try await PartsAPIClient.shared.assemblyReflowProfile(...)
                let result: [String: Any] = [:]
                await MainActor.run { reflowResult = result; reflowLoading = false }
            } catch {
                await MainActor.run { reflowLoading = false }
            }
        }
    }

    private func runAOI() {
        aoiLoading = true; aoiResult = nil
        Task {
            do {
                let _ = photoPath
                // Placeholder: let result = try await PartsAPIClient.shared.assemblyAOI(...)
                let result: [String: Any] = [:]
                await MainActor.run { aoiResult = result; aoiLoading = false }
            } catch {
                await MainActor.run { aoiLoading = false }
            }
        }
    }

    private func runFunctionalTest() {
        testLoading = true; testResult = nil
        Task {
            do {
                let _ = testCSVPath
                // Placeholder: let result = try await PartsAPIClient.shared.assemblyFunctionalTest(...)
                let result: [String: Any] = [:]
                await MainActor.run { testResult = result; testLoading = false }
            } catch {
                await MainActor.run { testLoading = false }
            }
        }
    }
}
#endif
