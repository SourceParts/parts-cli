#if os(macOS)
import SwiftUI
import AppKit

/// Supply Chain Pipeline: Procurement approval, AVL qualification, and obsolescence check.
struct SupplyChainPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .procurementApprove

    // Station 1: Procurement Approve
    @State private var procBomPath: String = ""
    @State private var procQuantity: String = ""
    @State private var procTargetDate: String = ""
    @State private var procResult: [String: Any]?
    @State private var procLoading = false
    @State private var procError: String?

    // Station 2: AVL Qualify
    @State private var avlBomPath: String = ""
    @State private var avlResult: [String: Any]?
    @State private var avlLoading = false

    // Station 3: Obsolescence Check
    @State private var obsBomPath: String = ""
    @State private var obsResult: [String: Any]?
    @State private var obsLoading = false

    enum Station: Int, CaseIterable {
        case procurementApprove = 1
        case avlQualify = 2
        case obsolescenceCheck = 3

        var title: String {
            switch self {
            case .procurementApprove: return "Procurement Approve"
            case .avlQualify: return "AVL Qualify"
            case .obsolescenceCheck: return "Obsolescence Check"
            }
        }

        var icon: String {
            switch self {
            case .procurementApprove: return "cart.badge.plus"
            case .avlQualify: return "checkmark.seal"
            case .obsolescenceCheck: return "exclamationmark.triangle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stationContent
                    }
                    .padding(24)
                }
                .frame(minWidth: 500)

                stationSidebar
                    .frame(width: 220)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle")
                .foregroundStyle(Color.accentColor)
            Text("Supply Chain Pipeline")
                .font(.headline)
            Divider().frame(height: 20)

            Text("Station \(currentStation.rawValue)/3")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(currentStation.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Station Content

    @ViewBuilder
    private var stationContent: some View {
        switch currentStation {
        case .procurementApprove: procurementApproveStation
        case .avlQualify: avlQualifyStation
        case .obsolescenceCheck: obsolescenceCheckStation
        }
    }

    // MARK: - Station 1: Procurement Approve

    private var procurementApproveStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Procurement Approve", description: "Upload BOM and generate purchase orders grouped by vendor", icon: "cart.badge.plus")

            VStack(alignment: .leading, spacing: 8) {
                filePickerRow(label: "BOM File:", path: $procBomPath, extensions: ["csv", "xlsx"])

                HStack {
                    Text("Quantity:").font(.caption).fontWeight(.medium)
                    TextField("e.g. 500", text: $procQuantity)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Target Date:").font(.caption).fontWeight(.medium)
                    TextField("YYYY-MM-DD", text: $procTargetDate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
            }

            HStack {
                Spacer()
                if procLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate POs") { runProcurement() }
                        .buttonStyle(.borderedProminent)
                        .disabled(procBomPath.isEmpty || procQuantity.isEmpty || procTargetDate.isEmpty)
                }
            }

            if let error = procError {
                errorBanner(error)
            }

            if let result = procResult,
               let vendors = result["vendors"] as? [[String: Any]] {
                let totalPOs = vendors.count
                let totalCost = result["total_cost"] as? Double ?? 0

                HStack(spacing: 16) {
                    statCard("\(totalPOs)", label: "Purchase Orders", color: .blue)
                    statCard(String(format: "$%.2f", totalCost), label: "Total Cost", color: .green)
                }

                ForEach(Array(vendors.enumerated()), id: \.offset) { _, vendor in
                    let vendorName = vendor["name"] as? String ?? "Unknown"
                    let items = vendor["items"] as? [[String: Any]] ?? []
                    let vendorTotal = vendor["total"] as? Double ?? 0

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(vendorName)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(String(format: "$%.2f", vendorTotal))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        }

                        VStack(spacing: 0) {
                            HStack {
                                Text("Part").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                                Text("Qty").font(.caption2).fontWeight(.bold).frame(width: 60)
                                Text("Unit").font(.caption2).fontWeight(.bold).frame(width: 80)
                                Text("Lead (d)").font(.caption2).fontWeight(.bold).frame(width: 60)
                                Spacer()
                            }
                            .padding(.vertical, 3).padding(.horizontal, 8)
                            .background(Color.gray.opacity(0.1))

                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(item["part"] as? String ?? "—")
                                        .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                                    Text("\(item["qty"] as? Int ?? 0)")
                                        .font(.system(size: 10, design: .monospaced)).frame(width: 60)
                                    Text(String(format: "$%.4f", item["unit_price"] as? Double ?? 0))
                                        .font(.system(size: 10, design: .monospaced)).frame(width: 80)
                                    Text("\(item["lead_days"] as? Int ?? 0)")
                                        .font(.system(size: 10, design: .monospaced)).frame(width: 60)
                                    Spacer()
                                }
                                .padding(.vertical, 2).padding(.horizontal, 8)
                            }
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                approveRejectButtons(
                    approveLabel: "Approve POs — Qualify AVL",
                    onApprove: { currentStation = .avlQualify }
                )
            }
        }
    }

    // MARK: - Station 2: AVL Qualify

    private var avlQualifyStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("AVL Qualify", description: "Check approved vendor list status for all BOM components", icon: "checkmark.seal")

            filePickerRow(label: "BOM File:", path: $avlBomPath, extensions: ["csv", "xlsx"])

            HStack {
                Spacer()
                if avlLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check AVL") { runAVL() }
                        .buttonStyle(.borderedProminent)
                        .disabled(avlBomPath.isEmpty)
                }
            }

            if let result = avlResult,
               let items = result["avl_items"] as? [[String: Any]] {
                let approved = items.filter { ($0["status"] as? String) == "approved" }.count
                let flagged = items.filter { ($0["status"] as? String) == "flagged" }.count
                let rejected = items.filter { ($0["status"] as? String) == "rejected" }.count

                HStack(spacing: 16) {
                    statCard("\(approved)", label: "Approved", color: .green)
                    statCard("\(flagged)", label: "Flagged", color: .orange)
                    statCard("\(rejected)", label: "Rejected", color: .red)
                }

                sectionLabel("AVL Status (\(items.count) components)")
                VStack(spacing: 0) {
                    HStack {
                        Text("Part").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                        Text("Manufacturer").font(.caption2).fontWeight(.bold).frame(width: 120, alignment: .leading)
                        Text("Vendor").font(.caption2).fontWeight(.bold).frame(width: 100, alignment: .leading)
                        Text("Status").font(.caption2).fontWeight(.bold).frame(width: 80)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let status = item["status"] as? String ?? "unknown"
                        HStack {
                            Text(item["part"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                            Text(item["manufacturer"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 120, alignment: .leading)
                            Text(item["vendor"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 100, alignment: .leading)
                            Text(status.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(
                                    status == "approved" ? Color.green.opacity(0.15) :
                                    status == "flagged" ? Color.orange.opacity(0.15) :
                                    Color.red.opacity(0.15)
                                )
                                .foregroundStyle(
                                    status == "approved" ? .green :
                                    status == "flagged" ? .orange :
                                    .red
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 80)
                            Spacer()
                        }
                        .padding(.vertical, 2).padding(.horizontal, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                approveRejectButtons(
                    approveLabel: "AVL Approved — Check Obsolescence",
                    onApprove: { currentStation = .obsolescenceCheck }
                )
            }
        }
    }

    // MARK: - Station 3: Obsolescence Check

    private var obsolescenceCheckStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Obsolescence Check", description: "Check component lifecycle status and end-of-life risk", icon: "exclamationmark.triangle")

            filePickerRow(label: "BOM File:", path: $obsBomPath, extensions: ["csv", "xlsx"])

            HStack {
                Spacer()
                if obsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Lifecycle") { runObsolescence() }
                        .buttonStyle(.borderedProminent)
                        .disabled(obsBomPath.isEmpty)
                }
            }

            if let result = obsResult,
               let items = result["lifecycle_items"] as? [[String: Any]] {
                let active = items.filter { ($0["status"] as? String) == "active" }.count
                let nrnd = items.filter { ($0["status"] as? String) == "nrnd" }.count
                let obsolete = items.filter { ($0["status"] as? String) == "obsolete" }.count

                HStack(spacing: 16) {
                    statCard("\(active)", label: "Active", color: .green)
                    statCard("\(nrnd)", label: "NRND", color: .orange)
                    statCard("\(obsolete)", label: "Obsolete", color: .red)
                }

                sectionLabel("Lifecycle Status (\(items.count) components)")
                VStack(spacing: 0) {
                    HStack {
                        Text("Part").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                        Text("Manufacturer").font(.caption2).fontWeight(.bold).frame(width: 120, alignment: .leading)
                        Text("Status").font(.caption2).fontWeight(.bold).frame(width: 80)
                        Text("Years Left").font(.caption2).fontWeight(.bold).frame(width: 70)
                        Text("Alt Available").font(.caption2).fontWeight(.bold).frame(width: 80)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let status = item["status"] as? String ?? "unknown"
                        let statusColor: Color = status == "active" ? .green : status == "nrnd" ? .orange : .red
                        HStack {
                            Text(item["part"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                            Text(item["manufacturer"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 120, alignment: .leading)
                            Text(status.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(statusColor.opacity(0.15))
                                .foregroundStyle(statusColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 80)
                            Text(item["years_left"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 70)
                            let altAvail = item["alt_available"] as? Bool ?? false
                            Image(systemName: altAvail ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(altAvail ? .green : .gray)
                                .font(.system(size: 10))
                                .frame(width: 80)
                            Spacer()
                        }
                        .padding(.vertical, 2).padding(.horizontal, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("Start Over") {
                        currentStation = .procurementApprove
                        procResult = nil; avlResult = nil; obsResult = nil
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Supply Chain Review Complete") {}
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Station Sidebar

    private var stationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pipeline")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()

            ForEach(Station.allCases, id: \.rawValue) { station in
                HStack(spacing: 8) {
                    Image(systemName: station.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(stationColor(station))
                        .frame(width: 16)

                    Text("\(station.rawValue). \(station.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(station == currentStation ? .primary : .secondary)

                    Spacer()

                    if station.rawValue < currentStation.rawValue {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else if station == currentStation {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(station == currentStation ? Color.accentColor.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    if station.rawValue <= currentStation.rawValue {
                        currentStation = station
                    }
                }
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func stationHeader(_ title: String, description: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3).fontWeight(.semibold)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func approveRejectButtons(approveLabel: String, onApprove: @escaping () -> Void) -> some View {
        HStack {
            Button("Reject") {
                currentStation = .procurementApprove
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Spacer()

            Button(approveLabel) { onApprove() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func statCard(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg).font(.caption)
        }
        .padding(8).background(Color.orange.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    @ViewBuilder
    private func filePickerRow(label: String, path: Binding<String>, extensions: [String]) -> some View {
        HStack {
            Text(label).font(.caption).fontWeight(.medium)
            if path.wrappedValue.isEmpty {
                Button("Select...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
                    panel.message = "Select file"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path.wrappedValue = url.path
                }
                .buttonStyle(.bordered)
            } else {
                Text(URL(fileURLWithPath: path.wrappedValue).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
                    panel.message = "Select file"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path.wrappedValue = url.path
                }) {
                    Image(systemName: "folder").font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stationColor(_ station: Station) -> Color {
        if station.rawValue < currentStation.rawValue { return .green }
        if station == currentStation { return .blue }
        return .gray
    }

    // MARK: - Actions

    private func runProcurement() {
        procLoading = true; procError = nil; procResult = nil
        Task {
            do {
                let _ = procBomPath; let _ = procQuantity; let _ = procTargetDate
                // Placeholder: let result = try await PartsAPIClient.shared.supplyChainProcure(...)
                let result: [String: Any] = [:]
                await MainActor.run { procResult = result; procLoading = false }
            } catch {
                await MainActor.run { procError = error.localizedDescription; procLoading = false }
            }
        }
    }

    private func runAVL() {
        avlLoading = true; avlResult = nil
        Task {
            do {
                let _ = avlBomPath
                // Placeholder: let result = try await PartsAPIClient.shared.supplyChainAVL(...)
                let result: [String: Any] = [:]
                await MainActor.run { avlResult = result; avlLoading = false }
            } catch {
                await MainActor.run { avlLoading = false }
            }
        }
    }

    private func runObsolescence() {
        obsLoading = true; obsResult = nil
        Task {
            do {
                let _ = obsBomPath
                // Placeholder: let result = try await PartsAPIClient.shared.supplyChainObsolescence(...)
                let result: [String: Any] = [:]
                await MainActor.run { obsResult = result; obsLoading = false }
            } catch {
                await MainActor.run { obsLoading = false }
            }
        }
    }
}
#endif
