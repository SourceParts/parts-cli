import SwiftUI

struct CSVViewerView: View {
    let filePath: String
    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var searchText: String = ""
    @State private var sortColumn: Int?
    @State private var sortAscending: Bool = true

    private var filteredRows: [[String]] {
        let query = searchText.lowercased()
        if query.isEmpty { return sortedRows }
        return sortedRows.filter { row in
            row.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private var sortedRows: [[String]] {
        guard let col = sortColumn, col < headers.count else { return rows }
        return rows.sorted { a, b in
            let va = col < a.count ? a[col] : ""
            let vb = col < b.count ? b[col] : ""
            // Try numeric sort
            if let na = Double(va), let nb = Double(vb) {
                return sortAscending ? na < nb : na > nb
            }
            return sortAscending
                ? va.localizedCaseInsensitiveCompare(vb) == .orderedAscending
                : va.localizedCaseInsensitiveCompare(vb) == .orderedDescending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(Color.accentColor)
                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                    .font(.headline)
                Spacer()
                Text("\(rows.count) rows, \(headers.count) columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Filter rows...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text("\(filteredRows.count) of \(rows.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Table
            if headers.isEmpty {
                VStack {
                    Spacer()
                    Text("Empty or invalid CSV")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            // Row number column
                            Text("#")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .center)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor))

                            ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                                Button(action: {
                                    if sortColumn == i {
                                        sortAscending.toggle()
                                    } else {
                                        sortColumn = i
                                        sortAscending = true
                                    }
                                }) {
                                    HStack(spacing: 2) {
                                        Text(header)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                        if sortColumn == i {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 8))
                                        }
                                    }
                                    .frame(minWidth: 80, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .background(Color(nsColor: .controlBackgroundColor))

                                if i < headers.count - 1 {
                                    Divider()
                                }
                            }
                        }

                        Divider()

                        // Data rows
                        ForEach(Array(filteredRows.enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: 0) {
                                Text("\(rowIndex + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 40, alignment: .center)
                                    .padding(.vertical, 4)

                                ForEach(Array(headers.indices), id: \.self) { colIndex in
                                    Text(colIndex < row.count ? row[colIndex] : "")
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 80, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .textSelection(.enabled)

                                    if colIndex < headers.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .background(rowIndex % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(filePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: {
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                }) {
                    Image(systemName: "folder")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in default app")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear { loadCSV() }
    }

    private func loadCSV() {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return }

        headers = parseCSVLine(headerLine)
        rows = Array(lines.dropFirst()).map { parseCSVLine($0) }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
