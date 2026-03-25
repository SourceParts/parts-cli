#if os(macOS)
import Foundation
import AppKit

// MARK: - Layer Type

enum PCBLayerType: String, CaseIterable, Codable {
    case frontCopper = "F_Cu"
    case innerCopper = "In_Cu"
    case backCopper = "B_Cu"
    case frontMask = "F_Mask"
    case backMask = "B_Mask"
    case frontPaste = "F_Paste"
    case backPaste = "B_Paste"
    case frontSilk = "F_Silk"
    case backSilk = "B_Silk"
    case edgeCuts = "Edge_Cuts"
    case drill = "Drill"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .frontCopper: return "Front Copper"
        case .innerCopper: return "Inner Copper"
        case .backCopper: return "Back Copper"
        case .frontMask: return "Front Mask"
        case .backMask: return "Back Mask"
        case .frontPaste: return "Front Paste"
        case .backPaste: return "Back Paste"
        case .frontSilk: return "Front Silk"
        case .backSilk: return "Back Silk"
        case .edgeCuts: return "Edge Cuts"
        case .drill: return "Drill"
        case .unknown: return "Unknown"
        }
    }

    var defaultColor: NSColor {
        switch self {
        case .frontCopper: return NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1)
        case .innerCopper: return NSColor(red: 0.6, green: 0.6, blue: 0.0, alpha: 1)
        case .backCopper: return NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1)
        case .frontMask: return NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1)
        case .backMask: return NSColor(red: 0.0, green: 0.4, blue: 0.0, alpha: 1)
        case .frontPaste: return NSColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
        case .backPaste: return NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        case .frontSilk: return NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        case .backSilk: return NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        case .edgeCuts: return NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1)
        case .drill: return NSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)
        case .unknown: return NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        }
    }

    var icon: String {
        switch self {
        case .frontCopper, .innerCopper, .backCopper: return "square.3.layers.3d"
        case .frontMask, .backMask: return "shield.fill"
        case .frontPaste, .backPaste: return "drop.fill"
        case .frontSilk, .backSilk: return "textformat"
        case .edgeCuts: return "square.dashed"
        case .drill: return "circle.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - PCB Layer

class PCBLayer: Identifiable, ObservableObject {
    let id: String
    let type: PCBLayerType
    let filePath: String
    let displayName: String
    let stackupOrder: Int
    let innerIndex: Int?  // nil for non-inner layers, 1-N for inner copper

    @Published var color: NSColor
    @Published var alpha: Double = 1.0
    @Published var isVisible: Bool = true

    init(type: PCBLayerType, filePath: String, displayName: String,
         stackupOrder: Int, innerIndex: Int? = nil) {
        self.id = UUID().uuidString
        self.type = type
        self.filePath = filePath
        self.displayName = displayName
        self.stackupOrder = stackupOrder
        self.innerIndex = innerIndex
        self.color = type.defaultColor
    }
}

// MARK: - PCB Version

struct PCBVersion: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let layerCount: Int
    let basePath: String
    let gbrjobPath: String?
    var layers: [PCBLayer]

    var copperLayers: [PCBLayer] {
        layers.filter { $0.type == .frontCopper || $0.type == .innerCopper || $0.type == .backCopper }
            .sorted { $0.stackupOrder < $1.stackupOrder }
    }

    var drillLayers: [PCBLayer] {
        layers.filter { $0.type == .drill }
    }
}

// MARK: - Layer Classification

enum PCBLayerClassifier {

    /// Classify a Gerber/drill file by its extension.
    static func classify(filename: String) -> (type: PCBLayerType, innerIndex: Int?) {
        let ext = (filename as NSString).pathExtension.lowercased()
        let name = filename.lowercased()

        switch ext {
        case "gtl": return (.frontCopper, nil)
        case "gbl": return (.backCopper, nil)
        case "gts": return (.frontMask, nil)
        case "gbs": return (.backMask, nil)
        case "gtp": return (.frontPaste, nil)
        case "gbp": return (.backPaste, nil)
        case "gto": return (.frontSilk, nil)
        case "gbo": return (.backSilk, nil)
        case "gm1", "gko": return (.edgeCuts, nil)
        case "drl", "xln": return (.drill, nil)
        default:
            // Inner copper layers: .g1, .g2, ..., .g99
            if ext.hasPrefix("g"), let num = Int(ext.dropFirst()), num >= 1 {
                return (.innerCopper, num)
            }
            return (.unknown, nil)
        }
    }

    /// Generate display name for a layer.
    static func displayName(type: PCBLayerType, innerIndex: Int?, filename: String) -> String {
        switch type {
        case .frontCopper: return "F.Cu (Top)"
        case .backCopper: return "B.Cu (Bottom)"
        case .innerCopper:
            if let idx = innerIndex { return "In\(idx).Cu" }
            return "Inner Cu"
        case .frontMask: return "F.Mask"
        case .backMask: return "B.Mask"
        case .frontPaste: return "F.Paste"
        case .backPaste: return "B.Paste"
        case .frontSilk: return "F.SilkS"
        case .backSilk: return "B.SilkS"
        case .edgeCuts: return "Edge.Cuts"
        case .drill: return "Drill"
        case .unknown: return (filename as NSString).lastPathComponent
        }
    }

    /// Stackup order (lower = closer to top of board).
    static func stackupOrder(type: PCBLayerType, innerIndex: Int?, totalInner: Int) -> Int {
        switch type {
        case .frontSilk: return 0
        case .frontPaste: return 1
        case .frontMask: return 2
        case .frontCopper: return 3
        case .innerCopper: return 3 + (innerIndex ?? 1)
        case .backCopper: return 3 + totalInner + 1
        case .backMask: return 3 + totalInner + 2
        case .backPaste: return 3 + totalInner + 3
        case .backSilk: return 3 + totalInner + 4
        case .edgeCuts: return 1000
        case .drill: return 1001
        case .unknown: return 999
        }
    }

    /// Discover and classify all Gerber/drill files in a directory.
    static func discoverLayers(in directory: String) -> [PCBLayer] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        let gerberExts = Set(["gbr", "gtl", "gbl", "gts", "gbs", "gto", "gbo", "gtp", "gbp",
                              "gm1", "gko", "drl", "xln"])

        var layers: [PCBLayer] = []
        var maxInner = 0

        // First pass: classify and find max inner layer
        var classified: [(file: String, type: PCBLayerType, inner: Int?)] = []
        for file in files.sorted() {
            let ext = (file as NSString).pathExtension.lowercased()
            let isGerber = gerberExts.contains(ext) ||
                (ext.hasPrefix("g") && Int(ext.dropFirst()) != nil)

            guard isGerber else { continue }

            let (type, inner) = classify(filename: file)
            classified.append((file, type, inner))
            if let idx = inner { maxInner = max(maxInner, idx) }
        }

        // Second pass: create layers with proper stackup ordering
        for (file, type, inner) in classified {
            let path = (directory as NSString).appendingPathComponent(file)
            let name = displayName(type: type, innerIndex: inner, filename: file)
            let order = stackupOrder(type: type, innerIndex: inner, totalInner: maxInner)

            let layer = PCBLayer(type: type, filePath: path, displayName: name,
                                 stackupOrder: order, innerIndex: inner)
            layers.append(layer)
        }

        return layers.sorted { $0.stackupOrder < $1.stackupOrder }
    }
}
#endif
