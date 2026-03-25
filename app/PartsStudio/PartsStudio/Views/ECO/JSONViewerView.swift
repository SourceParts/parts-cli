#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JSONViewerView: View {
    let filePath: String
    @State private var root: JSONNode?
    @State private var rawText: String = ""
    @State private var error: String?
    @State private var searchText: String = ""
    @State private var showRaw = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "curlybraces")
                    .foregroundStyle(Color.accentColor)
                Text("JSON Viewer")
                    .font(.headline)

                Spacer()

                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Filter keys...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .frame(width: 140)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

                Divider()
                    .frame(height: 20)

                // Toggle tree/raw
                Picker("", selection: $showRaw) {
                    Text("Tree").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Divider()
                    .frame(height: 20)

                // Copy
                Button(action: copyJSON) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy pretty-printed JSON")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if let error {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Invalid JSON")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 400)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if showRaw {
                // Raw pretty-printed view
                ScrollView([.horizontal, .vertical]) {
                    Text(rawText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else if let root {
                // Tree view
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        JSONTreeRow(node: root, depth: 0, filter: searchText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }

            Divider()

            // Status bar
            HStack {
                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                Spacer()
                if let root {
                    Text(root.summary)
                }
                Text(ByteCountFormatter.string(fromByteCount: Int64(rawText.utf8.count), countStyle: .file))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .task { loadJSON() }
    }

    private func loadJSON() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let obj = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            rawText = String(data: prettyData, encoding: .utf8) ?? ""
            root = JSONNode.parse(obj, key: "root")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawText, forType: .string)
    }
}

// MARK: - JSON Tree Model

indirect enum JSONValue {
    case string(String)
    case number(NSNumber)
    case bool(Bool)
    case null
    case array([JSONNode])
    case object([(String, JSONNode)])
}

struct JSONNode: Identifiable {
    let id = UUID()
    let key: String
    let value: JSONValue

    var summary: String {
        switch value {
        case .string(let s): return "\"\(s.prefix(100))\""
        case .number(let n): return "\(n)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr): return "[\(arr.count) items]"
        case .object(let obj): return "{\(obj.count) keys}"
        }
    }

    var typeColor: Color {
        switch value {
        case .string: return .green
        case .number: return .cyan
        case .bool: return .orange
        case .null: return .gray
        case .array: return .purple
        case .object: return .blue
        }
    }

    var isExpandable: Bool {
        switch value {
        case .array, .object: return true
        default: return false
        }
    }

    var children: [JSONNode] {
        switch value {
        case .array(let arr): return arr
        case .object(let obj): return obj.map(\.1)
        default: return []
        }
    }

    static func parse(_ obj: Any, key: String) -> JSONNode {
        if let dict = obj as? [String: Any] {
            let children = dict.sorted(by: { $0.key < $1.key }).map { k, v in
                (k, parse(v, key: k))
            }
            return JSONNode(key: key, value: .object(children))
        } else if let arr = obj as? [Any] {
            let children = arr.enumerated().map { i, v in
                parse(v, key: "[\(i)]")
            }
            return JSONNode(key: key, value: .array(children))
        } else if let s = obj as? String {
            return JSONNode(key: key, value: .string(s))
        } else if let b = obj as? Bool {
            return JSONNode(key: key, value: .bool(b))
        } else if let n = obj as? NSNumber {
            return JSONNode(key: key, value: .number(n))
        } else if obj is NSNull {
            return JSONNode(key: key, value: .null)
        } else {
            return JSONNode(key: key, value: .string("\(obj)"))
        }
    }
}

// MARK: - Tree Row

struct JSONTreeRow: View {
    let node: JSONNode
    let depth: Int
    let filter: String
    @State private var expanded = false

    private var matchesFilter: Bool {
        guard !filter.isEmpty else { return true }
        let lower = filter.lowercased()
        if node.key.lowercased().contains(lower) { return true }
        switch node.value {
        case .string(let s): return s.lowercased().contains(lower)
        case .number(let n): return "\(n)".contains(lower)
        default: break
        }
        // Check children recursively
        return node.children.contains { childMatches($0, filter: lower) }
    }

    private func childMatches(_ n: JSONNode, filter: String) -> Bool {
        if n.key.lowercased().contains(filter) { return true }
        if case .string(let s) = n.value, s.lowercased().contains(filter) { return true }
        if case .number(let num) = n.value, "\(num)".contains(filter) { return true }
        return n.children.contains { childMatches($0, filter: filter) }
    }

    var body: some View {
        if matchesFilter {
            VStack(alignment: .leading, spacing: 0) {
                // This node's row
                HStack(spacing: 4) {
                    if node.isExpandable {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                            .onTapGesture { expanded.toggle() }
                    } else {
                        Spacer().frame(width: 10)
                    }

                    // Key
                    if node.key != "root" {
                        Text(node.key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(":")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    // Value or summary
                    switch node.value {
                    case .string(let s):
                        Text("\"\(s)\"")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(node.typeColor)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    case .number(let n):
                        Text("\(n)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(node.typeColor)
                            .textSelection(.enabled)
                    case .bool(let b):
                        Text(b ? "true" : "false")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(node.typeColor)
                    case .null:
                        Text("null")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(node.typeColor)
                    case .array(let arr):
                        Text("[\(arr.count)]")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(node.typeColor)
                    case .object(let obj):
                        Text("{\(obj.count)}")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(node.typeColor)
                    }

                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 16)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    if node.isExpandable { expanded.toggle() }
                }

                // Children
                if expanded {
                    ForEach(node.children) { child in
                        JSONTreeRow(node: child, depth: depth + 1, filter: filter)
                    }
                }
            }
            .onAppear {
                // Auto-expand root and first level
                if depth < 1 { expanded = true }
            }
        }
    }
}
#endif
