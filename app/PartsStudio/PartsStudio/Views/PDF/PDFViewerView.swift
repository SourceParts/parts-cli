#if os(macOS)
import SwiftUI
import PDFKit

extension Notification.Name {
    static let zoomIn = Notification.Name("partsStudioZoomIn")
    static let zoomOut = Notification.Name("partsStudioZoomOut")
    static let zoomFit = Notification.Name("partsStudioZoomFit")
    static let pdfSearchResult = Notification.Name("partsStudioPDFSearchResult")
}

struct PDFViewerView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    var toolMode: ToolMode = .view
    var annotationStore: AnnotationStore?
    var conversationStore: ConversationStore?
    var dataLabelStore: DataLabelStore?
    var onAnnotationAdded: (() -> Void)?
    var onCommentAdded: (() -> Void)?
    var onLabelAdded: (() -> Void)?

    func makeNSView(context: Context) -> AnnotatingPDFView {
        let pdfView = AnnotatingPDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(white: 0.9, alpha: 1.0)
        pdfView.coordinator = context.coordinator

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Zoom notifications
        NotificationCenter.default.addObserver(
            forName: .zoomIn, object: nil, queue: .main
        ) { _ in pdfView.zoomIn(nil) }

        NotificationCenter.default.addObserver(
            forName: .zoomOut, object: nil, queue: .main
        ) { _ in pdfView.zoomOut(nil) }

        NotificationCenter.default.addObserver(
            forName: .zoomFit, object: nil, queue: .main
        ) { _ in pdfView.autoScales = true }

        // Search result navigation — scroll to selection and highlight
        NotificationCenter.default.addObserver(
            forName: .pdfSearchResult, object: nil, queue: .main
        ) { notification in
            if let selection = notification.userInfo?["selection"] as? PDFSelection {
                pdfView.setCurrentSelection(selection, animate: true)
                pdfView.scrollSelectionToVisible(nil)
            }
        }

        return pdfView
    }

    func updateNSView(_ pdfView: AnnotatingPDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        pdfView.toolMode = toolMode
        pdfView.coordinator = context.coordinator

        // Update cursor based on tool mode
        if toolMode == .view {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
        }

        if let page = document.page(at: currentPage) {
            if pdfView.currentPage !== page {
                pdfView.go(to: page)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: PDFViewerView

        init(_ parent: PDFViewerView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let pageIndex = document.index(for: currentPage)
            if pageIndex != parent.currentPage {
                DispatchQueue.main.async {
                    self.parent.currentPage = pageIndex
                }
            }
        }

        func addAnnotation(type: AnnotationType, page: PDFPage, bounds: CGRect, text: String? = nil) {
            let doc = parent.document
            let pageIndex = doc.index(for: page)

            let annotation = DatasheetAnnotation(
                page: pageIndex,
                type: type,
                bounds: AnnotationBounds(rect: bounds),
                text: text,
                fontSize: type == .freeText ? 12 : nil,
                color: type == .highlight ? "#FFFF0080" : nil
            )

            // Add to PDFKit for immediate visual
            let pdfAnnotation = annotation.toPDFAnnotation()
            page.addAnnotation(pdfAnnotation)

            // Persist
            parent.annotationStore?.addAnnotation(annotation)
            DispatchQueue.main.async {
                self.parent.onAnnotationAdded?()
            }
        }

        func addComment(page: PDFPage, point: CGPoint, selectedText: String?) {
            let doc = parent.document
            let pageIndex = doc.index(for: page)

            parent.conversationStore?.addThread(
                page: pageIndex,
                anchorX: point.x,
                anchorY: point.y,
                text: selectedText != nil ? "Re: \"\(selectedText!)\"" : "New thread",
                selectedText: selectedText
            )
            DispatchQueue.main.async {
                self.parent.onCommentAdded?()
            }
        }
    }
}

/// PDFView subclass that handles annotation drawing based on tool mode.
class AnnotatingPDFView: PDFView {
    var toolMode: ToolMode = .view
    weak var coordinator: PDFViewerView.Coordinator?

    private var dragStart: NSPoint?
    private var dragPage: PDFPage?
    private var dragOverlay: NSView?
    private var userClicked = false

    // MARK: - Focus handling

    override var acceptsFirstResponder: Bool {
        return userClicked || toolMode == .view
    }

    override func becomeFirstResponder() -> Bool {
        guard userClicked || toolMode == .view else { return false }
        return super.becomeFirstResponder()
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        userClicked = true

        if toolMode == .view {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
            DispatchQueue.main.async { self.userClicked = false }
            return
        }

        // Get the click location in PDF page coordinates
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else {
            super.mouseDown(with: event)
            return
        }
        let pagePoint = convert(viewPoint, to: page)

        switch toolMode {
        case .text:
            handleTextClick(page: page, point: pagePoint)
        case .comment:
            // Grab any currently selected text from the PDF
            let selectedText = currentSelection?.string
            coordinator?.addComment(page: page, point: pagePoint, selectedText: selectedText)
            clearSelection()
        case .redact, .highlight, .label:
            // Start drag
            dragStart = pagePoint
            dragPage = page
            showDragOverlay(at: viewPoint)
        case .view:
            break
        }

        DispatchQueue.main.async { self.userClicked = false }
    }

    override func mouseDragged(with event: NSEvent) {
        if toolMode == .view {
            super.mouseDragged(with: event)
            return
        }

        guard dragStart != nil, let overlay = dragOverlay else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let startView = convert(event.locationInWindow, from: nil)

        // Update overlay rectangle
        let currentPoint = viewPoint
        let origin = NSPoint(
            x: min(overlay.frame.origin.x, currentPoint.x),
            y: min(overlay.frame.origin.y, currentPoint.y)
        )
        let size = NSSize(
            width: abs(currentPoint.x - overlay.frame.origin.x),
            height: abs(currentPoint.y - overlay.frame.origin.y)
        )

        // Simpler: track in view coords using the overlay
        if let superview = overlay.superview {
            let startInSuper = superview.convert(event.locationInWindow, from: nil)
            overlay.frame = NSRect(origin: overlay.frame.origin, size: NSSize(
                width: max(1, startInSuper.x - overlay.frame.origin.x),
                height: max(1, startInSuper.y - overlay.frame.origin.y)
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if toolMode == .view {
            super.mouseUp(with: event)
            return
        }

        defer {
            dragOverlay?.removeFromSuperview()
            dragOverlay = nil
            dragStart = nil
            dragPage = nil
        }

        guard let start = dragStart, let page = dragPage else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let endPoint = convert(viewPoint, to: page)

        // Build rect from start/end in PDF coordinates
        let rect = CGRect(
            x: min(start.x, endPoint.x),
            y: min(start.y, endPoint.y),
            width: abs(endPoint.x - start.x),
            height: abs(endPoint.y - start.y)
        )

        // Minimum size to avoid accidental clicks
        guard rect.width > 5, rect.height > 5 else { return }

        switch toolMode {
        case .redact:
            coordinator?.addAnnotation(type: .redaction, page: page, bounds: rect)
        case .highlight:
            coordinator?.addAnnotation(type: .highlight, page: page, bounds: rect)
        case .label:
            handleLabelCreation(page: page, rect: rect)
        default:
            break
        }
    }

    // MARK: - Text placement

    private func handleTextClick(page: PDFPage, point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "Add Text Annotation"
        alert.informativeText = "Enter the text to place on the page:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "Enter text..."
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = input.stringValue
            guard !text.isEmpty else { return }

            // Estimate bounds from text length
            let font = NSFont.systemFont(ofSize: 12)
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            let rect = CGRect(
                x: point.x,
                y: point.y - textSize.height,
                width: textSize.width + 12,
                height: textSize.height + 4
            )

            coordinator?.addAnnotation(type: .freeText, page: page, bounds: rect, text: text)
        }
    }

    // MARK: - Label creation

    private func handleLabelCreation(page: PDFPage, rect: CGRect) {
        let categories = ["pin", "voltage", "current", "package", "temperature", "frequency", "custom"]

        let alert = NSAlert()
        alert.messageText = "Add Data Label"
        alert.informativeText = "Annotate this region with structured data:"
        alert.addButton(withTitle: "Add Label")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))

        // Category dropdown
        let categoryLabel = NSTextField(labelWithString: "Category:")
        categoryLabel.frame = NSRect(x: 0, y: 112, width: 80, height: 20)
        container.addSubview(categoryLabel)

        let categoryPopup = NSPopUpButton(frame: NSRect(x: 85, y: 108, width: 230, height: 28))
        categoryPopup.addItems(withTitles: categories)
        container.addSubview(categoryPopup)

        // Key field
        let keyLabel = NSTextField(labelWithString: "Key:")
        keyLabel.frame = NSRect(x: 0, y: 80, width: 80, height: 20)
        container.addSubview(keyLabel)

        let keyField = NSTextField(frame: NSRect(x: 85, y: 78, width: 230, height: 24))
        keyField.placeholderString = "e.g. VDD, Pin 12, Max rating"
        container.addSubview(keyField)

        // Value field
        let valueLabel = NSTextField(labelWithString: "Value:")
        valueLabel.frame = NSRect(x: 0, y: 48, width: 80, height: 20)
        container.addSubview(valueLabel)

        let valueField = NSTextField(frame: NSRect(x: 85, y: 46, width: 230, height: 24))
        valueField.placeholderString = "e.g. 3.3V, GPIO, 125C"
        container.addSubview(valueField)

        // Unit field
        let unitLabel = NSTextField(labelWithString: "Unit (opt):")
        unitLabel.frame = NSRect(x: 0, y: 16, width: 80, height: 20)
        container.addSubview(unitLabel)

        let unitField = NSTextField(frame: NSRect(x: 85, y: 14, width: 230, height: 24))
        unitField.placeholderString = "e.g. V, A, MHz, C"
        container.addSubview(unitField)

        alert.accessoryView = container
        alert.window.initialFirstResponder = keyField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let key = keyField.stringValue
            let value = valueField.stringValue
            guard !key.isEmpty, !value.isEmpty else { return }

            let category = categories[categoryPopup.indexOfSelectedItem]
            let unit = unitField.stringValue.isEmpty ? nil : unitField.stringValue

            guard let doc = coordinator?.parent.document else { return }
            let pageIndex = doc.index(for: page)

            let dataLabel = DataLabel(
                page: pageIndex,
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.width,
                height: rect.height,
                category: category,
                key: key,
                value: value,
                unit: unit
            )

            // Add visual annotation to page
            let pdfAnnotation = dataLabel.toPDFAnnotation()
            page.addAnnotation(pdfAnnotation)

            // Persist via store
            coordinator?.parent.dataLabelStore?.addLabel(dataLabel)
            DispatchQueue.main.async {
                self.coordinator?.parent.onLabelAdded?()
            }
        }
    }

    // MARK: - Drag overlay

    private func showDragOverlay(at point: NSPoint) {
        let overlay = NSView(frame: NSRect(origin: point, size: NSSize(width: 1, height: 1)))
        overlay.wantsLayer = true

        switch toolMode {
        case .redact:
            overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
            overlay.layer?.borderColor = NSColor.black.cgColor
        case .label:
            overlay.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.15).cgColor
            overlay.layer?.borderColor = NSColor.systemTeal.cgColor
        default:
            overlay.layer?.backgroundColor = NSColor.yellow.withAlphaComponent(0.2).cgColor
            overlay.layer?.borderColor = NSColor.orange.cgColor
        }
        overlay.layer?.borderWidth = 1

        documentView?.superview?.addSubview(overlay)
        dragOverlay = overlay
    }

    // MARK: - Zoom (always allow)

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
    }

    // MARK: - Cursor

    override func cursorUpdate(with event: NSEvent) {
        if toolMode == .view {
            super.cursorUpdate(with: event)
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if toolMode != .view {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}
#endif
