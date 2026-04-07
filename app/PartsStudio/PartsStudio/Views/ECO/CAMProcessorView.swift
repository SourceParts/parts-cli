#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// CAM Processor — unified manufacturing workflow: gerber preview, DFM, placement, BOM, quoting.
struct CAMProcessorView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: CAMTab = .overview

    // DFM state
    @State private var dfmJobId: String?
    @State private var dfmResult: PartsAPIClient.DFMResult?
    @State private var dfmPolling = false
    @State private var dfmError: String?

    // Quote state
    @State private var fabQuote: PartsAPIClient.FabQuote?
    @State private var quoteQuantity: Int = 5
    @State private var quoteLayers: Int = 4
    @State private var quoteLoading = false
    @State private var quoteError: String?

    // Placement state
    @State private var placementResult: PartsAPIClient.PlacementResult?
    @State private var placementLoading = false
    @State private var placementError: String?
    @State private var placementTopImage: NSImage?
    @State private var placementBottomImage: NSImage?
    @State private var placementSide: String = "top"

    // BOM state
    @State private var bomJobId: String?
    @State private var bomStatus: PartsAPIClient.BOMStatus?
    @State private var bomDetail: PartsAPIClient.BOMDetail?
    @State private var bomPolling = false
    @State private var bomError: String?
    @State private var bomId: String?

    // COGS state
    @State private var cogsResult: PartsAPIClient.COGSResult?
    @State private var cogsQuantity: Int = 100
    @State private var cogsLoading = false
    @State private var cogsError: String?

    // Gerber preview
    @State private var renderedImage: NSImage?
    @State private var isRendering = false
    @State private var zoomLevel: CGFloat = 1.0
    @State private var mouseCoord: CGPoint?
    @State private var bounds: GerbvRenderer.GerberBounds?

    private let renderer = GerbvRenderer()
    private var config: PartsConfig { PartsConfig.shared }

    enum CAMTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case dfm = "DFM"
        case bom = "BOM"
        case placement = "Placement"
        case quote = "Quote"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "cpu"
            case .dfm: return "checkmark.shield"
            case .bom: return "tablecells"
            case .placement: return "square.on.square.dashed"
            case .quote: return "dollarsign.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                mainContent
                    .frame(minWidth: 500)
                inspectorPanel
                    .frame(width: 280)
            }
        }
        .onAppear { loadGerberPreview() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.2")
                .foregroundStyle(Color.accentColor)
            Text("CAM Processor")
                .font(.headline)

            Divider().frame(height: 20)

            ForEach(CAMTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            if !config.projectId.isEmpty {
                Text(config.teamName.isEmpty ? config.projectId : config.teamName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(config.revision)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .overview: overviewTab
        case .dfm: dfmTab
        case .bom: bomTab
        case .placement: placementTab
        case .quote: quoteTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(spacing: 0) {
            if let img = renderedImage {
                ZoomableImageView(
                    image: img,
                    zoomLevel: $zoomLevel,
                    boardBounds: bounds,
                    mouseCoord: $mouseCoord,
                    measureMode: false,
                    measureA: .constant(nil),
                    measureB: .constant(nil)
                )
            } else if isRendering {
                ZStack {
                    Color.black
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Rendering board preview...")
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.caption)
                    }
                }
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("No gerber files found")
                            .foregroundStyle(.white.opacity(0.4))
                            .font(.caption)
                        Text("Place gerber files in \(config.fabReleasePath)")
                            .foregroundStyle(.white.opacity(0.3))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    // MARK: - DFM Tab

    private var dfmTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Design for Manufacturability")
                            .font(.title3).fontWeight(.semibold)
                        Text("Analyze gerber files for manufacturing issues")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if dfmPolling {
                        ProgressView().controlSize(.small)
                        Text("Analyzing...").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(action: { runDFM() }) {
                            HStack(spacing: 4) { Image(systemName: "play.fill"); Text("Run DFM") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(config.projectId.isEmpty)
                    }
                }

                if let error = dfmError { errorBanner(error) }

                if let result = dfmResult {
                    dfmResultView(result)
                } else if dfmJobId == nil {
                    emptyState(icon: "checkmark.shield", text: "Click \"Run DFM\" to analyze your design")
                }
            }
            .padding(24)
        }
    }

    // MARK: - BOM Tab

    private var bomTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bill of Materials")
                            .font(.title3).fontWeight(.semibold)
                        Text("Upload and process BOM for part matching and costing")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if bomPolling {
                        ProgressView().controlSize(.small)
                        Text("Processing...").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(action: { pickBOMFile() }) {
                            HStack(spacing: 4) { Image(systemName: "arrow.up.doc"); Text("Upload BOM") }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let error = bomError { errorBanner(error) }

                // BOM status
                if let status = bomStatus {
                    bomStatusView(status)
                }

                // BOM detail table
                if let detail = bomDetail {
                    bomDetailView(detail)
                }

                // COGS section (only when BOM is processed)
                if let bId = bomId {
                    Divider().padding(.vertical, 8)
                    cogsSection(bomId: bId)
                }

                if bomJobId == nil && bomDetail == nil {
                    emptyState(icon: "tablecells", text: "Upload a BOM file (CSV, XLSX) to match parts and calculate costs")
                }
            }
            .padding(24)
        }
    }

    // MARK: - Placement Tab

    private var placementTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Placement Generation")
                            .font(.title3).fontWeight(.semibold)
                        Text("Generate pick-and-place files from position CSV")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if placementLoading {
                        ProgressView().controlSize(.small)
                        Text("Generating...").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(action: { pickPositionFile() }) {
                            HStack(spacing: 4) { Image(systemName: "arrow.up.doc"); Text("Upload Position File") }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let error = placementError { errorBanner(error) }

                if placementTopImage != nil || placementBottomImage != nil {
                    placementResultView
                } else if placementResult == nil {
                    emptyState(icon: "square.on.square.dashed", text: "Upload a position file (CSV) to generate placement visualizations")
                }
            }
            .padding(24)
        }
    }

    // MARK: - Quote Tab

    private var quoteTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fabrication Quote")
                            .font(.title3).fontWeight(.semibold)
                        Text("Get pricing for PCB fabrication")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantity").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $quoteQuantity) {
                            ForEach([5, 10, 25, 50, 100, 250, 500], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.menu).frame(width: 100)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Layers").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $quoteLayers) {
                            ForEach([2, 4, 6, 8], id: \.self) { Text("\($0)L").tag($0) }
                        }
                        .pickerStyle(.menu).frame(width: 80)
                    }
                    Spacer()
                    if quoteLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: { fetchQuote() }) {
                            HStack(spacing: 4) { Image(systemName: "dollarsign.circle"); Text("Get Quote") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(config.projectId.isEmpty)
                    }
                }

                if let error = quoteError { errorBanner(error) }

                if let quote = fabQuote {
                    quoteResultView(quote)
                } else {
                    emptyState(icon: "dollarsign.circle", text: "Configure parameters and click \"Get Quote\"")
                }
            }
            .padding(24)
        }
    }

    // MARK: - DFM Result Subviews

    @ViewBuilder
    private func dfmResultView(_ result: PartsAPIClient.DFMResult) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 8).frame(width: 80, height: 80)
                Circle().trim(from: 0, to: CGFloat(result.score) / 100.0)
                    .stroke(dfmScoreColor(result.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 80, height: 80)
                VStack(spacing: 0) {
                    Text("\(result.score)").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("/ 100").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(dfmScoreLabel(result.score)).font(.headline).foregroundStyle(dfmScoreColor(result.score))
                Text("Status: \(result.status)").font(.caption).foregroundStyle(.secondary)
                if !result.warnings.isEmpty {
                    Text("\(result.warnings.count) warning(s)").font(.caption).foregroundStyle(.orange)
                }
            }
        }

        if !result.checks.isEmpty {
            sectionLabel("Checks")
            ForEach(Array(result.checks.enumerated()), id: \.offset) { _, check in
                HStack(spacing: 8) {
                    Image(systemName: check.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.pass ? .green : .red).font(.caption)
                    Text(check.name).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(check.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }

        if !result.warnings.isEmpty {
            sectionLabel("Warnings")
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, w in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 9))
                    Text(w).font(.system(size: 11))
                }
            }
        }

        if !result.recommendations.isEmpty {
            sectionLabel("Recommendations")
            ForEach(Array(result.recommendations.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.blue).font(.system(size: 9))
                    Text(r).font(.system(size: 11))
                }
            }
        }
    }

    // MARK: - BOM Subviews

    @ViewBuilder
    private func bomStatusView(_ status: PartsAPIClient.BOMStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if status.status == "processing" {
                    ProgressView(value: Double(status.progress), total: 100.0)
                        .frame(width: 120)
                    Text("\(status.progress)%").font(.caption).foregroundStyle(.secondary)
                } else if status.status == "complete" {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Processing complete").font(.caption).foregroundStyle(.green)
                } else if status.status == "failed" {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Processing failed").font(.caption).foregroundStyle(.red)
                }
                Spacer()
            }

            if status.totalLines > 0 {
                HStack(spacing: 16) {
                    statBadge("\(status.totalLines)", label: "Lines", color: .blue)
                    statBadge("\(status.matched)", label: "Matched", color: .green)
                    statBadge("\(status.unmatched)", label: "Unmatched", color: status.unmatched > 0 ? .orange : .green)
                }
            }
        }
    }

    @ViewBuilder
    private func bomDetailView(_ detail: PartsAPIClient.BOMDetail) -> some View {
        sectionLabel("BOM Lines (\(detail.lines.count))")

        // Table header
        HStack(spacing: 0) {
            Text("Ref").frame(width: 60, alignment: .leading)
            Text("Value").frame(width: 100, alignment: .leading)
            Text("Footprint").frame(width: 100, alignment: .leading)
            Text("MPN").frame(width: 140, alignment: .leading)
            Text("Manufacturer").frame(width: 120, alignment: .leading)
            Text("Price").frame(width: 60, alignment: .trailing)
            Text("Status").frame(width: 60, alignment: .center)
            Spacer()
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 4))

        ForEach(Array(detail.lines.prefix(50).enumerated()), id: \.offset) { _, line in
            HStack(spacing: 0) {
                Text(line.reference).frame(width: 60, alignment: .leading)
                Text(line.value).frame(width: 100, alignment: .leading).lineLimit(1)
                Text(line.footprint).frame(width: 100, alignment: .leading).lineLimit(1)
                Text(line.mpn).frame(width: 140, alignment: .leading).lineLimit(1)
                Text(line.manufacturer).frame(width: 120, alignment: .leading).lineLimit(1)
                if let price = line.unitPrice {
                    Text(String(format: "$%.3f", price)).frame(width: 60, alignment: .trailing)
                } else {
                    Text("—").frame(width: 60, alignment: .trailing).foregroundStyle(.tertiary)
                }
                Image(systemName: line.matched ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(line.matched ? .green : .orange)
                    .frame(width: 60)
                Spacer()
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }

        if detail.lines.count > 50 {
            Text("Showing 50 of \(detail.lines.count) lines")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - COGS Section

    @ViewBuilder
    private func cogsSection(bomId: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assembly Cost (COGS)")
                    .font(.system(size: 13, weight: .semibold))
                Text("Combined BOM + labor + overhead")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Build Qty").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $cogsQuantity) {
                    ForEach([10, 25, 50, 100, 250, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu).frame(width: 100)
            }

            if cogsLoading {
                ProgressView().controlSize(.small)
            } else {
                Button(action: { fetchCOGS(bomId: bomId) }) {
                    HStack(spacing: 4) { Image(systemName: "function"); Text("Calculate") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }

        if let error = cogsError { errorBanner(error) }

        if let cogs = cogsResult {
            cogsResultView(cogs)
        }
    }

    @ViewBuilder
    private func cogsResultView(_ cogs: PartsAPIClient.COGSResult) -> some View {
        VStack(spacing: 12) {
            // Summary cards
            HStack(spacing: 12) {
                quoteCard("COGS / Unit", value: String(format: "$%.2f", cogs.cogsPerUnit), color: .green)
                quoteCard("Total COGS", value: String(format: "$%.2f", cogs.cogsTotal), color: .blue)
                quoteCard("Build Qty", value: "\(cogs.buildQuantity)", color: .purple)
            }

            // Breakdown table
            VStack(spacing: 4) {
                cogsRow("BOM Cost", perUnit: cogs.bomCostPerUnit, total: cogs.bomCostTotal)
                cogsRow("Labor", perUnit: cogs.laborPerBoard, total: cogs.laborTotal)
                cogsRow("Overhead", perUnit: cogs.overheadPerBoard, total: cogs.overheadTotal)
                Divider()
                cogsRow("COGS", perUnit: cogs.cogsPerUnit, total: cogs.cogsTotal, bold: true)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func cogsRow(_ label: String, perUnit: Double, total: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: bold ? .semibold : .regular))
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(String(format: "$%.3f / unit", perUnit))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(bold ? .primary : .secondary)
            Text(String(format: "$%.2f total", total))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(bold ? .primary : .tertiary)
                .frame(width: 100, alignment: .trailing)
        }
    }

    // MARK: - Placement Subviews

    @ViewBuilder
    private var placementResultView: some View {
        // Side toggle
        Picker("Side", selection: $placementSide) {
            Text("Top").tag("top")
            Text("Bottom").tag("bottom")
        }
        .pickerStyle(.segmented)
        .frame(width: 200)

        let img = placementSide == "top" ? placementTopImage : placementBottomImage
        if let img = img {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        } else {
            Text("No \(placementSide) image available")
                .font(.caption).foregroundStyle(.secondary)
        }

        // Output files
        if let result = placementResult {
            sectionLabel("Generated Files")
            HStack(spacing: 12) {
                if let path = result.pdfPath { fileLink("Placement PDF", path: path, icon: "doc.richtext") }
                if let path = result.csvPath { fileLink("Machine CSV", path: path, icon: "tablecells") }
                if let path = result.feederMapPath { fileLink("Feeder Map", path: path, icon: "list.bullet") }
            }
        }
    }

    // MARK: - Quote Subviews

    @ViewBuilder
    private func quoteResultView(_ quote: PartsAPIClient.FabQuote) -> some View {
        HStack(spacing: 12) {
            quoteCard("Unit Price", value: String(format: "$%.2f", quote.unitPrice), color: .green)
            quoteCard("Total", value: String(format: "$%.2f", quote.totalPrice), color: .blue)
            quoteCard("Quantity", value: "\(quote.quantity) pcs", color: .purple)
            quoteCard("Lead Time", value: quote.leadTime.isEmpty ? "TBD" : quote.leadTime, color: .orange)
        }
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Board Info").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    infoSection("Project") {
                        infoRow("Name", config.teamName.isEmpty ? "—" : config.teamName)
                        infoRow("Revision", config.revision)
                        infoRow("Project ID", config.projectId.isEmpty ? "Not set" : config.projectId)
                    }
                    Divider()
                    infoSection("Paths") {
                        pathRow("Fab Release", config.fabReleasePath)
                        pathRow("BOM", config.bomPath)
                        pathRow("Assembly", config.assemblyPath)
                    }
                    Divider()
                    infoSection("Actions") {
                        Button(action: { loadGerberPreview() }) {
                            Label("Refresh Preview", systemImage: "arrow.clockwise").font(.caption)
                        }.buttonStyle(.link)
                        Button(action: { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: config.fabReleasePath) }) {
                            Label("Open Fab Folder", systemImage: "folder").font(.caption)
                        }.buttonStyle(.link)
                        Button(action: { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: config.bomPath) }) {
                            Label("Open BOM Folder", systemImage: "folder").font(.caption)
                        }.buttonStyle(.link)
                    }
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Shared UI Components

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    @ViewBuilder
    private func quoteCard(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statBadge(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 70)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func fileLink(_ label: String, path: String, icon: String) -> some View {
        Button(action: { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func infoSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
    }

    @ViewBuilder
    private func pathRow(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func dfmScoreColor(_ score: Int) -> Color {
        score >= 80 ? .green : score >= 60 ? .orange : .red
    }

    private func dfmScoreLabel(_ score: Int) -> String {
        score >= 90 ? "Excellent" : score >= 80 ? "Good" : score >= 60 ? "Needs Attention" : "Issues Found"
    }

    // MARK: - Actions

    private func loadGerberPreview() {
        let fabPath = config.fabReleasePath
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: fabPath) else { return }

        let gerberExts: Set<String> = ["gbr", "gtl", "gbl", "gts", "gbs", "gto", "gbo", "gtp", "gbp", "gm1", "gko", "drl", "xln"]
        let gerberFiles = files.filter { f in
            let ext = URL(fileURLWithPath: f).pathExtension.lowercased()
            return gerberExts.contains(ext) || (ext.hasPrefix("g") && ext.count <= 4 && Int(ext.dropFirst()) != nil)
        }.sorted().map { "\(fabPath)/\($0)" }

        guard !gerberFiles.isEmpty else { return }
        isRendering = true

        let layerConfigs = gerberFiles.map { path in
            let type = PCBLayerClassifier.classify(filename: URL(fileURLWithPath: path).lastPathComponent)
            return GerbvRenderer.LayerConfig(
                path: path,
                color: type.type.defaultColor,
                alpha: 1.0,
                isVisible: true
            )
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = renderer.render(layers: layerConfigs, width: 2400, height: 1600)
            DispatchQueue.main.async {
                renderedImage = result?.image
                bounds = result?.bounds
                isRendering = false
                zoomLevel = 0
            }
        }
    }

    private func runDFM() {
        guard !config.projectId.isEmpty else { dfmError = "No project_id in .parts/config.yaml"; return }
        dfmError = nil; dfmResult = nil; dfmPolling = true
        Task {
            do {
                let jobId = try await PartsAPIClient.shared.submitDFM(projectId: config.projectId)
                await MainActor.run { dfmJobId = jobId }
                for _ in 0..<60 {
                    let result = try await PartsAPIClient.shared.checkDFMStatus(jobId: jobId)
                    if result.status == "complete" || result.status == "failed" {
                        await MainActor.run { dfmResult = result; dfmPolling = false }
                        return
                    }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }
                await MainActor.run { dfmError = "DFM analysis timed out"; dfmPolling = false }
            } catch {
                await MainActor.run { dfmError = error.localizedDescription; dfmPolling = false }
            }
        }
    }

    private func fetchQuote() {
        guard !config.projectId.isEmpty else { quoteError = "No project_id in .parts/config.yaml"; return }
        quoteError = nil; quoteLoading = true
        Task {
            do {
                let quote = try await PartsAPIClient.shared.quoteFabrication(
                    projectId: config.projectId, quantity: quoteQuantity, layers: quoteLayers
                )
                await MainActor.run { fabQuote = quote; quoteLoading = false }
            } catch {
                await MainActor.run { quoteError = error.localizedDescription; quoteLoading = false }
            }
        }
    }

    private func pickBOMFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "csv")!,
            UTType(filenameExtension: "xlsx")!,
            UTType(filenameExtension: "xls")!,
        ]
        panel.allowsMultipleSelection = false
        panel.message = "Select BOM file"
        panel.directoryURL = URL(fileURLWithPath: config.bomPath)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        uploadBOM(url: url)
    }

    private func uploadBOM(url: URL) {
        bomError = nil; bomPolling = true; bomDetail = nil; bomId = nil; bomStatus = nil; cogsResult = nil
        Task {
            do {
                let result = try await PartsAPIClient.shared.uploadBOM(fileURL: url)
                await MainActor.run { bomJobId = result.jobId }

                // Poll for completion
                for _ in 0..<60 {
                    let status = try await PartsAPIClient.shared.checkBOMStatus(jobId: result.jobId)
                    await MainActor.run { bomStatus = status }

                    if status.status == "complete" {
                        await MainActor.run { bomId = status.bomId; bomPolling = false }
                        // Fetch detail
                        if let bId = status.bomId {
                            let detail = try await PartsAPIClient.shared.getBOMDetail(bomId: bId)
                            await MainActor.run { bomDetail = detail }
                        }
                        return
                    } else if status.status == "failed" {
                        await MainActor.run { bomError = "BOM processing failed"; bomPolling = false }
                        return
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
                await MainActor.run { bomError = "BOM processing timed out"; bomPolling = false }
            } catch {
                await MainActor.run { bomError = error.localizedDescription; bomPolling = false }
            }
        }
    }

    private func fetchCOGS(bomId: String) {
        cogsError = nil; cogsLoading = true
        Task {
            do {
                let result = try await PartsAPIClient.shared.calculateCOGS(bomId: bomId, buildQuantity: cogsQuantity)
                await MainActor.run { cogsResult = result; cogsLoading = false }
            } catch {
                await MainActor.run { cogsError = error.localizedDescription; cogsLoading = false }
            }
        }
    }

    private func pickPositionFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select position/placement file (CSV)"

        // Try to default to assembly dir
        let assemblyPath = config.assemblyPath
        if FileManager.default.fileExists(atPath: assemblyPath) {
            panel.directoryURL = URL(fileURLWithPath: assemblyPath)
        }

        guard panel.runModal() == .OK, let posURL = panel.url else { return }
        generatePlacement(positionFile: posURL)
    }

    private func generatePlacement(positionFile: URL) {
        placementError = nil; placementLoading = true; placementResult = nil
        placementTopImage = nil; placementBottomImage = nil

        // Try to find gerbers ZIP in fab release path
        let fabPath = config.fabReleasePath
        var gerbersZip: URL? = nil
        if let files = try? FileManager.default.contentsOfDirectory(atPath: fabPath) {
            if let zip = files.first(where: { $0.hasSuffix(".zip") }) {
                gerbersZip = URL(fileURLWithPath: "\(fabPath)/\(zip)")
            }
        }

        // Try to find BOM file
        var bomFile: URL? = nil
        if let files = try? FileManager.default.contentsOfDirectory(atPath: config.bomPath) {
            if let csv = files.first(where: { $0.lowercased().hasSuffix(".csv") }) {
                bomFile = URL(fileURLWithPath: "\(config.bomPath)/\(csv)")
            }
        }

        Task {
            do {
                let result = try await PartsAPIClient.shared.generatePlacement(
                    positionFile: positionFile,
                    bomFile: bomFile,
                    gerbersZip: gerbersZip,
                    boardName: config.teamName,
                    side: "both"
                )
                await MainActor.run {
                    placementResult = result
                    if let path = result.topImagePath { placementTopImage = NSImage(contentsOfFile: path) }
                    if let path = result.bottomImagePath { placementBottomImage = NSImage(contentsOfFile: path) }
                    placementLoading = false
                }
            } catch {
                await MainActor.run { placementError = error.localizedDescription; placementLoading = false }
            }
        }
    }
}
#endif
