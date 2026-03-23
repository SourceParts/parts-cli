import SwiftUI
import AppKit

struct GerberViewerView: View {
    let filePaths: [String]
    @State private var renderedImage: NSImage?
    @State private var isRendering = false
    @State private var error: String?
    @State private var disabledLayers: Set<Int> = []

    // Zoom state (driven by NSScrollView magnification)
    @State private var zoomLevel: CGFloat = 1.0

    private var layerNames: [(Int, String, Color)] {
        let colors: [Color] = [.red, .green, .yellow, .blue, .purple, .cyan, .orange, .pink]
        return filePaths.enumerated().map { i, path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (i, name, colors[i % colors.count])
        }
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
                .help("Zoom out (Cmd+scroll down)")
                .keyboardShortcut("-", modifiers: [.command])

                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40)

                Button(action: { zoomLevel = min(10.0, zoomLevel * 1.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in (Cmd+scroll up)")
                .keyboardShortcut("+", modifiers: [.command])

                Button(action: { zoomLevel = 0 }) { // 0 signals "fit"
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit to window")
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
                        zoomLevel: $zoomLevel
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

                // Layer list
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
                            ForEach(layerNames, id: \.0) { index, name, color in
                                HStack(spacing: 6) {
                                    Image(systemName: disabledLayers.contains(index) ? "eye.slash" : "eye")
                                        .font(.caption2)
                                        .foregroundStyle(disabledLayers.contains(index) ? .tertiary : color)
                                        .frame(width: 14)
                                    Circle()
                                        .fill(disabledLayers.contains(index) ? color.opacity(0.2) : color)
                                        .frame(width: 10, height: 10)
                                    Text(name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(disabledLayers.contains(index) ? .tertiary : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if disabledLayers.contains(index) {
                                        disabledLayers.remove(index)
                                    } else {
                                        disabledLayers.insert(index)
                                    }
                                    render()
                                }
                                .contextMenu {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.selectFile(filePaths[index], inFileViewerRootedAtPath: "")
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

                            Button("Render Selected") {
                                render()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                            .padding(.horizontal, 10)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onAppear { render() }
    }

    // MARK: - Render

    private func render() {
        isRendering = true
        error = nil

        let paths = filePaths.enumerated().compactMap { i, path in
            disabledLayers.contains(i) ? nil : path
        }

        Task {
            do {
                let img = try await renderGerber(paths: paths)
                await MainActor.run {
                    renderedImage = img
                    isRendering = false
                    // Signal fit-to-window on first render
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

    private func renderGerber(paths: [String]) async throws -> NSImage {
        let renderTool = findGerbvRender()
        guard let tool = renderTool else {
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "gerbv-render not found.\nInstall with: brew install gerbv\nThen build tools/gerbv-render.c"])
        }

        let outputPath = NSTemporaryDirectory() + "parts_gerber_\(UUID().uuidString).png"
        var args = [outputPath, "2400", "1600", "--bg", "000000"]
        args.append(contentsOf: paths)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let img = NSImage(contentsOfFile: outputPath) else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: errStr])
        }

        try? FileManager.default.removeItem(atPath: outputPath)
        return img
    }

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

// MARK: - Draggable Scroll View

/// NSScrollView subclass that supports click-drag panning.
/// Click and drag with trackpad or mouse to pan the canvas.
class DraggableScrollView: NSScrollView {
    private var isPanning = false
    private var panOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
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
        isPanning = false
        NSCursor.pop()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Zoomable Image View (NSScrollView-based)

/// NSViewRepresentable wrapping NSScrollView with magnification support.
/// Provides native macOS zoom (Cmd+scroll, trackpad pinch) and click-drag pan.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoomLevel: CGFloat

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

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.frame = NSRect(origin: .zero, size: image.size)

        scrollView.documentView = imageView
        context.coordinator.scrollView = scrollView

        // Observe magnification changes to sync back to SwiftUI
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationDidChange(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        // Fit to window on first display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            context.coordinator.fitToWindow(scrollView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Update image if changed
        if let imageView = scrollView.documentView as? NSImageView, imageView.image !== image {
            imageView.image = image
            imageView.frame = NSRect(origin: .zero, size: image.size)
        }

        // Handle zoom level changes from toolbar buttons
        if zoomLevel == 0 {
            // Signal to fit to window
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
    }
}
