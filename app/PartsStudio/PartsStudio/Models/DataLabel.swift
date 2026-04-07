import Foundation
import PDFKit

struct DataLabel: Codable, Identifiable {
    let id: String
    let page: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let category: String     // "pin", "voltage", "current", "package", "temperature", "frequency", "custom"
    let key: String          // e.g. "VDD", "Pin 12", "Max rating"
    let value: String        // e.g. "3.3V", "GPIO", "125C"
    let unit: String?        // e.g. "V", "A", "MHz", "C"
    let created: String

    init(page: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, category: String, key: String, value: String, unit: String? = nil) {
        self.id = UUID().uuidString
        self.page = page
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.category = category
        self.key = key
        self.value = value
        self.unit = unit
        self.created = ISO8601DateFormatter().string(from: Date())
    }

    var categoryColor: PlatformColor {
        switch category {
        case "pin": return PlatformColor.systemBlue
        case "voltage": return PlatformColor.systemRed
        case "current": return PlatformColor.systemOrange
        case "package": return PlatformColor.systemPurple
        case "temperature": return PlatformColor.systemBrown
        case "frequency": return PlatformColor.systemTeal
        default: return PlatformColor.systemGray
        }
    }

    var displayText: String {
        if let unit = unit, !unit.isEmpty {
            return "\(key): \(value) \(unit)"
        }
        return "\(key): \(value)"
    }

    func toPDFAnnotation() -> PDFAnnotation {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.contents = displayText
        annotation.font = PlatformFont.boldSystemFont(ofSize: 9)
        annotation.fontColor = categoryColor
        annotation.color = categoryColor.withAlphaComponent(0.08)

        let border = PDFBorder()
        border.lineWidth = 1.5
        border.style = .dashed
        border.dashPattern = [NSNumber(value: 4), NSNumber(value: 2)]
        annotation.border = border

        return annotation
    }
}

struct DataLabelsFile: Codable {
    let version: Int
    let contentHash: String
    var labels: [DataLabel]

    enum CodingKeys: String, CodingKey {
        case version
        case contentHash = "content_hash"
        case labels
    }
}
