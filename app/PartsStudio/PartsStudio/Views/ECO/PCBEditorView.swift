#if os(macOS)
import SwiftUI

struct PCBEditorView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var versionStore = PCBVersionStore()
    @State private var renderedImage: NSImage?
    @State private var isRendering = false
    @State private var bounds: GerbvRenderer.GerberBounds?
    @State private var selectedVersionId: String = "v3"

    private let renderer = GerbvRenderer()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                // Main viewport
                ZStack {
                    Color.black
                    if let img = renderedImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if isRendering {
                        ProgressView("Rendering PCB...")
                            .foregroundStyle(.white)
                    } else {
                        Text("Select a PCB version to begin")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 500)

                // Inspector panel
                inspectorPanel
                    .frame(width: 260)
            }

            Divider()
            statusBar
        }
        .onAppear { selectVersion(selectedVersionId) }
        .onChange(of: selectedVersionId) { selectVersion(selectedVersionId) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(Color.accentColor)
            Text("PCB Editor")
                .font(.headline)

            Divider().frame(height: 20)

            // Version picker
            Picker("", selection: $selectedVersionId) {
                ForEach(versionStore.versions) { v in
                    Text(v.name).tag(v.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 250)

            if isRendering {
                ProgressView().scaleEffect(0.7)
            }

            Spacer()

            if let v = currentVersion {
                Text("\(v.layerCount)L")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(v.layerCount >= 10 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundStyle(v.layerCount >= 10 ? .green : .orange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Button(action: { renderCurrentVersion() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Re-render")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let version = currentVersion {
                // Stackup header
                HStack {
                    Text("Stackup")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(version.copperLayers.count) copper")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()

                // Stackup visualization
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Visual stackup bars
                        VStack(spacing: 1) {
                            ForEach(version.copperLayers) { layer in
                                StackupBar(layer: layer, onToggle: { renderCurrentVersion() })
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        Divider()

                        // Full layer list
                        Text("Layers (\(version.layers.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        ForEach(version.layers) { layer in
                            PCBLayerRow(layer: layer, onChanged: { debouncedRender() })
                        }

                        Divider().padding(.vertical, 4)

                        HStack(spacing: 8) {
                            Button("Show All") {
                                version.layers.forEach { $0.isVisible = true }
                                renderCurrentVersion()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)

                            Button("Copper Only") {
                                version.layers.forEach {
                                    $0.isVisible = ($0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper)
                                }
                                renderCurrentVersion()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)

                            Button("Reset") {
                                version.layers.forEach { $0.isVisible = true; $0.alpha = 1.0; $0.color = $0.type.defaultColor }
                                renderCurrentVersion()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                        }
                        .padding(.horizontal, 10)

                        // Board info
                        if let b = bounds {
                            Divider().padding(.vertical, 4)
                            DisclosureGroup("Board Info") {
                                VStack(alignment: .leading, spacing: 3) {
                                    infoRow("Size", String(format: "%.2f x %.2f mm", b.widthMM, b.heightMM))
                                    infoRow("Layers", "\(version.layerCount) copper")
                                    infoRow("Files", "\(version.layers.count) total")
                                    infoRow("Version", version.shortName)
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No PCB version selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            if let b = bounds {
                Text(String(format: "%.2f x %.2f mm", b.widthMM, b.heightMM))
            }
            if let v = currentVersion {
                Text("\(v.layers.filter(\.isVisible).count)/\(v.layers.count) layers")
            }
            Spacer()
            if let v = currentVersion {
                Text(v.name)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private var currentVersion: PCBVersion? {
        versionStore.versions.first(where: { $0.id == selectedVersionId })
    }

    private func selectVersion(_ id: String) {
        selectedVersionId = id
        renderCurrentVersion()
    }

    @State private var renderWorkItem: DispatchWorkItem?

    private func debouncedRender() {
        renderWorkItem?.cancel()
        let item = DispatchWorkItem { renderCurrentVersion() }
        renderWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func renderCurrentVersion() {
        guard let version = currentVersion else { return }
        isRendering = true

        let layerConfigs = version.layers.map { layer in
            GerbvRenderer.LayerConfig(
                path: layer.filePath,
                color: layer.color,
                alpha: layer.alpha,
                isVisible: layer.isVisible
            )
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = renderer.render(layers: layerConfigs, width: 2400, height: 1600)
            DispatchQueue.main.async {
                renderedImage = result?.image
                bounds = result?.bounds
                isRendering = false
            }
        }
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
            Spacer()
        }
    }
}

// MARK: - Stackup Bar

struct StackupBar: View {
    @ObservedObject var layer: PCBLayer
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { layer.isVisible.toggle(); onToggle() }) {
                Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 9))
                    .foregroundColor(layer.isVisible ? Color(layer.color) : .gray)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color(layer.color).opacity(layer.isVisible ? 1.0 : 0.2))
                .frame(height: 4)

            Text(layer.displayName)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(layer.isVisible ? .primary : .tertiary)
                .frame(width: 70, alignment: .leading)
        }
    }
}

// MARK: - Layer Row

struct PCBLayerRow: View {
    @ObservedObject var layer: PCBLayer
    var onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: { layer.isVisible.toggle(); onChanged() }) {
                    Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash")
                        .font(.system(size: 10))
                        .foregroundColor(layer.isVisible ? Color(layer.color) : .gray)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)

                ColorPicker("", selection: Binding(
                    get: { Color(layer.color) },
                    set: { layer.color = NSColor($0); onChanged() }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 20, height: 16)

                Image(systemName: layer.type.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(layer.type.defaultColor))
                    .frame(width: 12)

                Text(layer.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)

                Spacer()

                Text("\(Int(layer.alpha * 100))%")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if layer.isVisible {
                Slider(value: Binding(
                    get: { layer.alpha },
                    set: { layer.alpha = $0; onChanged() }
                ), in: 0.05...1.0)
                .controlSize(.mini)
                .tint(Color(layer.color))
                .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .contextMenu {
            Button("Solo") {
                // Hide all others, show only this one
            }
            Button("Hide Others") {
                // Toggle visibility
            }
        }
    }
}
#endif
