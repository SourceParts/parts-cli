#if os(macOS)
import SwiftUI
import AppKit

struct CSVViewerView: View {
    let filePath: String
    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var searchText: String = ""

    private var filteredRows: [[String]] {
        let query = searchText.lowercased()
        if query.isEmpty { return rows }
        return rows.filter { row in
            row.contains(where: { $0.lowercased().contains(query) })
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

            // Native table
            if headers.isEmpty {
                VStack {
                    Spacer()
                    Text("Empty or invalid CSV")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                NativeTableView(headers: headers, rows: filteredRows)
            }

            Divider()

            // Footer
            HStack {
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
                .help("Reveal in Finder")
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

// MARK: - Native NSTableView

struct NativeTableView: NSViewRepresentable {
    let headers: [String]
    let rows: [[String]]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.intercellSpacing = NSSize(width: 8, height: 4)
        tableView.rowHeight = 22
        tableView.headerView = NSTableHeaderView()
        tableView.gridStyleMask = [.solidVerticalGridLineMask]

        // Row number column
        let numCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("_row"))
        numCol.title = "#"
        numCol.width = 40
        numCol.minWidth = 30
        numCol.maxWidth = 60
        tableView.addTableColumn(numCol)

        // Data columns
        for (i, header) in headers.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col_\(i)"))
            col.title = header
            col.minWidth = 60
            col.width = 120
            col.sortDescriptorPrototype = NSSortDescriptor(key: "col_\(i)", ascending: true)
            tableView.addTableColumn(col)
        }

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        context.coordinator.tableView = tableView

        scrollView.documentView = tableView

        // Size columns to fit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            tableView.sizeToFit()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.rows = rows
        (scrollView.documentView as? NSTableView)?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(headers: headers, rows: rows)
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        let headers: [String]
        var rows: [[String]]
        weak var tableView: NSTableView?

        init(headers: [String], rows: [[String]]) {
            self.headers = headers
            self.rows = rows
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let colId = tableColumn?.identifier.rawValue else { return nil }

            let cellId = NSUserInterfaceItemIdentifier("cell")
            let cell: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
                cell = existing
            } else {
                cell = NSTextField()
                cell.identifier = cellId
                cell.isBordered = false
                cell.isEditable = false
                cell.isSelectable = true
                cell.backgroundColor = .clear
                cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                cell.lineBreakMode = .byTruncatingTail
                cell.cell?.truncatesLastVisibleLine = true
            }

            if colId == "_row" {
                cell.stringValue = "\(row + 1)"
                cell.alignment = .center
                cell.font = NSFont.systemFont(ofSize: 10)
                cell.textColor = .tertiaryLabelColor
            } else if colId.hasPrefix("col_"), let colIndex = Int(colId.dropFirst(4)) {
                cell.stringValue = colIndex < rows[row].count ? rows[row][colIndex] : ""
                cell.alignment = .left
                cell.textColor = .labelColor
            }

            return cell
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sort = tableView.sortDescriptors.first,
                  let key = sort.key, key.hasPrefix("col_"),
                  let colIndex = Int(key.dropFirst(4)) else { return }

            rows.sort { a, b in
                let va = colIndex < a.count ? a[colIndex] : ""
                let vb = colIndex < b.count ? b[colIndex] : ""
                if let na = Double(va), let nb = Double(vb) {
                    return sort.ascending ? na < nb : na > nb
                }
                let result = va.localizedCaseInsensitiveCompare(vb)
                return sort.ascending ? result == .orderedAscending : result == .orderedDescending
            }
            tableView.reloadData()
        }
    }
}
#endif
