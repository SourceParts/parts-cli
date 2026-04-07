#if os(macOS)
import Foundation
import AppKit
import CGerbv

/// Native libgerbv renderer — renders Gerber/Excellon layers directly to NSImage in-process.
class GerbvRenderer {

    struct LayerConfig {
        let path: String
        let color: NSColor
        let alpha: Double  // 0.0–1.0
        let isVisible: Bool
    }

    struct RenderResult {
        let image: NSImage
        let bounds: GerberBounds
        let layerCount: Int
    }

    struct GerberBounds {
        let left: Double
        let right: Double
        let bottom: Double
        let top: Double

        var widthInches: Double { right - left }
        var heightInches: Double { top - bottom }
        var widthMM: Double { widthInches * 25.4 }
        var heightMM: Double { heightInches * 25.4 }
    }

    private let renderQueue = DispatchQueue(label: "com.sourceparts.gerbv.render")

    /// Render layers to an NSImage.
    func render(layers: [LayerConfig], width: Int, height: Int,
                backgroundColor: NSColor = NSColor.black) -> RenderResult? {
        renderQueue.sync {
            _render(layers: layers, width: width, height: height, backgroundColor: backgroundColor)
        }
    }

    /// Get bounding box for a set of Gerber files.
    func getBounds(files: [String]) -> GerberBounds? {
        renderQueue.sync {
            guard let project = gerbv_create_project() else { return nil }
            defer { gerbv_destroy_project(project) }

            for path in files {
                gerbv_open_layer_from_filename(project, path)
            }

            var bbox = gerbv_render_size_t()
            gerbv_render_get_boundingbox(project, &bbox)

            return GerberBounds(left: bbox.left, right: bbox.right,
                                bottom: bbox.bottom, top: bbox.top)
        }
    }

    /// Render to a PNG file.
    func renderToPNG(layers: [LayerConfig], width: Int, height: Int,
                     outputPath: String, backgroundColor: NSColor = NSColor.black) -> Bool {
        return renderQueue.sync { () -> Bool in
            guard let project = gerbv_create_project() else { return false }
            defer { gerbv_destroy_project(project) }

            configureProject(project, layers: layers, backgroundColor: backgroundColor)

            gerbv_export_png_file_from_project_autoscaled(
                project, Int32(width), Int32(height), outputPath
            )

            return FileManager.default.fileExists(atPath: outputPath)
        }
    }

    // MARK: - Private

    private func _render(layers: [LayerConfig], width: Int, height: Int,
                         backgroundColor: NSColor) -> RenderResult? {
        guard let project = gerbv_create_project() else { return nil }
        defer { gerbv_destroy_project(project) }

        let loadedCount = configureProject(project, layers: layers, backgroundColor: backgroundColor)
        guard loadedCount > 0 else { return nil }

        var bbox = gerbv_render_size_t()
        gerbv_render_get_boundingbox(project, &bbox)
        let bounds = GerberBounds(left: bbox.left, right: bbox.right,
                                  bottom: bbox.bottom, top: bbox.top)

        let tempPath = NSTemporaryDirectory() + "gerbv_render_\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        gerbv_export_png_file_from_project_autoscaled(
            project, Int32(width), Int32(height), tempPath
        )

        guard let image = NSImage(contentsOfFile: tempPath) else { return nil }
        return RenderResult(image: image, bounds: bounds, layerCount: loadedCount)
    }

    @discardableResult
    private func configureProject(_ project: UnsafeMutablePointer<gerbv_project_t>,
                                  layers: [LayerConfig],
                                  backgroundColor: NSColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        backgroundColor.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        project.pointee.background.red = guint16(r * 65535)
        project.pointee.background.green = guint16(g * 65535)
        project.pointee.background.blue = guint16(b * 65535)

        var loadedCount = 0
        for (i, layer) in layers.enumerated() {
            gerbv_open_layer_from_filename(project, layer.path)

            // Access file array — gerbv stores files as file[0], file[1], etc.
            guard let fileInfo = project.pointee.file.advanced(by: i).pointee else { continue }
            guard fileInfo.pointee.image != nil else { continue }

            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
            layer.color.usingColorSpace(.sRGB)?.getRed(&lr, green: &lg, blue: &lb, alpha: nil)
            fileInfo.pointee.color.red = guint16(lr * 65535)
            fileInfo.pointee.color.green = guint16(lg * 65535)
            fileInfo.pointee.color.blue = guint16(lb * 65535)

            fileInfo.pointee.alpha = guint16(layer.alpha * 65535)
            fileInfo.pointee.isVisible = layer.isVisible ? 1 : 0

            loadedCount += 1
        }

        return loadedCount
    }
}
#endif
