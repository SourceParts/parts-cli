#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Board Bounds Protocol

/// Protocol for any type that provides board bounding box in inches.
/// Conformed to by both GerberBounds (GerberViewerView) and GerbvRenderer.GerberBounds.
protocol BoardBoundsProviding {
    var left: Double { get }
    var right: Double { get }
    var bottom: Double { get }
    var top: Double { get }
}

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
    var boundsLeft: Double
    var boundsRight: Double
    var boundsBottom: Double
    var boundsTop: Double
    var hasBounds: Bool
    @Binding var mouseCoord: CGPoint?
    var measureMode: Bool
    @Binding var measureA: CGPoint?
    @Binding var measureB: CGPoint?

    /// Convenience initializer for types conforming to BoardBoundsProviding.
    init(image: NSImage, zoomLevel: Binding<CGFloat>,
         boardBounds: (any BoardBoundsProviding)?,
         mouseCoord: Binding<CGPoint?>,
         measureMode: Bool,
         measureA: Binding<CGPoint?>,
         measureB: Binding<CGPoint?>) {
        self.image = image
        self._zoomLevel = zoomLevel
        self.boundsLeft = boardBounds?.left ?? 0
        self.boundsRight = boardBounds?.right ?? 0
        self.boundsBottom = boardBounds?.bottom ?? 0
        self.boundsTop = boardBounds?.top ?? 0
        self.hasBounds = boardBounds != nil
        self._mouseCoord = mouseCoord
        self.measureMode = measureMode
        self._measureA = measureA
        self._measureB = measureB
    }

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

        // Mouse tracking -> board coordinates
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
            guard parent.hasBounds else { return nil }
            let imgW = parent.image.size.width
            let imgH = parent.image.size.height
            guard imgW > 0, imgH > 0 else { return nil }

            let boardX = parent.boundsLeft + (Double(point.x) / Double(imgW)) * (parent.boundsRight - parent.boundsLeft)
            // Y is inverted: top of image = top of board
            let boardY = parent.boundsTop - (Double(point.y) / Double(imgH)) * (parent.boundsTop - parent.boundsBottom)
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
