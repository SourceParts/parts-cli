#if os(macOS)
import SwiftUI
import AppKit
import PDFKit

/// KiCad-Ctrl: AOI-style operator-approved PCB editing wizard.
/// Each station performs one step and waits for explicit approval before proceeding.
struct KiCadCtrlView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .analyze
    @State private var pcbPath: String = ""

    // Station 1: Analyze
    @State private var analyzeResult: [String: Any]?
    @State private var highlightPDFPath: String?
    @State private var analyzeLoading = false
    @State private var analyzeError: String?

    // Station 2: Propose
    @State private var proposeResult: [String: Any]?
    @State private var proposeLoading = false

    // Station 3: Execute
    @State private var executeResult: [String: Any]?
    @State private var diffText: String = ""
    @State private var executeLoading = false

    // Station 4: Manual reroute (no API call — just a gate)

    // Station 5: Validate
    @State private var drcResult: [String: Any]?
    @State private var validateLoading = false

    // Station 6: Export
    @State private var exportResult: [String: Any]?
    @State private var exportLoading = false

    @State private var netNames: [String] = []
    @State private var netInput: String = ""

    enum Station: Int, CaseIterable {
        case analyze = 1
        case propose = 2
        case execute = 3
        case reroute = 4
        case validate = 5
        case export_ = 6

        var title: String {
            switch self {
            case .analyze: return "Net Analysis"
            case .propose: return "Rip-Up Proposal"
            case .execute: return "Rip-Up Execution"
            case .reroute: return "Manual Reroute"
            case .validate: return "DRC Validation"
            case .export_: return "Gerber Export"
            }
        }

        var icon: String {
            switch self {
            case .analyze: return "magnifyingglass"
            case .propose: return "list.clipboard"
            case .execute: return "scissors"
            case .reroute: return "pencil.and.ruler"
            case .validate: return "checkmark.shield"
            case .export_: return "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stationContent
                    }
                    .padding(24)
                }
                .frame(minWidth: 500)

                // Station sidebar
                stationSidebar
                    .frame(width: 220)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(Color.accentColor)
            Text("KiCad Control")
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

            // PCB file selector
            if pcbPath.isEmpty {
                Button("Select PCB...") { pickPCBFile() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(URL(fileURLWithPath: pcbPath).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: { pickPCBFile() }) {
                    Image(systemName: "folder").font(.caption)
                }
                .buttonStyle(.plain)
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
        case .analyze: analyzeStation
        case .propose: proposeStation
        case .execute: executeStation
        case .reroute: rerouteStation
        case .validate: validateStation
        case .export_: exportStation
        }
    }

    // MARK: - Station 1: Analyze

    private var analyzeStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Net Analysis", description: "Identify affected nets in the PCB design", icon: "magnifyingglass")

            if pcbPath.isEmpty {
                emptyState("Select a .kicad_pcb file to begin")
            } else {
                HStack {
                    TextField("Net names (comma-separated) or leave blank for all", text: $netInput)
                        .textFieldStyle(.roundedBorder)
                    if analyzeLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Analyze") { runAnalyze() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if let error = analyzeError {
                    errorBanner(error)
                }

                if let result = analyzeResult,
                   let nets = result["nets"] as? [String: [String: Any]] {
                    sectionLabel("Affected Nets (\(nets.count))")
                    ForEach(Array(nets.sorted(by: { $0.key < $1.key })), id: \.key) { name, info in
                        HStack {
                            Text(name)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text("\(info["tracks"] as? Int ?? 0) tracks")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(info["vias"] as? Int ?? 0) vias")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    approveRejectButtons(
                        approveLabel: "Proceed to Rip-Up Proposal",
                        onApprove: {
                            netNames = Array(nets.keys)
                            currentStation = .propose
                        }
                    )
                }
            }
        }
    }

    // MARK: - Station 2: Propose

    private var proposeStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Rip-Up Proposal", description: "Review what will be removed", icon: "list.clipboard")

            if netNames.isEmpty {
                emptyState("No nets selected. Go back to Analyze.")
            } else {
                HStack {
                    Text("\(netNames.count) nets selected")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if proposeLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Get Proposal") { runPropose() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if let result = proposeResult {
                    let totalTracks = result["total_tracks"] as? Int ?? 0
                    let totalVias = result["total_vias"] as? Int ?? 0

                    HStack(spacing: 16) {
                        statCard("\(totalTracks)", label: "Tracks", color: .orange)
                        statCard("\(totalVias)", label: "Vias", color: .red)
                        statCard("\(netNames.count)", label: "Nets", color: .blue)
                    }

                    approveRejectButtons(
                        approveLabel: "Execute Rip-Up",
                        onApprove: { currentStation = .execute }
                    )
                }
            }
        }
    }

    // MARK: - Station 3: Execute

    private var executeStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Rip-Up Execution", description: "Remove tracks and generate diff", icon: "scissors")

            HStack {
                Spacer()
                if executeLoading {
                    ProgressView().controlSize(.small)
                    Text("Processing...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Execute Rip-Up") { runExecute() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }

            if let result = executeResult {
                let tracks = result["tracks_removed"] as? Int ?? 0
                let vias = result["vias_removed"] as? Int ?? 0

                HStack(spacing: 16) {
                    statCard("\(tracks)", label: "Tracks Removed", color: .red)
                    statCard("\(vias)", label: "Vias Removed", color: .red)
                }

                if !diffText.isEmpty {
                    sectionLabel("Diff Preview (first 50 lines)")
                    ScrollView(.horizontal) {
                        Text(diffText.split(separator: "\n").prefix(50).joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                approveRejectButtons(
                    approveLabel: "Apply Diff & Open KiCad",
                    onApprove: { currentStation = .reroute }
                )
            }
        }
    }

    // MARK: - Station 4: Manual Reroute

    private var rerouteStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Manual Reroute", description: "Open the PCB in KiCad and reroute affected nets", icon: "pencil.and.ruler")

            VStack(spacing: 12) {
                Image(systemName: "pencil.and.ruler")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("The ripped board is ready for manual rerouting.")
                    .font(.body)

                Button("Open in KiCad") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: pcbPath))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Route the affected nets in KiCad, save the file, then approve below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)

            approveRejectButtons(
                approveLabel: "Reroute Complete — Run DRC",
                onApprove: { currentStation = .validate }
            )
        }
    }

    // MARK: - Station 5: Validate

    private var validateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("DRC Validation", description: "Run Design Rule Check on the modified board", icon: "checkmark.shield")

            HStack {
                Spacer()
                if validateLoading {
                    ProgressView().controlSize(.small)
                    Text("Running DRC...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Run DRC") { runValidate() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let result = drcResult {
                let errors = result["error_count"] as? Int ?? 0
                let warnings = result["warning_count"] as? Int ?? 0
                let unconnected = result["unconnected_count"] as? Int ?? 0
                let status = errors == 0 ? "PASS" : "FAIL"

                HStack(spacing: 16) {
                    statCard(status, label: "Status", color: errors == 0 ? .green : .red)
                    statCard("\(errors)", label: "Errors", color: errors > 0 ? .red : .green)
                    statCard("\(warnings)", label: "Warnings", color: warnings > 0 ? .orange : .green)
                    statCard("\(unconnected)", label: "Unconnected", color: unconnected > 0 ? .red : .green)
                }

                if errors == 0 {
                    approveRejectButtons(
                        approveLabel: "DRC Passed — Export Gerbers",
                        onApprove: { currentStation = .export_ }
                    )
                } else {
                    Text("Fix DRC errors in KiCad, then run DRC again.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Station 6: Export

    private var exportStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Gerber Export", description: "Export production files from the validated board", icon: "square.and.arrow.up")

            HStack {
                Spacer()
                if exportLoading {
                    ProgressView().controlSize(.small)
                    Text("Exporting...").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Export Gerbers") { runExport() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }

            if let result = exportResult {
                let fileCount = result["file_count"] as? Int ?? 0
                let outputDir = result["output_dir"] as? String ?? ""

                statCard("\(fileCount) files", label: "Exported", color: .green)

                Text("Output: \(outputDir)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDir)
                    }
                    .buttonStyle(.bordered)

                    Button("Done") {
                        // Reset wizard
                        currentStation = .analyze
                        analyzeResult = nil
                        proposeResult = nil
                        executeResult = nil
                        drcResult = nil
                        exportResult = nil
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
                currentStation = .analyze  // Reset to beginning
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

    // MARK: - Actions

    private func pickPCBFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "kicad_pcb")!]
        panel.message = "Select .kicad_pcb file"
        let config = PartsConfig.shared
        if FileManager.default.fileExists(atPath: config.pcbPath) {
            panel.directoryURL = URL(fileURLWithPath: config.pcbPath)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pcbPath = url.path
    }

    private func runAnalyze() {
        guard !pcbPath.isEmpty else { return }
        analyzeLoading = true; analyzeError = nil; analyzeResult = nil
        Task {
            do {
                var nets: [String] = []
                if !netInput.isEmpty {
                    nets = netInput.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                }
                let result = try await PartsAPIClient.shared.edaAnalyze(pcbPath: pcbPath, netNames: nets)
                await MainActor.run { analyzeResult = result; analyzeLoading = false }
            } catch {
                await MainActor.run { analyzeError = error.localizedDescription; analyzeLoading = false }
            }
        }
    }

    private func runPropose() {
        guard !pcbPath.isEmpty, !netNames.isEmpty else { return }
        proposeLoading = true
        Task {
            do {
                let result = try await PartsAPIClient.shared.edaProposeRipup(pcbPath: pcbPath, netNames: netNames)
                await MainActor.run { proposeResult = result; proposeLoading = false }
            } catch {
                await MainActor.run { proposeLoading = false }
            }
        }
    }

    private func runExecute() {
        guard !pcbPath.isEmpty, !netNames.isEmpty else { return }
        executeLoading = true
        Task {
            do {
                let result = try await PartsAPIClient.shared.edaExecuteRipup(pcbPath: pcbPath, netNames: netNames)
                await MainActor.run {
                    executeResult = result
                    diffText = result["diff"] as? String ?? ""
                    executeLoading = false
                }
            } catch {
                await MainActor.run { executeLoading = false }
            }
        }
    }

    private func runValidate() {
        guard !pcbPath.isEmpty else { return }
        validateLoading = true
        Task {
            do {
                let result = try await PartsAPIClient.shared.edaDRC(pcbPath: pcbPath)
                await MainActor.run { drcResult = result; validateLoading = false }
            } catch {
                await MainActor.run { validateLoading = false }
            }
        }
    }

    private func runExport() {
        guard !pcbPath.isEmpty else { return }
        exportLoading = true
        Task {
            do {
                let result = try await PartsAPIClient.shared.edaExport(pcbPath: pcbPath)
                await MainActor.run { exportResult = result; exportLoading = false }
            } catch {
                await MainActor.run { exportLoading = false }
            }
        }
    }
}
#endif
