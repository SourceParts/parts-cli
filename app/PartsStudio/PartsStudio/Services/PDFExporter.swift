#if os(macOS)
import AppKit
import PDFKit

@MainActor
enum PDFExporter {

    // MARK: - Strip Metadata

    static func stripMetadata(from sourceDocument: PDFDocument?) {
        guard let sourceDocument else { return }

        // Capture existing metadata before stripping
        let oldAttrs = sourceDocument.documentAttributes ?? [:]
        let knownKeys: [(String, PDFDocumentAttribute)] = [
            ("Author", .authorAttribute),
            ("Title", .titleAttribute),
            ("Subject", .subjectAttribute),
            ("Creator", .creatorAttribute),
            ("Producer", .producerAttribute),
            ("Keywords", .keywordsAttribute),
            ("Creation Date", .creationDateAttribute),
            ("Modification Date", .modificationDateAttribute),
        ]
        var removed: [String] = []
        for (label, key) in knownKeys {
            if let value = oldAttrs[key], "\(value)" != "" {
                removed.append("\(label): \(value)")
            }
        }

        // Create a temporary copy so we don't mutate the in-view document
        guard let data = sourceDocument.dataRepresentation(),
              let cleanDoc = PDFDocument(data: data) else { return }

        cleanDoc.documentAttributes = [:]

        let panel = NSSavePanel()
        panel.title = "Save Clean PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "clean.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if cleanDoc.write(to: url) {
            let summary = removed.isEmpty
                ? "No metadata fields were present."
                : "Removed:\n" + removed.joined(separator: "\n")
            showConfirmation("Metadata stripped and saved to \(url.lastPathComponent)\n\n\(summary)")
        } else {
            showConfirmation("Failed to save the PDF.")
        }
    }

    // MARK: - Export with Redactions

    static func exportWithRedactions(from sourceDocument: PDFDocument?) {
        guard let sourceDocument else { return }

        guard let data = sourceDocument.dataRepresentation(),
              let exportDoc = PDFDocument(data: data) else { return }

        let dpi: CGFloat = 300
        var redactedPageCount = 0

        for pageIndex in 0..<exportDoc.pageCount {
            guard let page = exportDoc.page(at: pageIndex) else { continue }

            let hasRedactions = page.annotations.contains { annotation in
                annotation.type == "Square" && annotation.color == .black
            }

            guard hasRedactions else { continue }
            redactedPageCount += 1

            // Render the page (with annotations baked in) to a bitmap at 300 DPI
            let mediaBox = page.bounds(for: .mediaBox)
            let scale = dpi / 72.0
            let pixelWidth = Int(mediaBox.width * scale)
            let pixelHeight = Int(mediaBox.height * scale)

            let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
            image.lockFocus()

            guard let context = NSGraphicsContext.current?.cgContext else {
                image.unlockFocus()
                continue
            }

            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            context.scaleBy(x: scale, y: scale)

            // Draw the PDF page content plus annotations
            page.draw(with: .mediaBox, to: context)

            image.unlockFocus()

            // Create a new PDFPage from the rendered image
            guard let flatPage = PDFPage(image: image) else { continue }

            // Preserve the original media box dimensions
            flatPage.setBounds(mediaBox, for: .mediaBox)

            exportDoc.removePage(at: pageIndex)
            exportDoc.insert(flatPage, at: pageIndex)
        }

        // Strip metadata from the exported copy
        exportDoc.documentAttributes = [:]

        let panel = NSSavePanel()
        panel.title = "Export Redacted PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "redacted.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if exportDoc.write(to: url) {
            showConfirmation(
                "Redacted PDF saved to \(url.lastPathComponent)\n\n" +
                "\(redactedPageCount) of \(exportDoc.pageCount) page(s) flattened as 300 DPI images with redactions baked in.\n" +
                "Original text under redaction areas is no longer selectable or searchable.\n\n" +
                "Verify no sensitive data is recoverable before distribution."
            )
        } else {
            showConfirmation("Failed to save the PDF.")
        }
    }

    // MARK: - Export Annotations as JSON

    static func exportAnnotations(from store: AnnotationStore) {
        guard !store.annotations.isEmpty else {
            showConfirmation("No annotations to export.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Annotations"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "annotations.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try JSONEncoder.prettyPrinted.encode(store.annotations)
            try data.write(to: url, options: .atomic)
            showConfirmation("Exported \(store.annotations.count) annotation(s) to \(url.lastPathComponent)")
        } catch {
            showConfirmation("Failed to export: \(error.localizedDescription)")
        }
    }

    // MARK: - Export Labels as CSV

    static func exportLabels(from store: DataLabelStore) {
        guard !store.labels.isEmpty else {
            showConfirmation("No labels to export.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Labels"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "labels.csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "page,category,key,value,unit,x,y,width,height,created\n"
        for label in store.labels {
            let unit = label.unit ?? ""
            let escaped = { (s: String) -> String in
                s.contains(",") || s.contains("\"") ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
            }
            csv += "\(label.page),\(escaped(label.category)),\(escaped(label.key)),\(escaped(label.value)),\(escaped(unit)),\(label.x),\(label.y),\(label.width),\(label.height),\(label.created)\n"
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            showConfirmation("Exported \(store.labels.count) label(s) to \(url.lastPathComponent)")
        } catch {
            showConfirmation("Failed to export: \(error.localizedDescription)")
        }
    }

    // MARK: - Export Current Page as PNG

    static func exportPageAsPNG(from document: PDFDocument?, pageIndex: Int) {
        guard let document, let page = document.page(at: pageIndex) else {
            showConfirmation("No page to export.")
            return
        }

        let dpi: CGFloat = 300
        let mediaBox = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let pixelWidth = Int(mediaBox.width * scale)
        let pixelHeight = Int(mediaBox.height * scale)

        let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return
        }

        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            showConfirmation("Failed to render page.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Page as PNG"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "page-\(pageIndex + 1).png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try pngData.write(to: url, options: .atomic)
            showConfirmation("Page \(pageIndex + 1) exported at \(dpi) DPI to \(url.lastPathComponent)")
        } catch {
            showConfirmation("Failed to save: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func showConfirmation(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Done"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
#endif
