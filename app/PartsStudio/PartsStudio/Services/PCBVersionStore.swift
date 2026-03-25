#if os(macOS)
import Foundation

/// Discovers and manages PCB versions for the active project.
class PCBVersionStore: ObservableObject {
    @Published var versions: [PCBVersion] = []
    @Published var selectedVersion: PCBVersion?

    private let projectRoot: String

    init(projectRoot: String = "") {
        self.projectRoot = projectRoot.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path + "/Work/Consulting/nRF54H20-Main-Board"
            : projectRoot
        discover()
    }

    func discover() {
        var found: [PCBVersion] = []

        // V1: 8-Layer Original
        let v1Dir = projectRoot + "/Original_Files/8layer_V1.01_2026-01-28/GERBER-FILE/8layer_V1.01_2026-01-28"
        if FileManager.default.fileExists(atPath: v1Dir) {
            let layers = PCBLayerClassifier.discoverLayers(in: v1Dir)
            if !layers.isEmpty {
                found.append(PCBVersion(
                    id: "v1", name: "V1: 8L Original (HDI)", shortName: "V1",
                    layerCount: layers.filter { $0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper }.count,
                    basePath: v1Dir, gbrjobPath: nil, layers: layers
                ))
            }
        }

        // V2: 8-Layer Revised
        let v2Candidates = [
            projectRoot + "/Original_Files/nRF54H20_Main_V1.03_ 8Layer_2026-01-28"
        ]
        for v2Dir in v2Candidates {
            if FileManager.default.fileExists(atPath: v2Dir) {
                // Check for gerbers directly or in subdirectories
                var layers = PCBLayerClassifier.discoverLayers(in: v2Dir)
                if layers.isEmpty {
                    // Try GERBER-FILE subdirectory
                    if let sub = try? FileManager.default.contentsOfDirectory(atPath: v2Dir)
                        .first(where: { $0.uppercased().contains("GERBER") }) {
                        layers = PCBLayerClassifier.discoverLayers(in: (v2Dir as NSString).appendingPathComponent(sub))
                    }
                }
                if !layers.isEmpty {
                    found.append(PCBVersion(
                        id: "v2", name: "V2: 8L Revised", shortName: "V2",
                        layerCount: layers.filter { $0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper }.count,
                        basePath: v2Dir, gbrjobPath: nil, layers: layers
                    ))
                    break
                }
            }
        }

        // V3: 10-Layer Source Parts (EVT2 fab_release has the cleanest files)
        let v3Dir = projectRoot + "/PCB/EVT2/fab_release"
        if FileManager.default.fileExists(atPath: v3Dir) {
            let layers = PCBLayerClassifier.discoverLayers(in: v3Dir)
            let gbrjob = (v3Dir as NSString).appendingPathComponent("nRF54H20_Main_V1.03-PcbDoc-job.gbrjob")
            let hasJob = FileManager.default.fileExists(atPath: gbrjob)
            if !layers.isEmpty {
                found.append(PCBVersion(
                    id: "v3", name: "V3: 10L Source Parts", shortName: "V3",
                    layerCount: layers.filter { $0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper }.count,
                    basePath: v3Dir, gbrjobPath: hasJob ? gbrjob : nil, layers: layers
                ))
            }
        }

        // V4: 10-Layer Production (panelized)
        let v4Base = projectRoot + "/PCB/Production_Release"
        if FileManager.default.fileExists(atPath: v4Base) {
            // Find the extracted zip directory
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: v4Base) {
                for dir in contents where dir.hasSuffix("_125354") || dir.contains("PcbDoc_2026") {
                    let v4Dir = (v4Base as NSString).appendingPathComponent(dir)
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: v4Dir, isDirectory: &isDir), isDir.boolValue else { continue }
                    let layers = PCBLayerClassifier.discoverLayers(in: v4Dir)
                    if !layers.isEmpty {
                        found.append(PCBVersion(
                            id: "v4", name: "V4: 10L Production (Panelized)", shortName: "V4",
                            layerCount: layers.filter { $0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper }.count,
                            basePath: v4Dir,
                            gbrjobPath: v3Dir + "/nRF54H20_Main_V1.03-PcbDoc-job.gbrjob",
                            layers: layers
                        ))
                        break
                    }
                }
            }
        }

        // V4B: 8-Layer CAM Output
        let v4bDir = projectRoot + "/Original_Files/516353A_Y101"
        if FileManager.default.fileExists(atPath: v4bDir) {
            let layers = PCBLayerClassifier.discoverLayers(in: v4bDir)
            if !layers.isEmpty {
                found.append(PCBVersion(
                    id: "v4b", name: "V4B: 8L CAM Output", shortName: "V4B",
                    layerCount: layers.filter { $0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper }.count,
                    basePath: v4bDir, gbrjobPath: nil, layers: layers
                ))
            }
        }

        versions = found
        selectedVersion = found.first(where: { $0.id == "v3" }) ?? found.first
    }
}
#endif
