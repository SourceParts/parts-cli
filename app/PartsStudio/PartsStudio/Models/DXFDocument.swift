import Foundation
import CoreGraphics

// MARK: - DXF Entity Type

enum DXFEntityType {
    case line(start: CGPoint, end: CGPoint)
    case circle(center: CGPoint, radius: Double)
    case arc(center: CGPoint, radius: Double, startAngle: Double, endAngle: Double)
    case lwPolyline(points: [CGPoint], closed: Bool)
    case text(position: CGPoint, height: Double, content: String, rotation: Double)
    case mtext(position: CGPoint, height: Double, content: String, width: Double)
    case point(position: CGPoint)
    case dimension(defPoint: CGPoint, textMidpoint: CGPoint, text: String)
    case insert(name: String, position: CGPoint, scaleX: Double, scaleY: Double, rotation: Double)
}

// MARK: - DXF Entity

struct DXFEntity: Identifiable {
    let id: UUID
    let type: DXFEntityType
    let layer: String
    let color: Int

    init(id: UUID = UUID(), type: DXFEntityType, layer: String, color: Int) {
        self.id = id
        self.type = type
        self.layer = layer
        self.color = color
    }
}

// MARK: - DXF Layer

struct DXFLayer {
    let name: String
    let color: Int
    var isVisible: Bool = true
}

// MARK: - DXF Block

struct DXFBlock {
    let name: String
    let basePoint: CGPoint
    let entities: [DXFEntity]
}

// MARK: - DXF Document

struct DXFDocument {
    var layers: [String: DXFLayer]
    var blocks: [String: DXFBlock]
    var entities: [DXFEntity]
    var bounds: CGRect
    var version: String
    var units: Int

    var sortedLayers: [DXFLayer] {
        layers.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var unitLabel: String {
        switch units {
        case 1: return "inches"
        case 2: return "feet"
        case 3: return "miles"
        case 4: return "mm"
        case 5: return "cm"
        case 6: return "m"
        case 7: return "km"
        case 8: return "microinches"
        case 9: return "mils"
        case 10: return "yards"
        case 11: return "angstroms"
        case 12: return "nanometers"
        case 13: return "microns"
        case 14: return "decimeters"
        case 15: return "decameters"
        case 16: return "hectometers"
        case 17: return "gigameters"
        case 18: return "AU"
        case 19: return "light years"
        case 20: return "parsecs"
        default: return "unspecified"
        }
    }
}

// MARK: - ACI Color Table

func aciColor(_ index: Int) -> (r: Double, g: Double, b: Double) {
    switch index {
    case 1: return (1.0, 0.0, 0.0)       // red
    case 2: return (1.0, 1.0, 0.0)       // yellow
    case 3: return (0.0, 1.0, 0.0)       // green
    case 4: return (0.0, 1.0, 1.0)       // cyan
    case 5: return (0.0, 0.0, 1.0)       // blue
    case 6: return (1.0, 0.0, 1.0)       // magenta
    case 7: return (1.0, 1.0, 1.0)       // white
    default: return (1.0, 1.0, 1.0)      // white (0=BYLAYER, >7=default)
    }
}
