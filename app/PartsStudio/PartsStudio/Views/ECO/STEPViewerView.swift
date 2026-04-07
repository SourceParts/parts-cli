#if os(macOS)
import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO
import UniformTypeIdentifiers

// MARK: - STEP Metadata

struct STEPMetadata {
    var file: String = ""
    var shapes: Int = 0
    var solids: Int = 0
    var faces: Int = 0
    var width: Double = 0
    var height: Double = 0
    var depth: Double = 0
    var unit: String = "mm"
    var minX: Double = 0
    var minY: Double = 0
    var minZ: Double = 0
    var maxX: Double = 0
    var maxY: Double = 0
    var maxZ: Double = 0
}

// MARK: - Layer Type

enum LayerCategory: String, CaseIterable {
    case hardware = "Hardware"
    case manufacturing = "Manufacturing"
    case custom = "Custom"
}

struct LayerType: Identifiable, Hashable {
    let id: String
    let name: String
    let category: LayerCategory
    let badge: NSColor

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LayerType, rhs: LayerType) -> Bool { lhs.id == rhs.id }

    static let none = LayerType(id: "none", name: "Unassigned", category: .hardware, badge: NSColor.gray)

    // Hardware types
    static let pcb = LayerType(id: "pcb", name: "PCB", category: .hardware, badge: NSColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1))
    static let enclosure = LayerType(id: "enclosure", name: "Enclosure", category: .hardware, badge: NSColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1))
    static let connector = LayerType(id: "connector", name: "Connector", category: .hardware, badge: NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    static let led = LayerType(id: "led", name: "LED", category: .hardware, badge: NSColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1))
    static let battery = LayerType(id: "battery", name: "Battery", category: .hardware, badge: NSColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
    static let antenna = LayerType(id: "antenna", name: "Antenna", category: .hardware, badge: NSColor(red: 0.7, green: 0.3, blue: 0.8, alpha: 1))
    static let heatsink = LayerType(id: "heatsink", name: "Heatsink", category: .hardware, badge: NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
    static let ic = LayerType(id: "ic", name: "IC / Module", category: .hardware, badge: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1))
    static let switch_ = LayerType(id: "switch", name: "Switch", category: .hardware, badge: NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
    static let lens = LayerType(id: "lens", name: "Lens / Window", category: .hardware, badge: NSColor(red: 0.6, green: 0.8, blue: 0.95, alpha: 1))
    static let gasket = LayerType(id: "gasket", name: "Gasket / Seal", category: .hardware, badge: NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
    static let fastener = LayerType(id: "fastener", name: "Fastener", category: .hardware, badge: NSColor(red: 0.7, green: 0.7, blue: 0.72, alpha: 1))
    static let cable = LayerType(id: "cable", name: "Cable / FPC", category: .hardware, badge: NSColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1))

    // Manufacturing types
    static let injectionMold = LayerType(id: "injection_mold", name: "Injection Mold", category: .manufacturing, badge: NSColor(red: 0.4, green: 0.7, blue: 0.4, alpha: 1))
    static let cnc = LayerType(id: "cnc", name: "CNC", category: .manufacturing, badge: NSColor(red: 0.5, green: 0.6, blue: 0.8, alpha: 1))
    static let sheetMetal = LayerType(id: "sheet_metal", name: "Sheet Metal", category: .manufacturing, badge: NSColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1))
    static let pcbFR4 = LayerType(id: "pcb_fr4", name: "PCB FR4", category: .manufacturing, badge: NSColor(red: 0.1, green: 0.5, blue: 0.1, alpha: 1))
    static let flexPCB = LayerType(id: "flex_pcb", name: "Flex PCB", category: .manufacturing, badge: NSColor(red: 0.8, green: 0.6, blue: 0.1, alpha: 1))
    static let diecast = LayerType(id: "diecast", name: "Die Cast", category: .manufacturing, badge: NSColor(red: 0.55, green: 0.55, blue: 0.6, alpha: 1))
    static let printed3D = LayerType(id: "3d_print", name: "3D Print", category: .manufacturing, badge: NSColor(red: 0.3, green: 0.8, blue: 0.8, alpha: 1))
    static let extrusion = LayerType(id: "extrusion", name: "Extrusion", category: .manufacturing, badge: NSColor(red: 0.7, green: 0.5, blue: 0.3, alpha: 1))

    static let hardwareTypes: [LayerType] = [.pcb, .enclosure, .connector, .led, .battery, .antenna, .heatsink, .ic, .switch_, .lens, .gasket, .fastener, .cable]
    static let manufacturingTypes: [LayerType] = [.injectionMold, .cnc, .sheetMetal, .pcbFR4, .flexPCB, .diecast, .printed3D, .extrusion]
    static let allPresets: [LayerType] = [.none] + hardwareTypes + manufacturingTypes
}

