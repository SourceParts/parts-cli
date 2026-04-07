#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GerberViewerView: View {
    let filePaths: [String]
    @State private var renderedImage: NSImage?
    @State private var isRendering = false
    @State private var error: String?
    @State private var disabledLayers: Set<Int> = []

    // Zoom state (driven by NSScrollView magnification)
    @State private var zoomLevel: CGFloat = 1.0

    // Per-layer color and alpha
    @State private var layerColors: [Int: Color] = [:]
    @State private var layerAlpha: [Int: Double] = [:]

    // Board info from --info
    @State private var boardBounds: GerberBounds?

    // Coordinates and measurement
    @State private var mouseCoord: CGPoint?
    @State private var measureMode = false
    @State private var measureA: CGPoint?
    @State private var measureB: CGPoint?
    @State private var coordinateUnit: CoordinateUnit = .mm

    // Debounced render — avoids re-rendering on every color/alpha drag
    @State private var renderWorkItem: DispatchWorkItem?

    private static let defaultColors: [Color] = [.red, .green, .yellow, .blue, .purple, .cyan, .orange, .pink]

    private func colorFor(_ index: Int) -> Color {
        layerColors[index] ?? Self.defaultColors[index % Self.defaultColors.count]
    }

    private func alphaFor(_ index: Int) -> Double {
        layerAlpha[index] ?? 1.0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(Color.accentColor)
                Text("Gerber Viewer")
                    .font(.headline)
                Spacer()

                if isRendering {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Rendering...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 20)

                // Zoom controls
                Button(action: { zoomLevel = max(0.1, zoomLevel * 0.8) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom out")
                .keyboardShortcut("-", modifiers: [.command])

                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40)

                Button(action: { zoomLevel = min(10.0, zoomLevel * 1.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in")
                .keyboardShortcut("+", modifiers: [.command])

                Button(action: { zoomLevel = 0 }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit to window")

                Divider()
                    .frame(height: 20)

                // Measure tool
                Button(action: {
                    measureMode.toggle()
                    if !measureMode { measureA = nil; measureB = nil }
                }) {
                    Image(systemName: measureMode ? "ruler.fill" : "ruler")
                }
                .help(measureMode ? "Exit measure mode" : "Measure distance")
                .foregroundStyle(measureMode ? Color.yellow : Color.primary)

                Divider()
                    .frame(height: 20)

                // Export
                Menu {
                    Button("Export PDF...") { exportGerbv(format: "pdf") }
                    Button("Export SVG...") { exportGerbv(format: "svg") }
                    Divider()
                    Button("Save PNG...") {
                        if let img = renderedImage { saveImage(img) }
                    }
                    .disabled(renderedImage == nil)
                    Button("Copy Image") {
                        if let img = renderedImage {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                        }
                    }
                    .disabled(renderedImage == nil)
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
                // Image view with zoom
                if let img = renderedImage {
                    ZoomableImageView(
                        image: img,
                        zoomLevel: $zoomLevel,
                        boardBounds: boardBounds,
                        mouseCoord: $mouseCoord,
                        measureMode: measureMode,
                        measureA: $measureA,
                        measureB: $measureB
                    )
                    .contextMenu {
                        Button("Copy Image") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                        }
                        Button("Save PNG...") {
                            saveImage(img)
                        }
                    }
                } else if let err = error {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { render() }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack {
                        Spacer()
                        ProgressView("Rendering Gerber layers...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

                // Layer list with color picker and alpha
                VStack(alignment: .leading, spacing: 0) {
                    Text("Layers (\(filePaths.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filePaths.enumerated()), id: \.offset) { index, path in
                                let name = URL(fileURLWithPath: path).lastPathComponent
                                let disabled = disabledLayers.contains(index)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        // Visibility toggle
                                        Button(action: {
                                            if disabledLayers.contains(index) {
                                                disabledLayers.remove(index)
                                            } else {
                                                disabledLayers.insert(index)
                                            }
                                            render()
                                        }) {
                                            Image(systemName: disabled ? "eye.slash" : "eye.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(disabled ? .gray : colorFor(index))
                                                .frame(width: 16, height: 16)
                                        }
                                        .buttonStyle(.plain)
                                        .help(disabled ? "Show layer" : "Hide layer")

                                        // Color swatch + picker
                                        ColorPicker("", selection: Binding(
                                            get: { colorFor(index) },
                                            set: { layerColors[index] = $0; debouncedRender() }
                                        ), supportsOpacity: false)
                                        .labelsHidden()
                                        .frame(width: 24, height: 18)
                                        .disabled(disabled)
                                        .opacity(disabled ? 0.3 : 1.0)
                                        .help("Layer color — click to change")

                                        Text(name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .foregroundStyle(disabled ? .tertiary : .primary)
                                        Spacer()

                                        // Alpha percentage
                                        if !disabled {
                                            Text("\(Int(alphaFor(index) * 100))%")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 30, alignment: .trailing)
                                        }
                                    }

                                    // Alpha slider — only when enabled
                                    if !disabled {
                                        Slider(value: Binding(
                                            get: { alphaFor(index) },
                                            set: { layerAlpha[index] = $0; debouncedRender() }
                                        ), in: 0.05...1.0)
                                        .controlSize(.mini)
                                        .tint(colorFor(index))
                                        .padding(.leading, 22)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .contextMenu {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.selectFile(filePaths[index], inFileViewerRootedAtPath: "")
                                    }
                                    Divider()
                                    Button("Solo This Layer") {
                                        disabledLayers = Set(filePaths.indices.filter { $0 != index })
                                        render()
                                    }
                                    Button("Reset Color") {
                                        layerColors.removeValue(forKey: index)
                                        layerAlpha.removeValue(forKey: index)
                                        render()
                                    }
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            Button("Enable All") {
                                disabledLayers.removeAll()
                                render()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                            .padding(.horizontal, 10)
                            .disabled(disabledLayers.isEmpty)

                            Button("Reset Colors") {
                                layerColors.removeAll()
                                layerAlpha.removeAll()
                                render()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                            .padding(.horizontal, 10)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(width: 220)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            // Status bar
            HStack(spacing: 12) {
                if let coord = mouseCoord {
                    Text(String(format: "X: %.3f  Y: %.3f %@",
                                coord.x * coordinateUnit.fromInch,
                                coord.y * coordinateUnit.fromInch,
                                coordinateUnit.suffix))
                }

                if let a = measureA, let b = measureB {
                    let dx = (b.x - a.x) * coordinateUnit.fromInch
                    let dy = (b.y - a.y) * coordinateUnit.fromInch
                    let dist = sqrt(dx * dx + dy * dy)
                    Text(String(format: "Dist: %.3f %@", dist, coordinateUnit.suffix))
                        .foregroundStyle(.yellow)
                } else if measureMode {
                    Text(measureA == nil ? "Click first point" : "Click second point")
                        .foregroundStyle(.yellow)
                }

                Spacer()

                if let bounds = boardBounds {
                    let w = (bounds.right - bounds.left) * coordinateUnit.fromInch
                    let h = (bounds.top - bounds.bottom) * coordinateUnit.fromInch
                    Text(String(format: "%.1f x %.1f %@", w, h, coordinateUnit.suffix))
                }

                Text("\(filePaths.count - disabledLayers.count)/\(filePaths.count) layers")

                Picker("", selection: $coordinateUnit) {
                    ForEach(CoordinateUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear { render() }
    }

    // MARK: - Debounced Render

    /// Schedule a render after a short delay. Cancels any pending render.
    /// Use for continuous adjustments (color picker, alpha slider) to avoid
    /// firing a subprocess on every drag tick.
    private func debouncedRender(delay: TimeInterval = 0.4) {
        renderWorkItem?.cancel()
        let item = DispatchWorkItem { [self] in render() }
        renderWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Render

    private func render() {
        isRendering = true
        error = nil

        // Build layer index mapping: which original indices are enabled
        let enabledIndices = filePaths.indices.filter { !disabledLayers.contains($0) }
        let paths = enabledIndices.map { filePaths[$0] }

        Task {
            do {
                let result = try await renderGerber(paths: paths, enabledIndices: enabledIndices)
                await MainActor.run {
                    renderedImage = result.image
                    boardBounds = result.bounds
                    isRendering = false
                    zoomLevel = 0
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isRendering = false
                }
            }
        }
    }

    private struct RenderResult {
        let image: NSImage
        let bounds: GerberBounds?
    }

    private func renderGerber(paths: [String], enabledIndices: [Int]) async throws -> RenderResult {
        let renderTool = findGerbvRender()
        guard let tool = renderTool else {
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "gerbv-render not found.\nInstall with: brew install gerbv\nThen build tools/gerbv-render.c"])
        }

        let outputPath = NSTemporaryDirectory() + "parts_gerber_\(UUID().uuidString).png"
        var args = [outputPath, "2400", "1600", "--bg", "000000", "--info"]

        // Add per-layer color and alpha overrides
        for (renderIdx, origIdx) in enabledIndices.enumerated() {
            if let color = layerColors[origIdx] {
                let hex = colorToHex(color)
                args.append(contentsOf: ["--color", "\(renderIdx)", hex])
            }
            if let alpha = layerAlpha[origIdx] {
                let alphaVal = Int(alpha * 65535)
                args.append(contentsOf: ["--alpha", "\(renderIdx)", "\(alphaVal)"])
            }
        }

        args.append(contentsOf: paths)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        // Parse board bounds from stderr
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        let bounds = parseInfoJSON(stderrStr)

        guard process.terminationStatus == 0,
              let img = NSImage(contentsOfFile: outputPath) else {
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: stderrStr.isEmpty ? "Render failed" : stderrStr])
        }

        try? FileManager.default.removeItem(atPath: outputPath)
        return RenderResult(image: img, bounds: bounds)
    }

    // MARK: - Color Helpers

    private func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "%02x%02x%02x", r, g, b)
    }

    // MARK: - Info Parsing

    private func parseInfoJSON(_ stderr: String) -> GerberBounds? {
        // Find JSON line in stderr (may have warnings before it)
        for line in stderr.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return GerberBounds(
                left: json["left"] as? Double ?? 0,
                right: json["right"] as? Double ?? 0,
                bottom: json["bottom"] as? Double ?? 0,
                top: json["top"] as? Double ?? 0
            )
        }
        return nil
    }

    // MARK: - Export via gerbv CLI

    private func exportGerbv(format: String) {
        let gerbvPath = "/opt/homebrew/bin/gerbv"
        guard FileManager.default.fileExists(atPath: gerbvPath) else { return }

        let contentType: UTType = format == "pdf" ? .pdf : .svg
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "gerber_export.\(format)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var args = ["--export=\(format)", "--output=\(url.path)", "--background=#000000"]
        // gerbv expects -f COLOR before each file
        for (i, path) in filePaths.enumerated() {
            if disabledLayers.contains(i) { continue }
            let hex = colorToHex(colorFor(i))
            let alpha = String(format: "%02x", Int(alphaFor(i) * 255))
            args.append("-f")
            args.append("#\(hex)\(alpha)")
            args.append(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gerbvPath)
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Helpers

    private func findGerbvRender() -> String? {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/gerbv-render",
            "/opt/homebrew/bin/gerbv-render",
            "/usr/local/bin/gerbv-render",
        ]
        return paths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func saveImage(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "gerber_render.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }
}

// MARK: - Board Bounds

typealias GerberBounds = GerbvRenderer.GerberBounds

// MARK: - Draggable Scroll View

/// NSScrollView subclass that supports click-drag panning.
/// When measureMode is true, clicks report coordinates instead of panning.
class DraggableScrollView: NSScrollView {
    private var isPanning = false
    private var panOrigin: NSPoint = .zero
    var measureMode = false
    var onMeasureClick: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if measureMode, let docView = documentView {
            let viewPoint = docView.convert(event.locationInWindow, from: nil)
            onMeasureClick?(viewPoint)
            return
        }
        isPanning = true
        panOrigin = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPanning else { return }
        let current = event.locationInWindow
        let dx = current.x - panOrigin.x
        let dy = current.y - panOrigin.y
        panOrigin = current

        var newOrigin = contentView.bounds.origin
        newOrigin.x -= dx
        newOrigin.y -= dy
        contentView.scroll(to: newOrigin)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            NSCursor.pop()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: measureMode ? .crosshair : .openHand)
    }
}

// MARK: - Tracking Image View

/// NSImageView subclass that tracks mouse movement and reports position.
class TrackingImageView: NSImageView {
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

// MARK: - Zoomable Image View (NSScrollView-based)

/// NSViewRepresentable wrapping NSScrollView with magnification support.
/// Provides native macOS zoom (Cmd+scroll, trackpad pinch), click-drag pan,
/// mouse coordinate tracking, and measurement tool.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoomLevel: CGFloat
    var boardBounds: GerberBounds?
    @Binding var mouseCoord: CGPoint?
    var measureMode: Bool
    @Binding var measureA: CGPoint?
    @Binding var measureB: CGPoint?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = DraggableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 10.0
        scrollView.backgroundColor = .black
        scrollView.drawsBackground = true
        scrollView.autohidesScrollers = true

        let imageView = TrackingImageView()
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.frame = NSRect(origin: .zero, size: image.size)

        // Mouse tracking → board coordinates
        let coordinator = context.coordinator
        imageView.onMouseMoved = { point in
            coordinator.handleMouseMoved(point)
        }
        imageView.onMouseExited = {
            DispatchQueue.main.async { coordinator.parent.mouseCoord = nil }
        }

        // Measure clicks
        scrollView.onMeasureClick = { point in
            coordinator.handleMeasureClick(point)
        }

        scrollView.documentView = imageView
        context.coordinator.scrollView = scrollView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationDidChange(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            context.coordinator.fitToWindow(scrollView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let imageView = scrollView.documentView as? TrackingImageView, imageView.image !== image {
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image.size)
        }

        // Sync measure mode to scroll view
        if let dsv = scrollView as? DraggableScrollView {
            if dsv.measureMode != measureMode {
                dsv.measureMode = measureMode
                scrollView.window?.invalidateCursorRects(for: scrollView)
            }
        }

        if zoomLevel == 0 {
            context.coordinator.fitToWindow(scrollView)
        } else if abs(scrollView.magnification - zoomLevel) > 0.01 {
            scrollView.magnification = zoomLevel
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ZoomableImageView
        weak var scrollView: NSScrollView?

        init(_ parent: ZoomableImageView) {
            self.parent = parent
        }

        @objc func magnificationDidChange(_ notification: Notification) {
            guard let sv = notification.object as? NSScrollView else { return }
            DispatchQueue.main.async {
                self.parent.zoomLevel = sv.magnification
            }
        }

        func fitToWindow(_ scrollView: NSScrollView) {
            let viewSize = scrollView.bounds.size
            let imageSize = parent.image.size
            guard viewSize.width > 0, viewSize.height > 0,
                  imageSize.width > 0, imageSize.height > 0 else { return }

            let scaleX = viewSize.width / imageSize.width
            let scaleY = viewSize.height / imageSize.height
            let fitScale = min(scaleX, scaleY)
            scrollView.magnification = fitScale
            DispatchQueue.main.async {
                self.parent.zoomLevel = fitScale
            }
        }

        /// Convert pixel position in the image view to board coordinates (inches).
        private func pixelToBoardCoord(_ point: NSPoint) -> CGPoint? {
            guard let bounds = parent.boardBounds else { return nil }
            let imgW = parent.image.size.width
            let imgH = parent.image.size.height
            guard imgW > 0, imgH > 0 else { return nil }

            let boardX = bounds.left + (Double(point.x) / Double(imgW)) * (bounds.right - bounds.left)
            // Y is inverted: top of image = top of board
            let boardY = bounds.top - (Double(point.y) / Double(imgH)) * (bounds.top - bounds.bottom)
            return CGPoint(x: boardX, y: boardY)
        }

        func handleMouseMoved(_ point: NSPoint) {
            guard let coord = pixelToBoardCoord(point) else { return }
            DispatchQueue.main.async {
                self.parent.mouseCoord = coord
            }
        }

        func handleMeasureClick(_ point: NSPoint) {
            guard let coord = pixelToBoardCoord(point) else { return }
            DispatchQueue.main.async {
                if self.parent.measureA == nil {
                    self.parent.measureA = coord
                    self.parent.measureB = nil
                } else if self.parent.measureB == nil {
                    self.parent.measureB = coord
                } else {
                    // Reset: start new measurement
                    self.parent.measureA = coord
                    self.parent.measureB = nil
                }
            }
        }
    }
}
#endif
