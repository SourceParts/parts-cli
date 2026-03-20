import Foundation
import PDFKit

enum AnnotationType: String, Codable {
    case redaction
    case freeText
    case highlight
}

struct AnnotationBounds: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct DatasheetAnnotation: Codable, Identifiable {
    let id: String
    let page: Int
    let type: AnnotationType
    let bounds: AnnotationBounds
    var text: String?
    var fontSize: CGFloat?
    var color: String?
    let created: String

    init(page: Int, type: AnnotationType, bounds: AnnotationBounds, text: String? = nil, fontSize: CGFloat? = nil, color: String? = nil) {
        self.id = UUID().uuidString
        self.page = page
        self.type = type
        self.bounds = bounds
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.created = ISO8601DateFormatter().string(from: Date())
    }

    func toPDFAnnotation() -> PDFAnnotation {
        let rect = bounds.cgRect

        switch type {
        case .redaction:
            let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            annotation.color = .black
            annotation.interiorColor = .black
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
            return annotation

        case .freeText:
            let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            annotation.contents = text ?? ""
            annotation.font = NSFont.systemFont(ofSize: fontSize ?? 12)
            annotation.fontColor = NSColor(hex: color ?? "#FF0000") ?? .red
            annotation.color = .clear
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
            return annotation

        case .highlight:
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = NSColor(hex: color ?? "#FFFF0080") ?? NSColor.yellow.withAlphaComponent(0.5)
            return annotation
        }
    }
}

struct AnnotationFile: Codable {
    let version: Int
    let contentHash: String
    var annotations: [DatasheetAnnotation]

    enum CodingKeys: String, CodingKey {
        case version
        case contentHash = "content_hash"
        case annotations
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var hexInt: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&hexInt)

        let r, g, b, a: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((hexInt >> 16) & 0xFF) / 255
            g = CGFloat((hexInt >> 8) & 0xFF) / 255
            b = CGFloat(hexInt & 0xFF) / 255
            a = 1.0
        case 8:
            r = CGFloat((hexInt >> 24) & 0xFF) / 255
            g = CGFloat((hexInt >> 16) & 0xFF) / 255
            b = CGFloat((hexInt >> 8) & 0xFF) / 255
            a = CGFloat(hexInt & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
