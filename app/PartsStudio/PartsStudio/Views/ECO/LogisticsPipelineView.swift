#if os(macOS)
import SwiftUI
import AppKit

/// Logistics Pipeline: Shipment creation through inventory reconciliation.
struct LogisticsPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStation: Station = .shipmentCreate

    // Station 1: Shipment Create
    @State private var orderID: String = ""
    @State private var destination: String = ""
    @State private var carrier: String = "DHL"
    @State private var weight: String = ""
    @State private var shipmentResult: [String: Any]?
    @State private var shipmentLoading = false
    @State private var shipmentError: String?

    // Station 2: Track
    @State private var shipmentID: String = ""
    @State private var trackResult: [String: Any]?
    @State private var trackLoading = false

    // Station 3: Customs Declare
    @State private var customsBomPath: String = ""
    @State private var invoiceAmount: String = ""
    @State private var destinationCountry: String = ""
    @State private var customsResult: [String: Any]?
    @State private var customsLoading = false

    // Station 4: Consignment Manifest
    @State private var manifestBomPath: String = ""
    @State private var inventoryJSONPath: String = ""
    @State private var cmAddress: String = ""
    @State private var manifestResult: [String: Any]?
    @State private var manifestLoading = false

    // Station 5: Inventory Reconcile
    @State private var physicalCountPath: String = ""
    @State private var systemCountPath: String = ""
    @State private var reconcileResult: [String: Any]?
    @State private var reconcileLoading = false

    enum Station: Int, CaseIterable {
        case shipmentCreate = 1
        case track = 2
        case customsDeclare = 3
        case consignmentManifest = 4
        case inventoryReconcile = 5

        var title: String {
            switch self {
            case .shipmentCreate: return "Shipment Create"
            case .track: return "Track"
            case .customsDeclare: return "Customs Declare"
            case .consignmentManifest: return "Consignment Manifest"
            case .inventoryReconcile: return "Inventory Reconcile"
            }
        }

        var icon: String {
            switch self {
            case .shipmentCreate: return "shippingbox"
            case .track: return "location"
            case .customsDeclare: return "doc.badge.gearshape"
            case .consignmentManifest: return "list.bullet.clipboard"
            case .inventoryReconcile: return "arrow.triangle.2.circlepath.doc.on.clipboard"
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
            Image(systemName: "shippingbox")
                .foregroundStyle(Color.accentColor)
            Text("Logistics Pipeline")
                .font(.headline)
            Divider().frame(height: 20)

            Text("Station \(currentStation.rawValue)/5")
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
        case .shipmentCreate: shipmentCreateStation
        case .track: trackStation
        case .customsDeclare: customsDeclareStation
        case .consignmentManifest: consignmentManifestStation
        case .inventoryReconcile: inventoryReconcileStation
        }
    }

    // MARK: - Station 1: Shipment Create

    private var shipmentCreateStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Shipment Create", description: "Create a new shipment with carrier and destination", icon: "shippingbox")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Order ID:").font(.caption).fontWeight(.medium)
                    TextField("e.g. ORD-2026-001", text: $orderID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }

                HStack {
                    Text("Destination:").font(.caption).fontWeight(.medium)
                    TextField("City, Country", text: $destination)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }

                HStack {
                    Text("Carrier:").font(.caption).fontWeight(.medium)
                    Picker("", selection: $carrier) {
                        Text("DHL").tag("DHL")
                        Text("FedEx").tag("FedEx")
                        Text("SF Express").tag("SF Express")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                HStack {
                    Text("Weight (kg):").font(.caption).fontWeight(.medium)
                    TextField("e.g. 2.5", text: $weight)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            HStack {
                Spacer()
                if shipmentLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Create Shipment") { runShipmentCreate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(orderID.isEmpty || destination.isEmpty || weight.isEmpty)
                }
            }

            if let error = shipmentError {
                errorBanner(error)
            }

            if let result = shipmentResult {
                let sid = result["shipment_id"] as? String ?? "—"
                let trackingNum = result["tracking_number"] as? String ?? "—"
                let estDays = result["estimated_days"] as? Int ?? 0

                HStack(spacing: 16) {
                    statCard(sid, label: "Shipment ID", color: .blue)
                    statCard(trackingNum, label: "Tracking #", color: .purple)
                    statCard("\(estDays)d", label: "Est. Transit", color: .orange)
                }

                approveRejectButtons(
                    approveLabel: "Proceed to Tracking",
                    onApprove: {
                        shipmentID = sid
                        currentStation = .track
                    }
                )
            }
        }
    }

    // MARK: - Station 2: Track

    private var trackStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Track Shipment", description: "Monitor shipment progress in real time", icon: "location")

            HStack {
                Text("Shipment ID:").font(.caption).fontWeight(.medium)
                TextField("e.g. SHP-001", text: $shipmentID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                if trackLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Track") { runTrack() }
                        .buttonStyle(.borderedProminent)
                        .disabled(shipmentID.isEmpty)
                }
            }

            if let result = trackResult,
               let events = result["events"] as? [[String: Any]] {
                let status = result["status"] as? String ?? "—"
                statCard(status.uppercased(), label: "Current Status", color: status == "delivered" ? .green : .blue)

                sectionLabel("Tracking Timeline (\(events.count) events)")
                ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                    HStack(alignment: .top, spacing: 10) {
                        VStack {
                            Circle()
                                .fill(idx == 0 ? Color.blue : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            if idx < events.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 2, height: 24)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event["description"] as? String ?? "—")
                                .font(.system(size: 11))
                            Text(event["timestamp"] as? String ?? "")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(event["location"] as? String ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                approveRejectButtons(
                    approveLabel: "Proceed to Customs",
                    onApprove: { currentStation = .customsDeclare }
                )
            }
        }
    }

    // MARK: - Station 3: Customs Declare

    private var customsDeclareStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Customs Declaration", description: "Generate HS codes and customs documentation", icon: "doc.badge.gearshape")

            VStack(alignment: .leading, spacing: 8) {
                filePickerRow(label: "BOM File:", path: $customsBomPath, extensions: ["csv", "xlsx"])

                HStack {
                    Text("Invoice Amount ($):").font(.caption).fontWeight(.medium)
                    TextField("e.g. 15000.00", text: $invoiceAmount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }

                HStack {
                    Text("Destination Country:").font(.caption).fontWeight(.medium)
                    TextField("e.g. US, DE, CN", text: $destinationCountry)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            HStack {
                Spacer()
                if customsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate HS Codes") { runCustoms() }
                        .buttonStyle(.borderedProminent)
                        .disabled(customsBomPath.isEmpty || invoiceAmount.isEmpty || destinationCountry.isEmpty)
                }
            }

            if let result = customsResult,
               let codes = result["hs_codes"] as? [[String: Any]] {
                sectionLabel("HS Code Table (\(codes.count) items)")
                VStack(spacing: 0) {
                    HStack {
                        Text("Part").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                        Text("HS Code").font(.caption2).fontWeight(.bold).frame(width: 100, alignment: .leading)
                        Text("Description").font(.caption2).fontWeight(.bold).frame(minWidth: 120, alignment: .leading)
                        Text("Duty %").font(.caption2).fontWeight(.bold).frame(width: 60)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(Array(codes.enumerated()), id: \.offset) { _, code in
                        HStack {
                            Text(code["part"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                            Text(code["hs_code"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 100, alignment: .leading)
                            Text(code["description"] as? String ?? "—")
                                .font(.system(size: 10)).frame(minWidth: 120, alignment: .leading)
                            Text(String(format: "%.1f%%", code["duty_rate"] as? Double ?? 0))
                                .font(.system(size: 10, design: .monospaced)).frame(width: 60)
                            Spacer()
                        }
                        .padding(.vertical, 2).padding(.horizontal, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                approveRejectButtons(
                    approveLabel: "Customs Approved — Proceed to Manifest",
                    onApprove: { currentStation = .consignmentManifest }
                )
            }
        }
    }

    // MARK: - Station 4: Consignment Manifest

    private var consignmentManifestStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Consignment Manifest", description: "Generate manifest for CM shipment", icon: "list.bullet.clipboard")

            VStack(alignment: .leading, spacing: 8) {
                filePickerRow(label: "BOM File:", path: $manifestBomPath, extensions: ["csv", "xlsx"])
                filePickerRow(label: "Inventory JSON:", path: $inventoryJSONPath, extensions: ["json"])

                HStack {
                    Text("CM Address:").font(.caption).fontWeight(.medium)
                    TextField("Contract manufacturer address", text: $cmAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
            }

            HStack {
                Spacer()
                if manifestLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Generate Manifest") { runManifest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(manifestBomPath.isEmpty || inventoryJSONPath.isEmpty || cmAddress.isEmpty)
                }
            }

            if let result = manifestResult,
               let items = result["manifest_items"] as? [[String: Any]] {
                let totalItems = items.count
                let totalQty = result["total_quantity"] as? Int ?? 0

                HStack(spacing: 16) {
                    statCard("\(totalItems)", label: "Line Items", color: .blue)
                    statCard("\(totalQty)", label: "Total Qty", color: .purple)
                }

                sectionLabel("Manifest Table")
                VStack(spacing: 0) {
                    HStack {
                        Text("Part").font(.caption2).fontWeight(.bold).frame(width: 120, alignment: .leading)
                        Text("Qty").font(.caption2).fontWeight(.bold).frame(width: 60)
                        Text("Package").font(.caption2).fontWeight(.bold).frame(width: 80, alignment: .leading)
                        Text("Reel/Bag").font(.caption2).fontWeight(.bold).frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))

                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item["part"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 120, alignment: .leading)
                            Text("\(item["qty"] as? Int ?? 0)")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 60)
                            Text(item["package"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 80, alignment: .leading)
                            Text(item["packaging"] as? String ?? "—")
                                .font(.system(size: 10, design: .monospaced)).frame(width: 80, alignment: .leading)
                            Spacer()
                        }
                        .padding(.vertical, 2).padding(.horizontal, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                approveRejectButtons(
                    approveLabel: "Manifest Approved — Reconcile Inventory",
                    onApprove: { currentStation = .inventoryReconcile }
                )
            }
        }
    }

    // MARK: - Station 5: Inventory Reconcile

    private var inventoryReconcileStation: some View {
        VStack(alignment: .leading, spacing: 16) {
            stationHeader("Inventory Reconcile", description: "Compare physical count against system records", icon: "arrow.triangle.2.circlepath.doc.on.clipboard")

            VStack(alignment: .leading, spacing: 8) {
                filePickerRow(label: "Physical Count CSV:", path: $physicalCountPath, extensions: ["csv"])
                filePickerRow(label: "System Count CSV:", path: $systemCountPath, extensions: ["csv"])
            }

            HStack {
                Spacer()
                if reconcileLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Reconcile") { runReconcile() }
                        .buttonStyle(.borderedProminent)
                        .disabled(physicalCountPath.isEmpty || systemCountPath.isEmpty)
                }
            }

            if let result = reconcileResult {
                let matched = result["matched"] as? Int ?? 0
                let discrepancies = result["discrepancies"] as? Int ?? 0
                let diffs = result["diff_items"] as? [[String: Any]] ?? []

                HStack(spacing: 16) {
                    statCard("\(matched)", label: "Matched", color: .green)
                    statCard("\(discrepancies)", label: "Discrepancies", color: discrepancies > 0 ? .red : .green)
                }

                if !diffs.isEmpty {
                    sectionLabel("Reconciliation Diff (\(diffs.count) items)")
                    VStack(spacing: 0) {
                        HStack {
                            Text("Part").font(.caption2).fontWeight(.bold).frame(width: 140, alignment: .leading)
                            Text("Physical").font(.caption2).fontWeight(.bold).frame(width: 70)
                            Text("System").font(.caption2).fontWeight(.bold).frame(width: 70)
                            Text("Delta").font(.caption2).fontWeight(.bold).frame(width: 70)
                            Spacer()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(Color.gray.opacity(0.1))

                        ForEach(Array(diffs.enumerated()), id: \.offset) { _, diff in
                            let delta = (diff["physical"] as? Int ?? 0) - (diff["system"] as? Int ?? 0)
                            HStack {
                                Text(diff["part"] as? String ?? "—")
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 140, alignment: .leading)
                                Text("\(diff["physical"] as? Int ?? 0)")
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 70)
                                Text("\(diff["system"] as? Int ?? 0)")
                                    .font(.system(size: 10, design: .monospaced)).frame(width: 70)
                                Text("\(delta > 0 ? "+" : "")\(delta)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(delta == 0 ? .green : .red)
                                    .frame(width: 70)
                                Spacer()
                            }
                            .padding(.vertical, 2).padding(.horizontal, 8)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Button("Start Over") {
                        currentStation = .shipmentCreate
                        shipmentResult = nil; trackResult = nil; customsResult = nil
                        manifestResult = nil; reconcileResult = nil
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Logistics Complete") {}
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
                currentStation = .shipmentCreate
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

    private func runShipmentCreate() {
        shipmentLoading = true; shipmentError = nil; shipmentResult = nil
        Task {
            do {
                let _ = orderID; let _ = destination; let _ = carrier; let _ = weight
                // Placeholder: let result = try await PartsAPIClient.shared.logisticsCreateShipment(...)
                let result: [String: Any] = [:]
                await MainActor.run { shipmentResult = result; shipmentLoading = false }
            } catch {
                await MainActor.run { shipmentError = error.localizedDescription; shipmentLoading = false }
            }
        }
    }

    private func runTrack() {
        trackLoading = true; trackResult = nil
        Task {
            do {
                let _ = shipmentID
                // Placeholder: let result = try await PartsAPIClient.shared.logisticsTrack(...)
                let result: [String: Any] = [:]
                await MainActor.run { trackResult = result; trackLoading = false }
            } catch {
                await MainActor.run { trackLoading = false }
            }
        }
    }

    private func runCustoms() {
        customsLoading = true; customsResult = nil
        Task {
            do {
                let _ = customsBomPath; let _ = invoiceAmount; let _ = destinationCountry
                // Placeholder: let result = try await PartsAPIClient.shared.logisticsCustomsDeclare(...)
                let result: [String: Any] = [:]
                await MainActor.run { customsResult = result; customsLoading = false }
            } catch {
                await MainActor.run { customsLoading = false }
            }
        }
    }

    private func runManifest() {
        manifestLoading = true; manifestResult = nil
        Task {
            do {
                let _ = manifestBomPath; let _ = inventoryJSONPath; let _ = cmAddress
                // Placeholder: let result = try await PartsAPIClient.shared.logisticsManifest(...)
                let result: [String: Any] = [:]
                await MainActor.run { manifestResult = result; manifestLoading = false }
            } catch {
                await MainActor.run { manifestLoading = false }
            }
        }
    }

    private func runReconcile() {
        reconcileLoading = true; reconcileResult = nil
        Task {
            do {
                let _ = physicalCountPath; let _ = systemCountPath
                // Placeholder: let result = try await PartsAPIClient.shared.logisticsReconcile(...)
                let result: [String: Any] = [:]
                await MainActor.run { reconcileResult = result; reconcileLoading = false }
            } catch {
                await MainActor.run { reconcileLoading = false }
            }
        }
    }
}
#endif
