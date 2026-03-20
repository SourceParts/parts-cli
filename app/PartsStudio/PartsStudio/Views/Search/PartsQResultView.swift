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
                switch qData.type {
                case "resistor_colors":
                    if let r = qData.results {
                        ResistorColorView(results: r)
                    }
                case "smd_code":
                    if let r = qData.results {
                        SMDCodeView(results: r)
                    }
                case "part_search":
                    if let r = qData.results {
                        PartSearchResultView(results: r)
                    }
                default:
                    // Generic JSON view
                    GenericResultView(data: qData)
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
}

struct QResults: Decodable {
    let message: String?
    let details: QDetails?
    let type: String?
    let parts: [[String: AnyCodable]]?
    // SMD code fields
    let code: String?
    let value: Double?
    let unit: String?
    let formattedValue: String?
    let tolerance: String?

    enum CodingKeys: String, CodingKey {
        case message, details, type, parts, code, value, unit, tolerance
        case formattedValue = "formatted_value"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let msg = results.message {
                Text(msg)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .textSelection(.enabled)
            }

            // Visual SMD component
            if let code = results.code {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                        .frame(width: 120, height: 60)
                    Text(code)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 24) {
                if let fv = results.formattedValue {
                    detailPill("Value", fv)
                }
                if let code = results.code {
                    detailPill("SMD Code", code)
                }
                if let t = results.tolerance, !t.isEmpty {
                    detailPill("Tolerance", t)
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
}

// MARK: - Part Search Results

struct PartSearchResultView: View {
    let results: QResults

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let msg = results.message {
                Text(msg)
                    .font(.headline)
            }

            if let parts = results.parts {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(part["mpn"]?.string ?? part["sku"]?.string ?? "Unknown")
                                .font(.body)
                                .fontWeight(.semibold)
                            Spacer()
                            if let price = part["price"]?.string {
                                Text(price)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.green)
                            }
                        }
                        if let desc = part["description"]?.string {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let mfr = part["manufacturer"]?.string {
                            Text(mfr)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    .textSelection(.enabled)
                }
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
