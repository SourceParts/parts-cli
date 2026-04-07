import SwiftUI

struct IQCCalendarView: View {
    let items: [IQCItem]
    @State private var displayedMonth = Date()
    @State private var selectedDate: DateComponents?

    private let calendar = Calendar.current
    private let dayOfWeekLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var itemsByDate: [DateComponents: [IQCItem]] {
        var result: [DateComponents: [IQCItem]] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"

        for item in items {
            let dateStr = String(item.createdAt.prefix(10))
            guard let date = fallback.date(from: dateStr) ?? formatter.date(from: dateStr) else { continue }
            let dc = calendar.dateComponents([.year, .month, .day], from: date)
            result[dc, default: []].append(item)
        }
        return result
    }

    private var daysInMonth: [DateComponents] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        return range.map { day in
            DateComponents(year: comps.year, month: comps.month, day: day)
        }
    }

    private var firstWeekday: Int {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let first = calendar.date(from: comps) else { return 1 }
        return calendar.component(.weekday, from: first) // 1=Sun, 7=Sat
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var selectedItems: [IQCItem] {
        guard let dc = selectedDate else { return [] }
        return itemsByDate[dc] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                Text("IQC Timeline")
                    .font(.headline)
                Spacer()
                Text("\(items.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Month navigation
                    HStack {
                        Button(action: { shiftMonth(-1) }) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        Text(monthTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()

                        Button(action: { shiftMonth(1) }) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Day-of-week headers
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                        ForEach(dayOfWeekLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                        // Leading empty cells
                        ForEach(0..<(firstWeekday - 1), id: \.self) { _ in
                            Color.clear.frame(height: 44)
                        }

                        // Day cells
                        ForEach(daysInMonth, id: \.day) { dc in
                            let dayItems = itemsByDate[dc] ?? []
                            let isSelected = selectedDate == dc
                            let isToday = calendar.dateComponents([.year, .month, .day], from: Date()) == dc

                            VStack(spacing: 2) {
                                Text("\(dc.day ?? 0)")
                                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                                    .foregroundStyle(isToday ? Color.accentColor : .primary)

                                if !dayItems.isEmpty {
                                    HStack(spacing: 2) {
                                        ForEach(Array(uniqueStatuses(dayItems).prefix(3)), id: \.self) { status in
                                            Circle()
                                                .fill(statusColor(status))
                                                .frame(width: 5, height: 5)
                                        }
                                    }
                                } else {
                                    Spacer().frame(height: 5)
                                }
                            }
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor.opacity(0.15) :
                                          !dayItems.isEmpty ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDate = (selectedDate == dc) ? nil : dc
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Divider()
                        .padding(.horizontal, 16)

                    // Event list for selected date or all events this month
                    let displayItems = selectedDate != nil ? selectedItems : monthItems
                    let headerText = selectedDate != nil ?
                        "\(selectedItems.count) event(s) on \(selectedDate?.day ?? 0) \(monthTitle.split(separator: " ").first ?? "")" :
                        "\(monthItems.count) event(s) in \(monthTitle)"

                    VStack(alignment: .leading, spacing: 8) {
                        Text(headerText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ForEach(displayItems) { item in
                            IQCEventRow(item: item)
                                .padding(.horizontal, 16)
                        }

                        if displayItems.isEmpty {
                            Text("No events")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var monthItems: [IQCItem] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        return itemsByDate.filter { dc, _ in
            dc.year == comps.year && dc.month == comps.month
        }.flatMap(\.value).sorted { $0.createdAt > $1.createdAt }
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newDate
            selectedDate = nil
        }
    }

    private func uniqueStatuses(_ items: [IQCItem]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            if seen.insert(item.status).inserted { return item.status }
            return nil
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "accepted": return .green
        case "rejected": return .red
        case "inspected": return .blue
        case "pending_inspection": return .orange
        case "received": return .purple
        default: return .gray
        }
    }
}

// MARK: - Event Row

struct IQCEventRow: View {
    let item: IQCItem

    private var badgeColor: Color {
        switch item.status {
        case "accepted": return .green
        case "rejected": return .red
        case "inspected": return .blue
        case "pending_inspection": return .orange
        case "received": return .purple
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.code)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(item.status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }
                if let notes = item.inspectionNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.createdAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
