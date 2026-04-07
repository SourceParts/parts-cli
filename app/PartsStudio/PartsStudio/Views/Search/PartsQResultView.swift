import SwiftUI

/// Renders `parts q` output — parses JSON responses into rich views,
/// falls back to monospace text for plain output.
struct PartsQResultView: View {
    let raw: String

    private var parsed: QResponse? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(QResponse.self, from: data)
    }

    var body: some View {
        if let resp = parsed, resp.status == "success", let qData = resp.data {
            VStack(alignment: .leading, spacing: 16) {
                // Check for empty results first
                if let r = qData.results, r.isEmpty {
                    EmptyResultView(query: qData.query ?? "")
                } else {
                    switch qData.type {
                    case "resistor_colors":
                        if let r = qData.results {
                            ResistorColorView(results: r)
                        }
                    case "smd_code":
                        if let r = qData.results {
                            SMDCodeView(results: r)
                        }
                    case "search", "part_search":
                        if let r = qData.results {
                            PartSearchResultView(results: r)
                        }
                    default:
                        GenericResultView(data: qData)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Plain text fallback
            Text(raw)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - JSON Models

struct QResponse: Decodable {
    let status: String
    let data: QData?
}

struct QData: Decodable {
    let type: String
    let results: QResults?
    let query: String?
    let searchId: String?

    enum CodingKeys: String, CodingKey {
        case type, results, query
        case searchId = "search_id"
    }
}

struct QResults: Decodable {
    let message: String?
    let details: QDetails?
    let type: String?
    let parts: [[String: AnyCodable]]?
    let products: [[String: AnyCodable]]?
    let total: Int?
    // SMD code fields
    let code: String?
    let value: Double?
    let unit: String?
    let formattedValue: String?
    let tolerance: String?

    enum CodingKeys: String, CodingKey {
        case message, details, type, parts, products, total, code, value, unit, tolerance
        case formattedValue = "formatted_value"
    }

    var isEmpty: Bool {
        let p = parts ?? []
        let pr = products ?? []
        return p.isEmpty && pr.isEmpty && (total ?? 0) == 0 && message == nil && code == nil
    }

    struct QDetails: Decodable {
        let value: String?
        let unit: String?
        let tolerance: String?
        let colors: [String]?
        let numBands: Int?

        enum CodingKeys: String, CodingKey {
            case value, unit, tolerance, colors
            case numBands = "num_bands"
        }
    }
}

/// Type-erased Codable for generic JSON values.
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else { value = "" }
    }

    var string: String { "\(value)" }
}

// MARK: - Resistor Color Bands

struct ResistorColorView: View {
    let results: QResults

    private static let bandColors: [String: Color] = [
        "black": .black, "brown": Color(red: 0.55, green: 0.27, blue: 0.07),
        "red": .red, "orange": .orange, "yellow": .yellow,
        "green": .green, "blue": .blue, "violet": .purple,
        "grey": .gray, "gray": .gray, "white": .white,
        "gold": Color(red: 0.83, green: 0.69, blue: 0.22),
        "silver": Color(red: 0.75, green: 0.75, blue: 0.75),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Big value display
            if let msg = results.message {
                Text(msg)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .textSelection(.enabled)
            }

            // Visual resistor with color bands
            if let colors = results.details?.colors {
                HStack(spacing: 0) {
                    // Lead wire
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 40, height: 3)

                    // Resistor body
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.82, green: 0.76, blue: 0.62))
                            .frame(width: CGFloat(colors.count * 40 + 60), height: 50)

                        HStack(spacing: 12) {
                            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Self.bandColors[color.lowercased()] ?? .gray)
                                    .frame(width: 14, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                    )
                            }
                        }
                    }

                    // Lead wire
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 40, height: 3)
                }
                .padding(.vertical, 8)

                // Band labels
                HStack(spacing: 12) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { i, color in
                        VStack(spacing: 2) {
                            Circle()
                                .fill(Self.bandColors[color.lowercased()] ?? .gray)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                            Text(color.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(bandLabel(index: i, total: colors.count))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Details
            if let d = results.details {
                HStack(spacing: 24) {
                    if let v = d.value, let u = d.unit {
                        detailPill("Value", "\(v) \(u)")
                    }
                    if let t = d.tolerance {
                        detailPill("Tolerance", t)
                    }
                    if let n = d.numBands {
                        detailPill("Bands", "\(n)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func bandLabel(index: Int, total: Int) -> String {
        if total == 4 {
            switch index {
            case 0: return "1st digit"
            case 1: return "2nd digit"
            case 2: return "multiplier"
            case 3: return "tolerance"
            default: return ""
            }
        } else if total == 5 {
            switch index {
            case 0: return "1st digit"
            case 1: return "2nd digit"
            case 2: return "3rd digit"
            case 3: return "multiplier"
            case 4: return "tolerance"
            default: return ""
            }
        }
        return ""
    }
}

// MARK: - SMD Code

struct SMDCodeView: View {
    let results: QResults

    private var code: String { results.code ?? "" }

    /// Decode the 3-digit code for all passive component types
    private var interpretations: [(type: String, icon: String, value: String, spec: String, unit: String, color: Color)] {
        guard code.count >= 3,
              let sig = Int(String(code.prefix(code.count - 1))),
              let mul = Int(String(code.suffix(1))) else { return [] }

        let multiplier = pow(10.0, Double(mul))

        // Resistor: EIA-198 / IEC 60062 marking
        let rOhms = Double(sig) * multiplier
        let rFormatted = formatValue(rOhms, units: [
            (1e9, "GΩ"), (1e6, "MΩ"), (1e3, "kΩ"), (1, "Ω"), (1e-3, "mΩ")
        ])

        // Capacitor: IEC 60062 / EIA-198 (value in pF)
        let cPF = Double(sig) * multiplier
        let cFormatted = formatValue(cPF, units: [
            (1e6, "µF"), (1e3, "nF"), (1, "pF")
        ])

        // Inductor: IEC 60062 (value in µH)
        let lUH = Double(sig) * multiplier
        let lFormatted = formatValue(lUH, units: [
            (1e6, "H"), (1e3, "mH"), (1, "µH"), (1e-3, "nH")
        ])

        return [
            ("Resistor", "r.square", rFormatted.0, "IEC 60062 / EIA-198", rFormatted.1, .orange),
            ("Capacitor", "c.square", cFormatted.0, "IEC 60062 / EIA-198", cFormatted.1, .blue),
            ("Inductor", "l.square", lFormatted.0, "IEC 60062 / EIA-198", lFormatted.1, .green),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Visual SMD chip
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                        .frame(width: 100, height: 50)
                    // Termination pads
                    HStack {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                            .frame(width: 8, height: 50)
                        Spacer()
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                            .frame(width: 8, height: 50)
                    }
                    .frame(width: 100)
                    Text(code)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("SMD Code \(code)")
                        .font(.title2)
                        .fontWeight(.bold)
                    if let msg = results.message {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // All interpretations
            Text("Possible Specifications")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ForEach(Array(interpretations.enumerated()), id: \.offset) { _, interp in
                HStack(spacing: 12) {
                    // Component icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(interp.color.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: interp.icon)
                            .font(.title3)
                            .foregroundStyle(interp.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(interp.type)
                                .font(.body)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(interp.value + " " + interp.unit)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                        }
                        Text(interp.spec)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(specDetail(interp.type))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            // Encoding explanation
            VStack(alignment: .leading, spacing: 6) {
                Text("How to read: \(code)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(Array(code.enumerated()), id: \.offset) { i, char in
                        VStack(spacing: 2) {
                            Text(String(char))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.bold)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(i < code.count - 1 ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                                )
                            Text(i < code.count - 1 ? "significant" : "multiplier")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 2) {
                        Text("=")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                        Text("")
                            .font(.system(size: 9))
                    }

                    VStack(spacing: 2) {
                        let sig = String(code.prefix(code.count - 1))
                        let mul = String(code.suffix(1))
                        Text("\(sig)×10^\(mul)")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .frame(height: 32)
                        Text("formula")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func specDetail(_ type: String) -> String {
        switch type {
        case "Resistor":
            return "First \(code.count - 1) digits = significant figures, last digit = number of zeros (Ω)"
        case "Capacitor":
            return "First \(code.count - 1) digits = significant figures, last digit = number of zeros (pF)"
        case "Inductor":
            return "First \(code.count - 1) digits = significant figures, last digit = number of zeros (µH)"
        default:
            return ""
        }
    }

    private func formatValue(_ raw: Double, units: [(threshold: Double, suffix: String)]) -> (String, String) {
        for (threshold, suffix) in units {
            if raw >= threshold {
                let scaled = raw / threshold
                if scaled == floor(scaled) {
                    return (String(format: "%.0f", scaled), suffix)
                } else {
                    return (String(format: "%.2g", scaled), suffix)
                }
            }
        }
        return (String(format: "%.2g", raw), units.last?.suffix ?? "")
    }
}

// MARK: - Empty Result

struct EmptyResultView: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No results found")
                .font(.title3)
                .fontWeight(.semibold)
            if !query.isEmpty {
                Text("Nothing matched \"\(query)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("  \u{2022} Check the spelling or try a different search term")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("  \u{2022} Use a part number (e.g., STM32F407VGT6)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("  \u{2022} Try a broader search (e.g., \"STM32\" instead of full MPN)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Part Search Results

struct PartSearchResultView: View {
    let results: QResults
    @EnvironmentObject var appState: AppState

    private var allParts: [[String: AnyCodable]] {
        let p = results.parts ?? []
        let pr = results.products ?? []
        return p.isEmpty ? pr : p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let msg = results.message {
                Text(msg)
                    .font(.headline)
            }

            if let total = results.total {
                Text("\(total) result\(total == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(allParts.enumerated()), id: \.offset) { _, part in
                let mpn = part["mpn"]?.string ?? part["sku"]?.string ?? part["name"]?.string ?? ""
                Button(action: {
                    if !mpn.isEmpty { appState.selectPart(mpn) }
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(mpn.isEmpty ? "Unknown" : mpn)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let price = part["price"]?.string {
                                Text(price)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.green)
                            }
                            if let stock = part["stock"]?.string, stock != "0" {
                                Text("\(stock) in stock")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let desc = part["description"]?.string {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack(spacing: 8) {
                            if let mfr = part["manufacturer"]?.string {
                                Text(mfr)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let cat = part["category"]?.string {
                                Text(cat)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if let pkg = part["package"]?.string {
                                Text(pkg)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Generic Result

struct GenericResultView: View {
    let data: QData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(data.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                Spacer()
                Text(data.type)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            if let msg = data.results?.message {
                Text(msg)
                    .font(.body)
                    .textSelection(.enabled)
            }

            if let details = data.results?.details {
                VStack(spacing: 0) {
                    if let v = details.value {
                        detailRow("Value", v)
                    }
                    if let u = details.unit {
                        detailRow("Unit", u)
                    }
                    if let t = details.tolerance {
                        detailRow("Tolerance", t)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
