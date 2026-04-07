import SwiftUI

/// Data model for Gerber Job File (.gbrjob) — Ucamco spec.
struct GerberJob: Codable {
    let Header: GerberJobHeader?
    let GeneralSpecs: GerberJobSpecs?
    let DesignRules: [GerberJobDesignRule]?
    let FilesAttributes: [GerberJobFile]?
    let MaterialStackup: [GerberJobStackupLayer]?

    struct GerberJobHeader: Codable {
        let GenerationSoftware: GerberJobSoftware?
        let CreationDate: String?
    }

    struct GerberJobSoftware: Codable {
        let Vendor: String?
        let Application: String?
        let Version: String?
    }

    struct GerberJobSpecs: Codable {
        let ProjectId: GerberJobProject?
        let Size: GerberJobSize?
        let LayerNumber: Int?
        let BoardThickness: Double?
        let Finish: String?
    }

    struct GerberJobProject: Codable {
        let Name: String?
        let GUID: String?
        let Revision: String?
    }

    struct GerberJobSize: Codable {
        let X: Double?
        let Y: Double?
    }

    struct GerberJobDesignRule: Codable {
        let Layers: String?
        let PadToPad: Double?
        let PadToTrack: Double?
        let TrackToTrack: Double?
        let MinLineWidth: Double?
        let TrackToRegion: Double?
        let RegionToRegion: Double?
    }

    struct GerberJobFile: Codable {
        let Path: String?
        let FileFunction: String?
        let FilePolarity: String?
    }

    struct GerberJobStackupLayer: Codable {
        let layerType: String?
        let Thickness: Double?
        let Material: String?
        let Name: String?
        let Notes: String?

        enum CodingKeys: String, CodingKey {
            case layerType = "Type"
            case Thickness, Material, Name, Notes
        }
    }
}

/// Viewer for Gerber Job Files (.gbrjob).
/// Shows board specs, layer stackup visualization, file list, and design rules.
struct GerberJobView: View {
    let filePath: String
    @EnvironmentObject var appState: AppState
    @State private var job: GerberJob?
    @State private var error: String?