// MARK: - Scene Node Info (for layer tree)

class SceneNodeInfo: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let node: SCNNode
    let faceCount: Int
    @Published var visible: Bool = true
    @Published var color: NSColor
    @Published var opacity: Double = 1.0
    @Published var layerType: LayerType = .none

    init(name: String, node: SCNNode, faceCount: Int, color: NSColor) {
        self.name = name
        self.node = node
        self.faceCount = faceCount
        self.color = color
    }
}

// MARK: - STEP Viewer View

struct STEPViewerView: View {
    let filePath: String
    @State private var scene: SCNScene?
    @State private var metadata: STEPMetadata?
    @State private var isLoading = true
    @State private var error: String?
    @State private var wireframe = false
    @State private var stlTempPath: String?
    @State private var nodeInfos: [SceneNodeInfo] = []
    @State private var activeMaterial: PVDMaterial = .none

    private static let nodeColors: [NSColor] = [
        NSColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1.0),  // steel gray
        NSColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0),   // blue
        NSColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1.0),   // green
        NSColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1.0),   // orange
        NSColor(red: 0.7, green: 0.3, blue: 0.6, alpha: 1.0),   // purple
        NSColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1.0),   // red
        NSColor(red: 0.3, green: 0.7, blue: 0.7, alpha: 1.0),   // teal
        NSColor(red: 0.8, green: 0.75, blue: 0.3, alpha: 1.0),  // gold
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(Color.accentColor)
                Text("3D Viewer")
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Converting STEP...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 20)

                // Wireframe toggle
                Button(action: { wireframe.toggle(); updateWireframe() }) {
                    Image(systemName: wireframe ? "square.grid.3x3.fill" : "square.grid.3x3")
                }
                .help(wireframe ? "Solid view" : "Wireframe view")
                .foregroundStyle(wireframe ? Color.accentColor : .primary)

                Divider()
                    .frame(height: 20)

                // PVD material presets
                Menu {
                    ForEach(PVDMaterial.allCases, id: \.self) { mat in
                        Button(action: { applyPVDMaterial(mat) }) {
                            HStack {
                                Text(mat.displayName)
                                if activeMaterial == mat {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintbrush.fill")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("PVD surface finish")

                Divider()
                    .frame(height: 20)

                // Export
                Menu {
                    Button("Save STL...") { exportSTL() }
                    Button("Screenshot PNG...") { exportScreenshot() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Export")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HSplitView {
                // 3D viewport
                if let scene {
                    SceneKitView(scene: scene)
                        .frame(minWidth: 400)
                } else if let error {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text("Failed to load STEP file")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                        Button("Retry") { loadSTEP() }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack {
                        Spacer()
                        ProgressView("Converting STEP to 3D mesh...")
                            .font(.caption)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

                // Layer tree + info sidebar
                VStack(alignment: .leading, spacing: 0) {
                    if !nodeInfos.isEmpty {
                        Text("Layers (\(nodeInfos.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(nodeInfos) { info in
                                    LayerRow(info: info, onChanged: { applyNodeAppearance(info) })
                                }

                                Divider()
                                    .padding(.vertical, 4)

                                HStack(spacing: 8) {
                                    Button("Show All") {
                                        nodeInfos.forEach { $0.visible = true; applyNodeAppearance($0) }
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.link)

                                    Button("Reset") {
                                        for (i, info) in nodeInfos.enumerated() {
                                            info.color = Self.nodeColors[i % Self.nodeColors.count]
                                            info.opacity = 1.0
                                            info.visible = true
                                            applyNodeAppearance(info)
                                        }
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.link)
                                }
                                .padding(.horizontal, 10)
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    // Model info (collapsed section below layers)
                    if let meta = metadata {
                        Divider()

                        DisclosureGroup("Model Info") {
                            VStack(alignment: .leading, spacing: 4) {
                                infoRow("File", URL(fileURLWithPath: filePath).lastPathComponent)
                                infoRow("Size", String(format: "%.1f x %.1f x %.1f %@", meta.width, meta.height, meta.depth, meta.unit))
                                infoRow("Shapes", "\(meta.shapes)")
                                infoRow("Solids", "\(meta.solids)")
                                infoRow("Faces", "\(meta.faces)")
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .frame(width: 220)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            // Status bar
            HStack(spacing: 16) {
                if let meta = metadata {
                    Text(String(format: "%.1f x %.1f x %.1f %@", meta.width, meta.height, meta.depth, meta.unit))
                    Text("\(meta.faces) faces")
                    Text("\(meta.solids) solids")
                }
                Spacer()
                let visible = nodeInfos.filter(\.visible).count
                if !nodeInfos.isEmpty {
                    Text("\(visible)/\(nodeInfos.count) layers")
                }
                Text(wireframe ? "Wireframe" : "Solid")
                    .foregroundStyle(wireframe ? .yellow : .secondary)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task(id: filePath) { loadSTEP() }
    }

    // MARK: - Layer Row

    struct LayerRow: View {
        @ObservedObject var info: SceneNodeInfo
        @State private var customTypeName = ""
        var onChanged: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Visibility toggle
                    Button(action: {
                        info.visible.toggle()
                        onChanged()
                    }) {
                        Image(systemName: info.visible ? "eye.fill" : "eye.slash")
                            .font(.system(size: 10))
                            .foregroundColor(info.visible ? Color(info.color) : .gray)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(info.visible ? "Hide" : "Show")

                    // Color picker
                    ColorPicker("", selection: Binding(
                        get: { Color(info.color) },
                        set: { info.color = NSColor($0); onChanged() }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 24, height: 18)
                    .disabled(!info.visible)
                    .opacity(info.visible ? 1.0 : 0.3)
                    .help("Part color")

                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(info.visible ? .primary : .tertiary)

                        // Type badge
                        if info.layerType.id != "none" {
                            Text(info.layerType.name)
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(info.layerType.badge).opacity(0.2))
                                .foregroundStyle(Color(info.layerType.badge))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Spacer()

                    if info.visible {
                        Text("\(Int(info.opacity * 100))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }

                // Opacity slider
                if info.visible {
                    Slider(value: Binding(
                        get: { info.opacity },
                        set: { info.opacity = $0; onChanged() }
                    ), in: 0.05...1.0)
                    .controlSize(.mini)
                    .tint(Color(info.color))
                    .padding(.leading, 22)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .contextMenu {
                // Layer type assignment
                Menu("Hardware Type") {
                    ForEach(LayerType.hardwareTypes) { type in
                        Button(action: { info.layerType = type }) {
                            HStack {
                                Circle().fill(Color(type.badge)).frame(width: 8, height: 8)
                                Text(type.name)
                                if info.layerType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Menu("Manufacturing Type") {
                    ForEach(LayerType.manufacturingTypes) { type in
                        Button(action: { info.layerType = type }) {
                            HStack {
                                Circle().fill(Color(type.badge)).frame(width: 8, height: 8)
                                Text(type.name)
                                if info.layerType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Button("Clear Type") { info.layerType = .none }

                Divider()

                Button("Solo") {
                    NotificationCenter.default.post(name: .stepSoloNode, object: info.id)
                }
                Button("Reset Color") {
                    info.opacity = 1.0
                    onChanged()
                }
            }
        }
    }

    // MARK: - Node Appearance

    private func applyNodeAppearance(_ info: SceneNodeInfo) {
        info.node.isHidden = !info.visible
        if let geometry = info.node.geometry {
            for material in geometry.materials {
                material.diffuse.contents = info.color
                material.transparency = CGFloat(info.opacity)
                material.fillMode = wireframe ? .lines : .fill
            }
        }
    }

    // MARK: - Load STEP

    private func loadSTEP() {
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await convertSTEP()
                await MainActor.run {
                    scene = result.scene
                    metadata = result.metadata
                    stlTempPath = result.stlPath
                    nodeInfos = result.nodeInfos
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private struct ConvertResult {
        let scene: SCNScene
        let metadata: STEPMetadata
        let stlPath: String
        let nodeInfos: [SceneNodeInfo]
    }

    private func convertSTEP() async throws -> ConvertResult {
        guard let tool = findStepConvert() else {
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "step-convert not found.\nBuild with: c++ -std=c++17 -o tools/step-convert tools/step-convert.cpp -I/opt/homebrew/include/opencascade -L/opt/homebrew/lib -lTKDESTEP -lTKDESTL -lTKMesh -lTKBRep -lTKernel -lTKG3d -lTKTopAlgo -lTKXSBase -lTKMath -lTKGeomBase -lTKGeomAlgo -lTKShHealing"])
        }

        let stlPath = NSTemporaryDirectory() + "parts_step_\(UUID().uuidString).stl"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = [filePath, stlPath, "--info", "--split"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Conversion failed"
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: errStr])
        }

        // Parse metadata from stderr (includes parts array with names)
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        let meta = parseMetadata(stderrStr)
        let partNames = parsePartNames(stderrStr)

        // Load split STL files as separate SceneKit nodes
        let scnScene = SCNScene()
        var infos: [SceneNodeInfo] = []

        // Check for split files: stlPath_0.stl, stlPath_1.stl, ...
        let basePath = stlPath.hasSuffix(".stl") ? String(stlPath.dropLast(4)) : stlPath
        var splitIndex = 0
        while true {
            let splitPath = "\(basePath)_\(splitIndex).stl"
            guard FileManager.default.fileExists(atPath: splitPath) else { break }

            let asset = MDLAsset(url: URL(fileURLWithPath: splitPath))
            let partScene = SCNScene(mdlAsset: asset)

            // Move geometry nodes into main scene
            var partNodeFound = false
            partScene.rootNode.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }
                if partNodeFound { return } // one node per split file
                partNodeFound = true

                let color = Self.nodeColors[splitIndex % Self.nodeColors.count]
                let name = splitIndex < partNames.count ? partNames[splitIndex] : "Part \(splitIndex + 1)"
                let faceCount = geometry.elements.reduce(0) { $0 + $1.primitiveCount }

                // Apply material
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.specular.contents = NSColor.white
                material.metalness.contents = NSColor(white: 0.4, alpha: 1.0)
                material.roughness.contents = NSColor(white: 0.3, alpha: 1.0)
                material.lightingModel = .physicallyBased
                material.isDoubleSided = true
                geometry.materials = [material]

                node.name = name
                scnScene.rootNode.addChildNode(node)

                let info = SceneNodeInfo(name: name, node: node, faceCount: faceCount, color: color)
                infos.append(info)
            }

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: splitPath)
            splitIndex += 1
        }

        // Fallback: if no split files, load the single STL
        if infos.isEmpty && FileManager.default.fileExists(atPath: stlPath) {
            let asset = MDLAsset(url: URL(fileURLWithPath: stlPath))
            let fallbackScene = SCNScene(mdlAsset: asset)
            fallbackScene.rootNode.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }
                let color = Self.nodeColors[0]
                let faceCount = geometry.elements.reduce(0) { $0 + $1.primitiveCount }

                let material = SCNMaterial()
                material.diffuse.contents = color
                material.specular.contents = NSColor.white
                material.metalness.contents = NSColor(white: 0.4, alpha: 1.0)
                material.roughness.contents = NSColor(white: 0.3, alpha: 1.0)
                material.lightingModel = .physicallyBased
                material.isDoubleSided = true
                geometry.materials = [material]

                node.name = "Body"
                scnScene.rootNode.addChildNode(node)
                infos.append(SceneNodeInfo(name: "Body", node: node, faceCount: faceCount, color: color))
            }
        }

        // Set up lighting and environment
        setupSceneLighting(scnScene, metadata: meta)

        return ConvertResult(scene: scnScene, metadata: meta, stlPath: stlPath, nodeInfos: infos)
    }

    private func setupSceneLighting(_ scene: SCNScene, metadata: STEPMetadata) {
        // Ambient light
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.color = NSColor(white: 0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambientNode)

        // Directional light
        let dirNode = SCNNode()
        dirNode.light = SCNLight()
        dirNode.light?.type = .directional
        dirNode.light?.color = NSColor(white: 0.8, alpha: 1.0)
        dirNode.light?.castsShadow = true
        dirNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(dirNode)

        // Fill light
        let fillNode = SCNNode()
        fillNode.light = SCNLight()
        fillNode.light?.type = .directional
        fillNode.light?.color = NSColor(white: 0.3, alpha: 1.0)
        fillNode.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillNode)

        // Grid floor
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = NSColor(white: 0.15, alpha: 1.0)
        floor.materials = [floorMaterial]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, Float(metadata.minZ) - 1, 0)
        scene.rootNode.addChildNode(floorNode)

        // Background
        scene.background.contents = NSColor(white: 0.1, alpha: 1.0)
    }

    // MARK: - Wireframe

    private func updateWireframe() {
        for info in nodeInfos {
            if let geometry = info.node.geometry {
                for material in geometry.materials {
                    material.fillMode = wireframe ? .lines : .fill
                }
            }
        }
    }

    // MARK: - PVD Material

    private func applyPVDMaterial(_ mat: PVDMaterial) {
        activeMaterial = mat
        for info in nodeInfos {
            guard let geometry = info.node.geometry else { continue }
            for material in geometry.materials {
                if mat == .none {
                    // Restore per-layer color
                    material.diffuse.contents = info.color
                    material.metalness.contents = NSColor(white: 0.4, alpha: 1.0)
                    material.roughness.contents = NSColor(white: 0.3, alpha: 1.0)
                    material.specular.contents = NSColor.white
                } else {
                    material.diffuse.contents = mat.diffuseColor
                    material.metalness.contents = NSColor(white: CGFloat(mat.metalness), alpha: 1.0)
                    material.roughness.contents = NSColor(white: CGFloat(mat.roughness), alpha: 1.0)
                    material.specular.contents = mat.specularColor
                }
            }
        }
    }

    // MARK: - Metadata Parsing

    private func parseMetadata(_ stderr: String) -> STEPMetadata {
        var meta = STEPMetadata()
        for line in stderr.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            meta.file = json["file"] as? String ?? ""
            meta.shapes = json["shapes"] as? Int ?? 0
            meta.solids = json["solids"] as? Int ?? 0
            meta.faces = json["faces"] as? Int ?? 0
            meta.width = json["width"] as? Double ?? 0
            meta.height = json["height"] as? Double ?? 0
            meta.depth = json["depth"] as? Double ?? 0
            meta.unit = json["unit"] as? String ?? "mm"

            if let bounds = json["bounds"] as? [String: Any] {
                meta.minX = bounds["min_x"] as? Double ?? 0
                meta.minY = bounds["min_y"] as? Double ?? 0
                meta.minZ = bounds["min_z"] as? Double ?? 0
                meta.maxX = bounds["max_x"] as? Double ?? 0
                meta.maxY = bounds["max_y"] as? Double ?? 0
                meta.maxZ = bounds["max_z"] as? Double ?? 0
            }
            break
        }
        return meta
    }

    /// Parse part names from the "parts" array in the --info JSON output.
    private func parsePartNames(_ stderr: String) -> [String] {
        for line in stderr.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parts = json["parts"] as? [[String: Any]] else { continue }
            return parts.map { $0["name"] as? String ?? "Part" }
        }
        return []
    }

    // MARK: - Export

    private func exportSTL() {
        guard let stlPath = stlTempPath, FileManager.default.fileExists(atPath: stlPath) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "stl") ?? .data]
        panel.nameFieldStringValue = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent + ".stl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.copyItem(atPath: stlPath, toPath: url.path)
    }

    private func exportScreenshot() {
        NotificationCenter.default.post(name: .stepExportScreenshot, object: nil)
    }

    // MARK: - Helpers

    private func findStepConvert() -> String? {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/step-convert",
            "/opt/homebrew/bin/step-convert",
            "/usr/local/bin/step-convert",
            Bundle.main.bundlePath + "/../tools/step-convert",
        ]
        let toolsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tools/step-convert").path
        return ([toolsDir] + paths).first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - PVD Material Presets

enum PVDMaterial: String, CaseIterable {
    case none = "None"
    case aluminum = "Aluminum"
    case stainlessSteel = "Stainless Steel"
    case titanium = "Titanium"
    case copper = "Copper"
    case gold = "Gold"
    case roseGold = "Rose Gold"
    case blackChrome = "Black Chrome"
    case nickel = "Nickel"
    case brass = "Brass"

    var displayName: String { rawValue }

    var diffuseColor: NSColor {
        switch self {
        case .none:           return .gray
        case .aluminum:       return NSColor(red: 0.77, green: 0.79, blue: 0.82, alpha: 1.0)
        case .stainlessSteel: return NSColor(red: 0.72, green: 0.73, blue: 0.74, alpha: 1.0)
        case .titanium:       return NSColor(red: 0.62, green: 0.62, blue: 0.65, alpha: 1.0)
        case .copper:         return NSColor(red: 0.85, green: 0.55, blue: 0.40, alpha: 1.0)
        case .gold:           return NSColor(red: 0.85, green: 0.75, blue: 0.45, alpha: 1.0)
        case .roseGold:       return NSColor(red: 0.85, green: 0.60, blue: 0.55, alpha: 1.0)
        case .blackChrome:    return NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        case .nickel:         return NSColor(red: 0.70, green: 0.70, blue: 0.68, alpha: 1.0)
        case .brass:          return NSColor(red: 0.80, green: 0.68, blue: 0.38, alpha: 1.0)
        }
    }

    var specularColor: NSColor {
        switch self {
        case .none:           return .white
        case .aluminum:       return NSColor(white: 0.95, alpha: 1.0)
        case .stainlessSteel: return NSColor(white: 0.9, alpha: 1.0)
        case .titanium:       return NSColor(white: 0.7, alpha: 1.0)
        case .copper:         return NSColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1.0)
        case .gold:           return NSColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0)
        case .roseGold:       return NSColor(red: 1.0, green: 0.85, blue: 0.8, alpha: 1.0)
        case .blackChrome:    return NSColor(white: 0.6, alpha: 1.0)
        case .nickel:         return NSColor(white: 0.85, alpha: 1.0)
        case .brass:          return NSColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 1.0)
        }
    }

    var metalness: Float {
        switch self {
        case .none:           return 0.4
        case .aluminum:       return 0.9
        case .stainlessSteel: return 0.85
        case .titanium:       return 0.75
        case .copper:         return 0.95
        case .gold:           return 0.98
        case .roseGold:       return 0.95
        case .blackChrome:    return 0.9
        case .nickel:         return 0.85
        case .brass:          return 0.9
        }
    }

    var roughness: Float {
        switch self {
        case .none:           return 0.3
        case .aluminum:       return 0.25
        case .stainlessSteel: return 0.2
        case .titanium:       return 0.35
        case .copper:         return 0.15
        case .gold:           return 0.1
        case .roseGold:       return 0.12
        case .blackChrome:    return 0.08
        case .nickel:         return 0.2
        case .brass:          return 0.18
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let stepExportScreenshot = Notification.Name("stepExportScreenshot")
    static let stepSoloNode = Notification.Name("stepSoloNode")
}

// MARK: - SceneKit View

struct SceneKitView: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        scnView.antialiasingMode = .multisampling4X
        scnView.showsStatistics = false

        // Camera controls: orbit (left drag), pan (right drag), zoom (scroll/pinch)
        scnView.cameraControlConfiguration.allowsTranslation = true
        scnView.cameraControlConfiguration.rotationSensitivity = 0.5
        scnView.defaultCameraController.interactionMode = .orbitTurntable

        // Default camera positioned to frame the model
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 45
        camera.zNear = 0.1
        camera.zFar = 10000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 100, 250)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Screenshot export
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.exportScreenshot(_:)),
            name: .stepExportScreenshot,
            object: nil
        )
        context.coordinator.scnView = scnView

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        if scnView.scene !== scene {
            scnView.scene = scene
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        weak var scnView: SCNView?

        @objc func exportScreenshot(_ notification: Notification) {
            guard let view = scnView else { return }
            let image = view.snapshot()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "step_screenshot.png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }
}
#endif
