#if os(macOS)
import SwiftUI
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Coordinate Unit

enum CoordinateUnit: String, CaseIterable {
    case mm, mil, inch

    var suffix: String { rawValue }

    /// Conversion factor FROM mm TO this unit.
    var fromMM: Double {
        switch self {
        case .mm:   return 1.0
        case .mil:  return 1.0 / 0.0254   // 1 mm = ~39.37 mil
        case .inch: return 1.0 / 25.4      // 1 mm = ~0.03937 inch
        }
    }

    /// Conversion factor FROM inches TO this unit (used by Gerber viewer).
    var fromInch: Double {
        switch self {
        case .mm:   return 25.4
        case .mil:  return 1000.0
        case .inch: return 1.0
        }
    }
}

// MARK: - DXF Viewer View

struct DXFViewerView: View {
    let filePath: String

    @State private var document: DXFDocument?
    @State private var isLoading = true
    @State private var error: String?
    @State private var hiddenLayers: Set<String> = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var mouseCoord: CGPoint?
    @State private var coordinateUnit: CoordinateUnit = .mm
    @State private var measureMode = false
    @State private var measureA: CGPoint?
    @State private var measureB: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Toolbar
            HStack {
                Image(systemName: "square.on.square.intersection.dashed")
                    .foregroundStyle(Color.accentColor)
                Text("DXF Viewer")
                    .font(.headline)
                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 20)