    /// Directory containing the .gbrjob and its gerber files.
    private var gerberDir: String {
        URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.purple)
                Text("Gerber Job File")
                    .font(.headline)
                Spacer()
                if let job = job, let specs = job.GeneralSpecs {
                    Text("\(specs.LayerNumber ?? 0)L")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
                Button(action: { openGerberViewer() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.caption)
                        Text("View Layers")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "") }) {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let err = error {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let job = job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        boardInfoSection(job)
                        stackupSection(job)
                        filesSection(job)
                        designRulesSection(job)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 32)
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear { loadJob() }
    }

    // MARK: - Board Info

    @ViewBuilder
    private func boardInfoSection(_ job: GerberJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Board", icon: "cpu")

            let specs = job.GeneralSpecs
            let header = job.Header

            LazyVGrid(columns: [GridItem(.fixed(120), alignment: .trailing), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                if let name = specs?.ProjectId?.Name {
                    propLabel("Project"); propValue(name)
                }
                if let rev = specs?.ProjectId?.Revision, rev != "rev?" {
                    propLabel("Revision"); propValue(rev)
                }
                if let x = specs?.Size?.X, let y = specs?.Size?.Y {
                    propLabel("Size"); propValue(String(format: "%.2f x %.2f mm", x, y))
                }
                if let layers = specs?.LayerNumber {
                    propLabel("Layers"); propValue("\(layers)")
                }
                if let thick = specs?.BoardThickness {
                    propLabel("Thickness"); propValue(String(format: "%.1f mm", thick))
                }
                if let finish = specs?.Finish, finish != "None" {
                    propLabel("Finish"); propValue(finish)
                }
                if let sw = header?.GenerationSoftware {
                    propLabel("Software"); propValue("\(sw.Application ?? "") \(sw.Version ?? "")")
                }
                if let date = header?.CreationDate {
                    propLabel("Created"); propValue(formatDate(date))
                }
            }
        }
    }

    // MARK: - Stackup Visualization

    @ViewBuilder
    private func stackupSection(_ job: GerberJob) -> some View {
        if let stackup = job.MaterialStackup, !stackup.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Layer Stackup", icon: "square.stack.3d.up")

            VStack(spacing: 0) {
                ForEach(Array(stackup.enumerated()), id: \.offset) { _, layer in
                    let isCopperOrMask = ["Copper", "SolderMask", "SolderPaste", "Legend"].contains(layer.layerType ?? "")
                    HStack(spacing: 0) {
                        // Color bar
                        Rectangle()
                            .fill(stackupColor(layer.layerType ?? ""))
                            .frame(width: 6)

                        // Layer info
                        HStack(spacing: 8) {
                            Text(layer.Name ?? layer.layerType ?? "")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(width: 160, alignment: .leading)

                            Text(layer.layerType ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)

                            if let thick = layer.Thickness {
                                Text(String(format: "%.0f \u{00B5}m", thick * 1000))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 60, alignment: .trailing)
                            } else {
                                Spacer().frame(width: 60)
                            }

                            if let mat = layer.Material {
                                Text(mat)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if isCopperOrMask {
                                Image(systemName: "eye")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, stackupHeight(layer.layerType ?? "", layer.Thickness))
                    }
                    .background(stackupBgColor(layer.layerType ?? ""))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isCopperOrMask { openGerberViewer() }
                    }
                    .onHover { hovering in
                        if isCopperOrMask {
                            hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        } // if let stackup
    }

    private func stackupColor(_ type: String) -> Color {
        switch type {
        case "Copper": return .orange
        case "Dielectric": return .green.opacity(0.6)
        case "SolderMask": return .blue
        case "SolderPaste": return .gray
        case "Legend": return .white
        default: return .secondary
        }
    }

    private func stackupBgColor(_ type: String) -> Color {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch type {
        case "Copper": return isDark ? Color(white: 0.18) : Color(white: 0.97)
        case "Dielectric": return isDark ? Color(white: 0.13) : Color(white: 0.94)
        default: return isDark ? Color(white: 0.15) : Color(white: 0.96)
        }
    }

    private func stackupHeight(_ type: String, _ thickness: Double?) -> CGFloat {
        switch type {
        case "Copper": return 4
        case "Dielectric": return max(3, min(8, CGFloat((thickness ?? 0.1) * 40)))
        case "SolderMask": return 3
        default: return 2
        }
    }

    // MARK: - Files

    @ViewBuilder
    private func filesSection(_ job: GerberJob) -> some View {
        if let files = job.FilesAttributes, !files.isEmpty {

        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Gerber Files (\(files.count))", icon: "doc.on.doc")

            VStack(spacing: 1) {
                // Header
                HStack(spacing: 0) {
                    Text("File").font(.system(size: 10, weight: .semibold)).frame(width: 300, alignment: .leading)
                    Text("Function").font(.system(size: 10, weight: .semibold)).frame(width: 160, alignment: .leading)
                    Text("Polarity").font(.system(size: 10, weight: .semibold)).frame(width: 80, alignment: .leading)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))

                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    HStack(spacing: 0) {
                        Text(file.Path ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 300, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(file.FileFunction ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 160, alignment: .leading)
                        Text(file.FilePolarity ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(file.FilePolarity == "Negative" ? .red : .green)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture { openGerberViewer(file: file.Path) }
                    .onHover { hovering in
                        hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        } // if let files
    }

    // MARK: - Design Rules

    @ViewBuilder
    private func designRulesSection(_ job: GerberJob) -> some View {
        if let rules = job.DesignRules, !rules.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Design Rules", icon: "ruler")

            ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.Layers ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.fixed(120), alignment: .trailing), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                        if let v = rule.MinLineWidth { propLabel("Min Width"); propValue(String(format: "%.3f mm", v)) }
                        if let v = rule.PadToPad { propLabel("Pad-Pad"); propValue(String(format: "%.3f mm", v)) }
                        if let v = rule.PadToTrack { propLabel("Pad-Track"); propValue(String(format: "%.3f mm", v)) }
                        if let v = rule.TrackToTrack { propLabel("Track-Track"); propValue(String(format: "%.3f mm", v)) }
                        if let v = rule.TrackToRegion { propLabel("Track-Region"); propValue(String(format: "%.3f mm", v)) }
                        if let v = rule.RegionToRegion { propLabel("Region-Region"); propValue(String(format: "%.3f mm", v)) }
                    }
                }
            }
        }
        } // if let rules
    }

    // MARK: - Navigation

    /// Open the Gerber Viewer for all gerber files in the same directory as this .gbrjob.
    /// Optionally specify a file path (relative from .gbrjob) to focus.
    private func openGerberViewer(file: String? = nil) {
        let targetPath: String
        if let file = file {
            // Resolve relative path from .gbrjob directory
            targetPath = "\(gerberDir)/\(file)"
        } else {
            // Find the first gerber file in the directory
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(atPath: gerberDir)) ?? []
            let gerberExts: Set<String> = ["gbr", "gtl", "gbl", "gts", "gbs", "gto", "gbo", "gtp", "gbp", "gm1", "gko", "drl", "xln"]
            let firstGerber = files.first { f in
                let ext = URL(fileURLWithPath: f).pathExtension.lowercased()
                return gerberExts.contains(ext) || (ext.hasPrefix("g") && Int(ext.dropFirst()) != nil)
            }
            guard let g = firstGerber else { return }
            targetPath = "\(gerberDir)/\(g)"
        }

        // Navigate by setting an assembly doc pointing to the gerber file
        let doc = AssemblyDocument(
            id: targetPath,
            name: URL(fileURLWithPath: targetPath).lastPathComponent,
            category: "Fab",
            path: targetPath,
            size: 0,
            revision: ""
        )
        appState.selectedAssemblyDoc = doc
        appState.selectedDatasheet = nil
        appState.selectedECO = nil
        appState.selectedIQCItem = nil
        appState.pdfDocument = nil
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
    }

    @ViewBuilder
    private func propLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func propValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return iso
    }

    private func loadJob() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            error = "Cannot read file"
            return
        }
        do {
            job = try JSONDecoder().decode(GerberJob.self, from: data)
        } catch {
            self.error = "Invalid .gbrjob: \(error.localizedDescription)"
        }
    }
}
