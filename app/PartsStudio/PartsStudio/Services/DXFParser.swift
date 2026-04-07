import Foundation
import CoreGraphics

// MARK: - DXF Parser

class DXFParser {

    // MARK: - Errors

    enum ParseError: Error, LocalizedError {
        case fileReadFailed(URL)
        case emptyContent
        case noEntitiesFound

        var errorDescription: String? {
            switch self {
            case .fileReadFailed(let url):
                return "Failed to read DXF file: \(url.lastPathComponent)"
            case .emptyContent:
                return "DXF content is empty"
            case .noEntitiesFound:
                return "No valid entities found in DXF file"
            }
        }
    }

    // MARK: - Group Code Pair

    private struct GroupCodePair {
        let code: Int
        let value: String
    }

    // MARK: - Public API

    func parse(contentsOf url: URL) throws -> DXFDocument {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            throw ParseError.fileReadFailed(url)
        }
        return try parse(string: content)
    }

    func parse(string content: String) throws -> DXFDocument {
        guard !content.isEmpty else {
            throw ParseError.emptyContent
        }

        // Step 1: Tokenize into group code pairs
        let pairs = tokenize(content)

        // Step 2: Find section ranges
        let sections = findSections(pairs)

        // Step 3: Parse HEADER
        var version = "Unknown"
        var units = 0
        if let headerRange = sections["HEADER"] {
            (version, units) = parseHeader(pairs, range: headerRange)
        }

        // Step 4: Parse TABLES (layers)
        var layers: [String: DXFLayer] = [:]
        if let tablesRange = sections["TABLES"] {
            layers = parseLayers(pairs, range: tablesRange)
        }

        // Step 5: Parse BLOCKS
        var blocks: [String: DXFBlock] = [:]
        if let blocksRange = sections["BLOCKS"] {
            blocks = parseBlocks(pairs, range: blocksRange)
        }

        // Step 6: Parse ENTITIES
        var entities: [DXFEntity] = []
        if let entitiesRange = sections["ENTITIES"] {
            entities = parseEntities(pairs, range: entitiesRange)
        }

        // Step 7: Create layers on-the-fly for entities referencing unknown layers
        for entity in entities {
            if layers[entity.layer] == nil {
                layers[entity.layer] = DXFLayer(name: entity.layer, color: 7)
            }
        }

        // Also add layers from block entities
        for block in blocks.values {
            for entity in block.entities {
                if layers[entity.layer] == nil {
                    layers[entity.layer] = DXFLayer(name: entity.layer, color: 7)
                }
            }
        }

        // Ensure default layer "0" exists
        if layers["0"] == nil {
            layers["0"] = DXFLayer(name: "0", color: 7)
        }

        // Step 8: Compute bounds
        let bounds = computeBounds(entities: entities)

        return DXFDocument(
            layers: layers,
            blocks: blocks,
            entities: entities,
            bounds: bounds,
            version: version,
            units: units
        )
    }

    // MARK: - Tokenizer

    private func tokenize(_ content: String) -> [GroupCodePair] {
        // Normalize line endings: \r\n → \n, standalone \r → \n
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
                                .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var pairs: [GroupCodePair] = []
        var i = 0

        while i + 1 < lines.count {
            let codeLine = lines[i]
            let valueLine = lines[i + 1]

            if let code = Int(codeLine) {
                pairs.append(GroupCodePair(code: code, value: valueLine))
                i += 2
            } else {
                // Skip unparseable line and advance by 1
                i += 1
            }
        }

        return pairs
    }

    // MARK: - Section Finder

    private func findSections(_ pairs: [GroupCodePair]) -> [String: Range<Int>] {
        var sections: [String: Range<Int>] = [:]
        var i = 0

        while i < pairs.count {
            if pairs[i].code == 0 && pairs[i].value.uppercased() == "SECTION" {
                // Next pair should be code 2 with section name
                if i + 1 < pairs.count && pairs[i + 1].code == 2 {
                    let sectionName = pairs[i + 1].value.uppercased()
                    let sectionStart = i + 2

                    // Find ENDSEC
                    var j = sectionStart
                    while j < pairs.count {
                        if pairs[j].code == 0 && pairs[j].value.uppercased() == "ENDSEC" {
                            sections[sectionName] = sectionStart..<j
                            i = j + 1
                            break
                        }
                        j += 1
                    }

                    if j >= pairs.count {
                        // No ENDSEC found — section extends to end
                        sections[sectionName] = sectionStart..<pairs.count
                        break
                    }
                    continue
                }
            }
            i += 1
        }

        return sections
    }

    // MARK: - HEADER Parser

    private func parseHeader(_ pairs: [GroupCodePair], range: Range<Int>) -> (String, Int) {
        var version = "Unknown"
        var units = 0

        var i = range.lowerBound
        while i < range.upperBound {
            if pairs[i].code == 9 {
                let varName = pairs[i].value.uppercased()

                if varName == "$ACADVER" {
                    // Next pair with code 1 is the value
                    var j = i + 1
                    while j < range.upperBound && j <= i + 5 {
                        if pairs[j].code == 1 {
                            version = pairs[j].value
                            break
                        }
                        j += 1
                    }
                } else if varName == "$INSUNITS" {
                    // Next pair with code 70 is the value
                    var j = i + 1
                    while j < range.upperBound && j <= i + 5 {
                        if pairs[j].code == 70 {
                            units = Int(pairs[j].value) ?? 0
                            break
                        }
                        j += 1
                    }
                }
            }
            i += 1
        }

        return (version, units)
    }

    // MARK: - TABLES / LAYER Parser

    private func parseLayers(_ pairs: [GroupCodePair], range: Range<Int>) -> [String: DXFLayer] {
        var layers: [String: DXFLayer] = [:]
        var i = range.lowerBound

        while i < range.upperBound {
            if pairs[i].code == 0 && pairs[i].value.uppercased() == "LAYER" {
                var name = "0"
                var color = 7

                var j = i + 1
                while j < range.upperBound {
                    // Stop at the next code 0 (next table entry or ENDTAB)
                    if pairs[j].code == 0 {
                        break
                    }
                    switch pairs[j].code {
                    case 2:
                        name = pairs[j].value
                    case 62:
                        let c = Int(pairs[j].value) ?? 7
                        // Negative color means layer is off/frozen — store absolute value
                        color = abs(c)
                    default:
                        break
                    }
                    j += 1
                }

                layers[name] = DXFLayer(name: name, color: color)
                i = j
                continue
            }
            i += 1
        }

        return layers
    }

    // MARK: - BLOCKS Parser

    private func parseBlocks(_ pairs: [GroupCodePair], range: Range<Int>) -> [String: DXFBlock] {
        var blocks: [String: DXFBlock] = [:]
        var i = range.lowerBound

        while i < range.upperBound {
            if pairs[i].code == 0 && pairs[i].value.uppercased() == "BLOCK" {
                var blockName = ""
                var baseX: Double = 0
                var baseY: Double = 0

                // Read block header attributes
                var j = i + 1
                while j < range.upperBound {
                    if pairs[j].code == 0 {
                        break
                    }
                    switch pairs[j].code {
                    case 2:
                        blockName = pairs[j].value
                    case 10:
                        baseX = Double(pairs[j].value) ?? 0
                    case 20:
                        baseY = Double(pairs[j].value) ?? 0
                    default:
                        break
                    }
                    j += 1
                }

                // Parse entities within the block until ENDBLK
                var blockEntities: [DXFEntity] = []
                while j < range.upperBound {
                    if pairs[j].code == 0 && pairs[j].value.uppercased() == "ENDBLK" {
                        j += 1
                        // Skip past ENDBLK attributes
                        while j < range.upperBound && pairs[j].code != 0 {
                            j += 1
                        }
                        break
                    }

                    if pairs[j].code == 0 {
                        let (entity, nextIndex) = parseOneEntity(pairs, startIndex: j, upperBound: range.upperBound)
                        if let entity = entity {
                            blockEntities.append(entity)
                        }
                        j = nextIndex
                    } else {
                        j += 1
                    }
                }

                if !blockName.isEmpty {
                    blocks[blockName] = DXFBlock(
                        name: blockName,
                        basePoint: CGPoint(x: baseX, y: baseY),
                        entities: blockEntities
                    )
                }

                i = j
                continue
            }
            i += 1
        }

        return blocks
    }

    // MARK: - ENTITIES Parser

    private func parseEntities(_ pairs: [GroupCodePair], range: Range<Int>) -> [DXFEntity] {
        var entities: [DXFEntity] = []
        var i = range.lowerBound

        while i < range.upperBound {
            if pairs[i].code == 0 {
                let (entity, nextIndex) = parseOneEntity(pairs, startIndex: i, upperBound: range.upperBound)
                if let entity = entity {
                    entities.append(entity)
                }
                i = nextIndex
            } else {
                i += 1
            }
        }

        return entities
    }

    // MARK: - Single Entity Parser

    /// Parses one entity starting at `startIndex` (which must be a code 0 pair).
    /// Returns the parsed entity (or nil) and the index of the next code 0 pair.
    private func parseOneEntity(_ pairs: [GroupCodePair], startIndex: Int, upperBound: Int) -> (DXFEntity?, Int) {
        guard startIndex < upperBound, pairs[startIndex].code == 0 else {
            return (nil, startIndex + 1)
        }

        let typeName = pairs[startIndex].value.uppercased()

        // Find the end of this entity (next code 0 or end of range)
        var endIndex = startIndex + 1
        while endIndex < upperBound && pairs[endIndex].code != 0 {
            endIndex += 1
        }

        let entityRange = (startIndex + 1)..<endIndex

        // Common attributes
        var layer = "0"
        var color = 0

        // Extract common attributes first
        for k in entityRange {
            switch pairs[k].code {
            case 8:
                layer = pairs[k].value
            case 62:
                color = Int(pairs[k].value) ?? 0
            default:
                break
            }
        }

        let entity: DXFEntity?

        switch typeName {
        case "LINE":
            entity = parseLine(pairs, range: entityRange, layer: layer, color: color)
        case "CIRCLE":
            entity = parseCircle(pairs, range: entityRange, layer: layer, color: color)
        case "ARC":
            entity = parseArc(pairs, range: entityRange, layer: layer, color: color)
        case "LWPOLYLINE":
            entity = parseLWPolyline(pairs, range: entityRange, layer: layer, color: color)
        case "TEXT":
            entity = parseText(pairs, range: entityRange, layer: layer, color: color)
        case "MTEXT":
            entity = parseMText(pairs, range: entityRange, layer: layer, color: color)
        case "POINT":
            entity = parsePoint(pairs, range: entityRange, layer: layer, color: color)
        case "DIMENSION":
            entity = parseDimension(pairs, range: entityRange, layer: layer, color: color)
        case "INSERT":
            entity = parseInsert(pairs, range: entityRange, layer: layer, color: color)
        default:
            entity = nil
        }

        return (entity, endIndex)
    }

    // MARK: - Entity Type Parsers

    private func parseLine(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var x1: Double = 0, y1: Double = 0
        var x2: Double = 0, y2: Double = 0

        for i in range {
            switch pairs[i].code {
            case 10: x1 = Double(pairs[i].value) ?? 0
            case 20: y1 = Double(pairs[i].value) ?? 0
            case 11: x2 = Double(pairs[i].value) ?? 0
            case 21: y2 = Double(pairs[i].value) ?? 0
            default: break
            }
        }

        return DXFEntity(
            type: .line(start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2)),
            layer: layer,
            color: color
        )
    }

    private func parseCircle(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var cx: Double = 0, cy: Double = 0
        var radius: Double = 0

        for i in range {
            switch pairs[i].code {
            case 10: cx = Double(pairs[i].value) ?? 0
            case 20: cy = Double(pairs[i].value) ?? 0
            case 40: radius = Double(pairs[i].value) ?? 0
            default: break
            }
        }

        return DXFEntity(
            type: .circle(center: CGPoint(x: cx, y: cy), radius: radius),
            layer: layer,
            color: color
        )
    }

    private func parseArc(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var cx: Double = 0, cy: Double = 0
        var radius: Double = 0
        var startAngle: Double = 0, endAngle: Double = 360

        for i in range {
            switch pairs[i].code {
            case 10: cx = Double(pairs[i].value) ?? 0
            case 20: cy = Double(pairs[i].value) ?? 0
            case 40: radius = Double(pairs[i].value) ?? 0
            case 50: startAngle = Double(pairs[i].value) ?? 0
            case 51: endAngle = Double(pairs[i].value) ?? 360
            default: break
            }
        }

        return DXFEntity(
            type: .arc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: startAngle, endAngle: endAngle),
            layer: layer,
            color: color
        )
    }

    private func parseLWPolyline(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var points: [CGPoint] = []
        var closed = false

        // LWPOLYLINE has multiple code 10/20 pairs — one per vertex.
        // We accumulate them in order: each code 10 starts a new vertex X,
        // and the following code 20 provides the Y.
        var currentX: Double?

        for i in range {
            switch pairs[i].code {
            case 70:
                let flags = Int(pairs[i].value) ?? 0
                closed = (flags & 1) != 0
            case 10:
                // If we have a pending X without a Y, store it with Y=0
                if let x = currentX {
                    points.append(CGPoint(x: x, y: 0))
                }
                currentX = Double(pairs[i].value) ?? 0
            case 20:
                let y = Double(pairs[i].value) ?? 0
                if let x = currentX {
                    points.append(CGPoint(x: x, y: y))
                    currentX = nil
                }
            default:
                break
            }
        }

        // Handle trailing X with no Y
        if let x = currentX {
            points.append(CGPoint(x: x, y: 0))
        }

        return DXFEntity(
            type: .lwPolyline(points: points, closed: closed),
            layer: layer,
            color: color
        )
    }

    private func parseText(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var x: Double = 0, y: Double = 0
        var height: Double = 1
        var content = ""
        var rotation: Double = 0

        for i in range {
            switch pairs[i].code {
            case 10: x = Double(pairs[i].value) ?? 0
            case 20: y = Double(pairs[i].value) ?? 0
            case 40: height = Double(pairs[i].value) ?? 1
            case 1: content = pairs[i].value
            case 50: rotation = Double(pairs[i].value) ?? 0
            default: break
            }
        }

        return DXFEntity(
            type: .text(position: CGPoint(x: x, y: y), height: height, content: content, rotation: rotation),
            layer: layer,
            color: color
        )
    }

    private func parseMText(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var x: Double = 0, y: Double = 0
        var height: Double = 1
        var content = ""
        var width: Double = 0

        // MTEXT can split long text across multiple code 3 pairs followed by code 1
        var textParts: [String] = []
        var primaryText = ""

        for i in range {
            switch pairs[i].code {
            case 10: x = Double(pairs[i].value) ?? 0
            case 20: y = Double(pairs[i].value) ?? 0
            case 40: height = Double(pairs[i].value) ?? 1
            case 41: width = Double(pairs[i].value) ?? 0
            case 3: textParts.append(pairs[i].value)
            case 1: primaryText = pairs[i].value
            default: break
            }
        }

        // Code 3 parts come before code 1 in long text
        content = textParts.joined() + primaryText

        return DXFEntity(
            type: .mtext(position: CGPoint(x: x, y: y), height: height, content: content, width: width),
            layer: layer,
            color: color
        )
    }

    private func parsePoint(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var x: Double = 0, y: Double = 0

        for i in range {
            switch pairs[i].code {
            case 10: x = Double(pairs[i].value) ?? 0
            case 20: y = Double(pairs[i].value) ?? 0
            default: break
            }
        }

        return DXFEntity(
            type: .point(position: CGPoint(x: x, y: y)),
            layer: layer,
            color: color
        )
    }

    private func parseDimension(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var defX: Double = 0, defY: Double = 0
        var midX: Double = 0, midY: Double = 0
        var text = ""

        for i in range {
            switch pairs[i].code {
            case 10: defX = Double(pairs[i].value) ?? 0
            case 20: defY = Double(pairs[i].value) ?? 0
            case 11: midX = Double(pairs[i].value) ?? 0
            case 21: midY = Double(pairs[i].value) ?? 0
            case 1: text = pairs[i].value
            default: break
            }
        }

        return DXFEntity(
            type: .dimension(
                defPoint: CGPoint(x: defX, y: defY),
                textMidpoint: CGPoint(x: midX, y: midY),
                text: text
            ),
            layer: layer,
            color: color
        )
    }

    private func parseInsert(_ pairs: [GroupCodePair], range: Range<Int>, layer: String, color: Int) -> DXFEntity {
        var name = ""
        var x: Double = 0, y: Double = 0
        var scaleX: Double = 1, scaleY: Double = 1
        var rotation: Double = 0

        for i in range {
            switch pairs[i].code {
            case 2: name = pairs[i].value
            case 10: x = Double(pairs[i].value) ?? 0
            case 20: y = Double(pairs[i].value) ?? 0
            case 41: scaleX = Double(pairs[i].value) ?? 1
            case 42: scaleY = Double(pairs[i].value) ?? 1
            case 50: rotation = Double(pairs[i].value) ?? 0
            default: break
            }
        }

        return DXFEntity(
            type: .insert(name: name, position: CGPoint(x: x, y: y), scaleX: scaleX, scaleY: scaleY, rotation: rotation),
            layer: layer,
            color: color
        )
    }

    // MARK: - Bounds Computation

    private func computeBounds(entities: [DXFEntity]) -> CGRect {
        guard !entities.isEmpty else {
            return .zero
        }

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        func expandToFit(_ point: CGPoint) {
            minX = min(minX, Double(point.x))
            minY = min(minY, Double(point.y))
            maxX = max(maxX, Double(point.x))
            maxY = max(maxY, Double(point.y))
        }

        func expandToFitCircleBounds(center: CGPoint, radius: Double) {
            minX = min(minX, Double(center.x) - radius)
            minY = min(minY, Double(center.y) - radius)
            maxX = max(maxX, Double(center.x) + radius)
            maxY = max(maxY, Double(center.y) + radius)
        }

        for entity in entities {
            switch entity.type {
            case .line(let start, let end):
                expandToFit(start)
                expandToFit(end)

            case .circle(let center, let radius):
                expandToFitCircleBounds(center: center, radius: radius)

            case .arc(let center, let radius, _, _):
                // Approximate with full circle bounds
                expandToFitCircleBounds(center: center, radius: radius)

            case .lwPolyline(let points, _):
                for point in points {
                    expandToFit(point)
                }

            case .text(let position, _, _, _):
                expandToFit(position)

            case .mtext(let position, _, _, _):
                expandToFit(position)

            case .point(let position):
                expandToFit(position)

            case .dimension(let defPoint, let textMidpoint, _):
                expandToFit(defPoint)
                expandToFit(textMidpoint)

            case .insert(_, let position, _, _, _):
                expandToFit(position)
            }
        }

        // Guard against no valid points
        if minX > maxX || minY > maxY {
            return .zero
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