                // Zoom controls
                Button(action: { zoomScale = max(0.1, zoomScale * 0.8) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom out")
                .keyboardShortcut("-", modifiers: [.command])

                Text("\(Int(zoomScale * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40)

                Button(action: { zoomScale = min(10.0, zoomScale * 1.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in")
                .keyboardShortcut("+", modifiers: [.command])

                Button(action: { zoomScale = 0 }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit to window")

                Divider()
                    .frame(height: 20)

                // Measure toggle
                Button(action: {
                    measureMode.toggle()
                    if !measureMode {
                        measureA = nil
                        measureB = nil
                    }
                }) {
                    Image(systemName: measureMode ? "ruler.fill" : "ruler")
                }
                .help(measureMode ? "Exit measure mode" : "Measure distance")
                .foregroundStyle(measureMode ? Color.yellow : Color.primary)

                Divider()
                    .frame(height: 20)

                // Export menu
                Menu {
                    Button("Export PNG...") { exportPNG() }
                    Button("Export PDF...") { exportPDF() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("Export")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HSplitView {
                // MARK: Canvas
                if let doc = document {
                    DXFCanvasRepresentable(
                        document: doc,
                        hiddenLayers: hiddenLayers,
                        zoomScale: $zoomScale,
                        mouseCoord: $mouseCoord,
                        measureMode: measureMode,
                        measureA: $measureA,
                        measureB: $measureB
                    )
                    .contextMenu {
                        Button("Copy to Clipboard") { copyCanvasToClipboard() }
                        Button("Export PNG...") { exportPNG() }
                    }
                } else if isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Parsing DXF file...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
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
                        Button("Retry") { loadFile() }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

                // MARK: Layer Sidebar
                VStack(alignment: .leading, spacing: 0) {
                    Text("Layers (\(document?.layers.count ?? 0))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if let doc = document {
                                ForEach(doc.sortedLayers, id: \.name) { layer in
                                    let isHidden = hiddenLayers.contains(layer.name)
                                    let (r, g, b) = aciColor(layer.color)
                                    let layerColor = Color(
                                        nsColor: NSColor(
                                            srgbRed: CGFloat(r),
                                            green: CGFloat(g),
                                            blue: CGFloat(b),
                                            alpha: 1
                                        )
                                    )

                                    HStack(spacing: 6) {
                                        Image(systemName: isHidden ? "eye.slash" : "eye")
                                            .font(.caption2)
                                            .foregroundColor(isHidden ? .gray : layerColor)
                                            .frame(width: 14)
                                        Circle()
                                            .fill(isHidden ? layerColor.opacity(0.2) : layerColor)
                                            .frame(width: 10, height: 10)
                                        Text(layer.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .foregroundStyle(isHidden ? .tertiary : .primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if hiddenLayers.contains(layer.name) {
                                            hiddenLayers.remove(layer.name)
                                        } else {
                                            hiddenLayers.insert(layer.name)
                                        }
                                    }
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            Button("Enable All") {
                                hiddenLayers.removeAll()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                            .padding(.horizontal, 10)
                            .disabled(hiddenLayers.isEmpty)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            // MARK: Status Bar
            HStack(spacing: 12) {
                // Mouse coordinates
                if let coord = mouseCoord {
                    let factor = coordinateUnit.fromMM
                    Text(String(
                        format: "X: %.3f  Y: %.3f %@",
                        coord.x * factor,
                        coord.y * factor,
                        coordinateUnit.suffix
                    ))
                } else {
                    Text("X: ---  Y: ---")
                        .foregroundStyle(.tertiary)
                }

                Divider()
                    .frame(height: 12)

                // Board dimensions
                if let doc = document {
                    let factor = coordinateUnit.fromMM
                    let w = doc.bounds.width * factor
                    let h = doc.bounds.height * factor
                    Text(String(
                        format: "%.1f x %.1f %@",
                        w, h,
                        coordinateUnit.suffix
                    ))
                    .foregroundStyle(.secondary)
                }

                // Measurement distance
                if let a = measureA, let b = measureB {
                    Divider()
                        .frame(height: 12)
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let dist = sqrt(dx * dx + dy * dy) * coordinateUnit.fromMM
                    Text(String(format: "D: %.3f %@", dist, coordinateUnit.suffix))
                        .foregroundStyle(.yellow)
                } else if measureMode {
                    Divider()
                        .frame(height: 12)
                    Text(measureA == nil ? "Click start point" : "Click end point")
                        .foregroundStyle(.yellow)
                }

                Spacer()

                // Entity/layer count
                if let doc = document {
                    Text("\(doc.entities.count) entities")
                        .foregroundStyle(.secondary)
                    Divider()
                        .frame(height: 12)
                    Text(doc.unitLabel)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 12)

                // Unit picker
                Picker("", selection: $coordinateUnit) {
                    ForEach(CoordinateUnit.allCases, id: \.self) { unit in
                        Text(unit.suffix).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task {
            loadFile()
        }
    }

    // MARK: - Load File

    private func loadFile() {
        isLoading = true
        error = nil
        document = nil

        Task {
            do {
                let parser = DXFParser()
                let doc = try parser.parse(contentsOf: URL(fileURLWithPath: filePath))
                await MainActor.run {
                    document = doc
                    isLoading = false
                    // Signal fit-to-window on first load
                    zoomScale = 0
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Export

    private func exportPNG() {
        guard document != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = URL(fileURLWithPath: filePath)
            .deletingPathExtension().lastPathComponent + "_export.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            NotificationCenter.default.post(
                name: .dxfExportPNG,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func exportPDF() {
        guard document != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = URL(fileURLWithPath: filePath)
            .deletingPathExtension().lastPathComponent + "_export.pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            NotificationCenter.default.post(
                name: .dxfExportPDF,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func copyCanvasToClipboard() {
        NotificationCenter.default.post(name: .dxfCopyToClipboard, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let dxfExportPNG = Notification.Name("dxfExportPNG")
    static let dxfExportPDF = Notification.Name("dxfExportPDF")
    static let dxfCopyToClipboard = Notification.Name("dxfCopyToClipboard")
}

// MARK: - DXF Canvas Representable

struct DXFCanvasRepresentable: NSViewRepresentable {
    let document: DXFDocument
    let hiddenLayers: Set<String>
    @Binding var zoomScale: CGFloat
    @Binding var mouseCoord: CGPoint?
    let measureMode: Bool
    @Binding var measureA: CGPoint?
    @Binding var measureB: CGPoint?

    func makeNSView(context: Context) -> DraggableScrollView {
        let scrollView = DraggableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 10.0
        scrollView.backgroundColor = .black
        scrollView.drawsBackground = true
        scrollView.autohidesScrollers = true

        let canvasView = DXFCanvasNSView(document: document)
        canvasView.hiddenLayers = hiddenLayers
        canvasView.measureMode = measureMode
        canvasView.measureA = measureA
        canvasView.measureB = measureB

        canvasView.onMouseMoved = { worldPoint in
            DispatchQueue.main.async {
                self.mouseCoord = worldPoint
            }
        }
        canvasView.onMeasureClick = { worldPoint in
            DispatchQueue.main.async {
                if self.measureA == nil {
                    self.measureA = worldPoint
                    self.measureB = nil
                } else {
                    self.measureB = worldPoint
                }
            }
        }

        // Size the canvas to fit the DXF content
        let scale: CGFloat = 10.0
        let margin: CGFloat = 50
        let w = document.bounds.width * scale + margin * 2
        let h = document.bounds.height * scale + margin * 2
        canvasView.frame = NSRect(x: 0, y: 0, width: max(w, 100), height: max(h, 100))

        scrollView.documentView = canvasView
        context.coordinator.scrollView = scrollView
        context.coordinator.canvasView = canvasView

        // Observe magnification
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationDidChange(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        // Observe export notifications
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleExportPNG(_:)),
            name: .dxfExportPNG,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleExportPDF(_:)),
            name: .dxfExportPDF,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleCopyToClipboard(_:)),
            name: .dxfCopyToClipboard,
            object: nil
        )

        // Fit to window on first display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            context.coordinator.fitToWindow(scrollView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: DraggableScrollView, context: Context) {
        guard let canvasView = scrollView.documentView as? DXFCanvasNSView else { return }

        // Update drawing properties
        var needsRedraw = false

        if canvasView.hiddenLayers != hiddenLayers {
            canvasView.hiddenLayers = hiddenLayers
            needsRedraw = true
        }
        if canvasView.measureMode != measureMode {
            canvasView.measureMode = measureMode
            needsRedraw = true
        }
        if canvasView.measureA != measureA {
            canvasView.measureA = measureA
            needsRedraw = true
        }
        if canvasView.measureB != measureB {
            canvasView.measureB = measureB
            needsRedraw = true
        }

        if needsRedraw {
            canvasView.needsDisplay = true
        }

        // Handle zoom level changes from toolbar
        if zoomScale == 0 {
            context.coordinator.fitToWindow(scrollView)
        } else if abs(scrollView.magnification - zoomScale) > 0.01 {
            scrollView.magnification = zoomScale
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: DXFCanvasRepresentable
        weak var scrollView: DraggableScrollView?
        weak var canvasView: DXFCanvasNSView?

        init(_ parent: DXFCanvasRepresentable) {
            self.parent = parent
        }

        @objc func magnificationDidChange(_ notification: Notification) {
            guard let sv = notification.object as? NSScrollView else { return }
            DispatchQueue.main.async {
                self.parent.zoomScale = sv.magnification
            }
        }

        func fitToWindow(_ scrollView: DraggableScrollView) {
            guard let docView = scrollView.documentView else { return }
            let viewSize = scrollView.bounds.size
            let canvasSize = docView.frame.size
            guard viewSize.width > 0, viewSize.height > 0,
                  canvasSize.width > 0, canvasSize.height > 0 else { return }

            let scaleX = viewSize.width / canvasSize.width
            let scaleY = viewSize.height / canvasSize.height
            let fitScale = min(scaleX, scaleY)
            scrollView.magnification = fitScale
            DispatchQueue.main.async {
                self.parent.zoomScale = fitScale
            }
        }

        @objc func handleExportPNG(_ notification: Notification) {
            guard let canvasView = canvasView,
                  let url = notification.userInfo?["url"] as? URL else { return }

            guard let bitmapRep = canvasView.bitmapImageRepForCachingDisplay(in: canvasView.bounds) else { return }
            canvasView.cacheDisplay(in: canvasView.bounds, to: bitmapRep)
            if let png = bitmapRep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }

        @objc func handleExportPDF(_ notification: Notification) {
            guard let canvasView = canvasView,
                  let url = notification.userInfo?["url"] as? URL else { return }

            let pdfData = canvasView.dataWithPDF(inside: canvasView.bounds)
            try? pdfData.write(to: url)
        }

        @objc func handleCopyToClipboard(_ notification: Notification) {
            guard let canvasView = canvasView else { return }
            guard let bitmapRep = canvasView.bitmapImageRepForCachingDisplay(in: canvasView.bounds) else { return }
            canvasView.cacheDisplay(in: canvasView.bounds, to: bitmapRep)
            let image = NSImage(size: canvasView.bounds.size)
            image.addRepresentation(bitmapRep)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - DXF Canvas NSView

class DXFCanvasNSView: NSView {

    // MARK: Properties

    let document: DXFDocument
    var hiddenLayers: Set<String> = []
    var measureMode: Bool = false
    var measureA: CGPoint?
    var measureB: CGPoint?

    /// Pixels per DXF unit in the base (unmagnified) view.
    private let worldScale: CGFloat = 10.0
    /// Margin in view pixels around the drawing.
    private let margin: CGFloat = 50

    /// Callback when mouse moves (world coordinates).
    var onMouseMoved: ((CGPoint) -> Void)?
    /// Callback when measure point clicked (world coordinates).
    var onMeasureClick: ((CGPoint) -> Void)?

    // MARK: Init

    init(document: DXFDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let worldPoint = viewToWorld(viewPoint)
        onMouseMoved?(worldPoint)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseMoved?(CGPoint(x: CGFloat.nan, y: CGFloat.nan))
    }

    override func mouseDown(with event: NSEvent) {
        guard measureMode else {
            super.mouseDown(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let worldPoint = viewToWorld(viewPoint)
        onMeasureClick?(worldPoint)
        needsDisplay = true
    }

    // MARK: Coordinate Conversion

    private func viewToWorld(_ viewPoint: CGPoint) -> CGPoint {
        let worldX = (viewPoint.x - margin) / worldScale + document.bounds.origin.x
        let worldY = (viewPoint.y - margin) / worldScale + document.bounds.origin.y
        return CGPoint(x: worldX, y: worldY)
    }

    // MARK: Drawing

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Black background
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(bounds)

        // Set up world-to-screen transform
        ctx.saveGState()
        ctx.translateBy(
            x: margin - document.bounds.origin.x * worldScale,
            y: margin - document.bounds.origin.y * worldScale
        )
        ctx.scaleBy(x: worldScale, y: worldScale)

        // Draw all entities
        for entity in document.entities {
            if hiddenLayers.contains(entity.layer) { continue }
            drawEntity(entity, in: ctx, depth: 0)
        }

        // Draw measurement overlay
        if let a = measureA {
            // Draw point A marker
            drawMeasurePoint(a, in: ctx)

            if let b = measureB {
                // Draw point B marker
                drawMeasurePoint(b, in: ctx)

                // Draw connecting line
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1))
                ctx.setLineWidth(0.15)
                ctx.setLineDash(phase: 0, lengths: [0.8, 0.4])
                ctx.move(to: a)
                ctx.addLine(to: b)
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }

        ctx.restoreGState()

        // Draw crosshair grid lines at edges (optional subtle reference)
        drawOriginMarker(in: ctx)
    }

    // MARK: - Entity Drawing

    private func drawEntity(_ entity: DXFEntity, in ctx: CGContext, depth: Int) {
        guard depth < 10 else { return }

        let (r, g, b) = resolveColor(entity)
        ctx.setStrokeColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.setLineWidth(0.1)

        switch entity.type {
        case .line(let start, let end):
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

        case .circle(let center, let radius):
            ctx.strokeEllipse(in: CGRect(
                x: center.x - CGFloat(radius),
                y: center.y - CGFloat(radius),
                width: CGFloat(radius) * 2,
                height: CGFloat(radius) * 2
            ))

        case .arc(let center, let radius, let startAngle, let endAngle):
            ctx.addArc(
                center: center,
                radius: CGFloat(radius),
                startAngle: CGFloat(startAngle * .pi / 180),
                endAngle: CGFloat(endAngle * .pi / 180),
                clockwise: false
            )
            ctx.strokePath()

        case .lwPolyline(let points, let closed):
            guard !points.isEmpty else { break }
            ctx.move(to: points[0])
            for i in 1..<points.count {
                ctx.addLine(to: points[i])
            }
            if closed { ctx.closePath() }
            ctx.strokePath()

        case .text(let pos, let height, let content, let rotation):
            ctx.saveGState()
            ctx.translateBy(x: pos.x, y: pos.y)
            if rotation != 0 {
                ctx.rotate(by: CGFloat(rotation * .pi / 180))
            }
            ctx.scaleBy(x: 1, y: -1)
            let fontSize = max(CGFloat(height * 0.8), 0.5)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
            ]
            NSString(string: content).draw(at: .zero, withAttributes: attrs)
            ctx.restoreGState()

        case .mtext(let pos, let height, let content, _):
            ctx.saveGState()
            ctx.translateBy(x: pos.x, y: pos.y)
            ctx.scaleBy(x: 1, y: -1)
            let fontSize = max(CGFloat(height * 0.8), 0.5)
            // Strip MTEXT formatting codes (e.g., \P for newline, {\fArial;...})
            let cleaned = stripMTextFormatting(content)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
            ]
            NSString(string: cleaned).draw(at: .zero, withAttributes: attrs)
            ctx.restoreGState()

        case .point(let pos):
            ctx.fillEllipse(in: CGRect(
                x: pos.x - 0.2,
                y: pos.y - 0.2,
                width: 0.4,
                height: 0.4
            ))

        case .dimension(let defPoint, let textMidpoint, let text):
            // Draw a line from definition point to text midpoint
            ctx.setLineDash(phase: 0, lengths: [0.5, 0.3])
            ctx.move(to: defPoint)
            ctx.addLine(to: textMidpoint)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])

            // Draw dimension text if present
            if !text.isEmpty {
                ctx.saveGState()
                ctx.translateBy(x: textMidpoint.x, y: textMidpoint.y)
                ctx.scaleBy(x: 1, y: -1)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 0.8),
                    .foregroundColor: NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
                ]
                NSString(string: text).draw(at: .zero, withAttributes: attrs)
                ctx.restoreGState()
            }

        case .insert(let name, let pos, let sx, let sy, let rot):
            if let block = document.blocks[name] {
                ctx.saveGState()
                ctx.translateBy(x: pos.x, y: pos.y)
                if rot != 0 {
                    ctx.rotate(by: CGFloat(rot * .pi / 180))
                }
                ctx.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
                ctx.translateBy(x: -block.basePoint.x, y: -block.basePoint.y)

                for blockEntity in block.entities {
                    if hiddenLayers.contains(blockEntity.layer) { continue }
                    drawEntity(blockEntity, in: ctx, depth: depth + 1)
                }
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Helpers

    /// Resolve ACI color for an entity. If entity color is 0 (BYLAYER), use the layer color.
    private func resolveColor(_ entity: DXFEntity) -> (CGFloat, CGFloat, CGFloat) {
        var colorIndex = entity.color
        if colorIndex == 0 {
            // BYLAYER — look up layer color
            if let layer = document.layers[entity.layer] {
                colorIndex = layer.color
            } else {
                colorIndex = 7
            }
        }
        let (r, g, b) = aciColor(colorIndex)
        return (CGFloat(r), CGFloat(g), CGFloat(b))
    }

    /// Draw a small crosshair marker for measurement points.
    private func drawMeasurePoint(_ point: CGPoint, in ctx: CGContext) {
        let size: CGFloat = 0.5
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1))
        ctx.setLineWidth(0.15)
        ctx.setLineDash(phase: 0, lengths: [])

        // Crosshair
        ctx.move(to: CGPoint(x: point.x - size, y: point.y))
        ctx.addLine(to: CGPoint(x: point.x + size, y: point.y))
        ctx.move(to: CGPoint(x: point.x, y: point.y - size))
        ctx.addLine(to: CGPoint(x: point.x, y: point.y + size))
        ctx.strokePath()

        // Small circle
        ctx.strokeEllipse(in: CGRect(
            x: point.x - size * 0.6,
            y: point.y - size * 0.6,
            width: size * 1.2,
            height: size * 1.2
        ))
    }

    /// Draw a subtle origin marker at the DXF origin (0,0) if visible.
    private func drawOriginMarker(in ctx: CGContext) {
        // Transform origin (0,0) to view coords
        let originX = margin + (0 - document.bounds.origin.x) * worldScale
        let originY = margin + (0 - document.bounds.origin.y) * worldScale

        // Only draw if origin is within the canvas bounds (with some padding)
        guard originX > -50 && originX < bounds.width + 50 &&
              originY > -50 && originY < bounds.height + 50 else { return }

        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.3, blue: 0.3, alpha: 0.6))
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [4, 4])

        // Horizontal line through origin
        ctx.move(to: CGPoint(x: 0, y: originY))
        ctx.addLine(to: CGPoint(x: bounds.width, y: originY))
        ctx.strokePath()

        // Vertical line through origin
        ctx.move(to: CGPoint(x: originX, y: 0))
        ctx.addLine(to: CGPoint(x: originX, y: bounds.height))
        ctx.strokePath()

        ctx.restoreGState()
    }

    /// Strip common MTEXT formatting codes for plain-text rendering.
    private func stripMTextFormatting(_ text: String) -> String {
        var result = text
        // Replace \P with newline
        result = result.replacingOccurrences(of: "\\P", with: "\n")
        // Remove font/style blocks like {\fArial|b0|i0;...}
        // Simple approach: remove content between { and the first ;, keep rest until }
        while let openRange = result.range(of: "{\\") {
            if let closeRange = result.range(of: "}", range: openRange.upperBound..<result.endIndex) {
                let inner = String(result[openRange.upperBound..<closeRange.lowerBound])
                // Keep text after the semicolon (if any)
                if let semiRange = inner.range(of: ";") {
                    let kept = String(inner[semiRange.upperBound...])
                    result.replaceSubrange(openRange.lowerBound...closeRange.lowerBound, with: kept)
                } else {
                    result.replaceSubrange(openRange.lowerBound...closeRange.lowerBound, with: inner)
                }
            } else {
                break
            }
        }
        // Remove remaining backslash codes like \A1;
        result = result.replacingOccurrences(
            of: "\\\\[A-Za-z][^;]*;",
            with: "",
            options: .regularExpression
        )
        return result
    }
}
#endif
