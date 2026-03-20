import SwiftUI
import PDFKit

struct PDFViewerView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int

    func makeNSView(context: Context) -> ClickToFocusPDFView {
        let pdfView = ClickToFocusPDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(white: 0.9, alpha: 1.0)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ pdfView: ClickToFocusPDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
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
    }
}

/// PDFView that only takes focus when the user explicitly clicks on it.
class ClickToFocusPDFView: PDFView {
    private var userClicked = false

    override var acceptsFirstResponder: Bool {
        return userClicked
    }

    override func becomeFirstResponder() -> Bool {
        guard userClicked else { return false }
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        userClicked = true
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        // Reset after a tick so programmatic focus grabs are blocked again
        DispatchQueue.main.async { self.userClicked = false }
    }
}
