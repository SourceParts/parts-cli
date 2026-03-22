import SwiftUI

struct AOIImageResult: Codable {
    let filename: String
    var verdict: String  // "pending", "pass", "fail"
    var notes: String
    let handlerBallCount: Int
    let handlerVoidPct: Double
    let handlerBridging: Bool
    let handlerUniformity: Double
    let handlerVerdict: String
}

struct IQCAOIReviewView: View {
    let item: IQCItem
    @State private var currentIndex = 0
    @State private var results: [AOIImageResult] = []
    @State private var overlayImages: [String] = []
    @State private var showReport = false
    @State private var noteText = ""
    @State private var zoomScale: CGFloat = 1.0

    private let aoiDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Work/aoi_review").path
    private let analysisPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Work/xray_analysis_results.json").path

    var body: some View {
        if showReport {
            reportView
        } else if results.isEmpty {
            loadingView
        } else {
            reviewView
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading AOI overlay images...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadData() }
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            // Top bar: progress + stats
            HStack(spacing: 12) {
                Text("Image \(currentIndex + 1) of \(results.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                ProgressView(value: Double(reviewedCount), total: Double(results.count))
                    .frame(width: 120)

                Text("\(reviewedCount)/\(results.count) reviewed")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Handler findings
                let r = results[currentIndex]
                HStack(spacing: 8) {
                    statBadge("Balls: \(r.handlerBallCount)", .blue)
                    statBadge("Void: \(String(format: "%.1f", r.handlerVoidPct))%",
                              r.handlerVoidPct > 25 ? .red : r.handlerVoidPct > 10 ? .orange : .green)
                    statBadge("Bridge: \(r.handlerBridging ? "YES" : "NO")",
                              r.handlerBridging ? .red : .green)
                    statBadge("Unif: \(String(format: "%.2f", r.handlerUniformity))",
                              r.handlerUniformity < 0.7 ? .orange : .green)
                    statBadge("Auto: \(r.handlerVerdict.uppercased())",
                              r.handlerVerdict == "pass" ? .green : .red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Image viewer
            ZStack {
                Color.black

                if currentIndex < overlayImages.count {
                    OverlayImageView(path: overlayImages[currentIndex], zoomScale: $zoomScale)
                }

                // Verdict overlay badge
                if results[currentIndex].verdict != "pending" {
                    VStack {
                        HStack {
                            Spacer()
                            Text(results[currentIndex].verdict.uppercased())
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(results[currentIndex].verdict == "pass" ?
                                            Color.green.opacity(0.9) : Color.red.opacity(0.9))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(12)
                        }
                        Spacer()
                    }
                }
            }

            Divider()

            // Bottom bar: notes + actions
            HStack(spacing: 8) {
                // Navigation
                Button(action: { if currentIndex > 0 { currentIndex -= 1; noteText = results[currentIndex].notes } }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button(action: { if currentIndex < results.count - 1 { currentIndex += 1; noteText = results[currentIndex].notes } }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex >= results.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])

                Divider().frame(height: 20)

                // Filename
                Text(results[currentIndex].filename)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Divider().frame(height: 20)

                // Notes
                TextField("Notes (optional)...", text: $noteText)
                    .font(.system(size: 11))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .onSubmit { results[currentIndex].notes = noteText }
                    .onChange(of: noteText) { results[currentIndex].notes = noteText }

                Spacer()

                // Zoom
                Button(action: { zoomScale = 1.0 }) {
                    Text("1:1")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Divider().frame(height: 20)

                // PASS / FAIL
                Button(action: { markVerdict("pass") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("PASS")
                    }
                    .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.small)
                .keyboardShortcut("p", modifiers: .command)

                Button(action: { markVerdict("fail") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("FAIL")
                    }
                    .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .keyboardShortcut("f", modifiers: .command)

                Divider().frame(height: 20)

                // Generate report
                Button(action: { generateReport() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text("Report")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(reviewedCount < results.count)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    // MARK: - Report

    private var reportView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AOI Calibration Report")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("nRF54H20 Main Board V1.03 — IQC Lot 3.10")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Reviewed: \(Date().formatted(date: .long, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Back to Review") { showReport = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Divider()

                // Summary
                let humanPass = results.filter { $0.verdict == "pass" }.count
                let humanFail = results.filter { $0.verdict == "fail" }.count
                let autoPass = results.filter { $0.handlerVerdict == "pass" }.count
                let autoFail = results.filter { $0.handlerVerdict == "fail" }.count
                let falsePositives = results.filter { $0.handlerVerdict == "fail" && $0.verdict == "pass" }.count
                let falseNegatives = results.filter { $0.handlerVerdict == "pass" && $0.verdict == "fail" }.count

                HStack(spacing: 20) {
                    summaryCard("Human", pass: humanPass, fail: humanFail, color: .blue)
                    summaryCard("Handler", pass: autoPass, fail: autoFail, color: .purple)
                    VStack(spacing: 4) {
                        Text("Discrepancies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(falsePositives + falseNegatives)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(falsePositives + falseNegatives > 0 ? .orange : .green)
                        HStack(spacing: 8) {
                            Text("FP: \(falsePositives)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text("FN: \(falseNegatives)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                Divider()

                // Per-image table
                Text("Per-Image Results")
                    .font(.headline)

                VStack(spacing: 0) {
                    // Header row
                    HStack {
                        Text("Image").frame(width: 80, alignment: .leading)
                        Text("Balls").frame(width: 50)
                        Text("Void %").frame(width: 60)
                        Text("Bridge").frame(width: 55)
                        Text("Unif").frame(width: 50)
                        Text("Auto").frame(width: 50)
                        Text("Human").frame(width: 55)
                        Text("Match").frame(width: 45)
                        Text("Notes").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))

                    ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                        let match = r.verdict == r.handlerVerdict
                        HStack {
                            Text(r.filename).frame(width: 80, alignment: .leading)
                            Text("\(r.handlerBallCount)").frame(width: 50)
                            Text(String(format: "%.1f", r.handlerVoidPct)).frame(width: 60)
                            Text(r.handlerBridging ? "YES" : "NO").frame(width: 55)
                                .foregroundStyle(r.handlerBridging ? .red : .green)
                            Text(String(format: "%.2f", r.handlerUniformity)).frame(width: 50)
                            Text(r.handlerVerdict.uppercased()).frame(width: 50)
                                .foregroundStyle(r.handlerVerdict == "pass" ? .green : .red)
                            Text(r.verdict.uppercased()).frame(width: 55)
                                .foregroundStyle(r.verdict == "pass" ? .green : .red)
                            Image(systemName: match ? "checkmark" : "xmark")
                                .frame(width: 45)
                                .foregroundStyle(match ? .green : .orange)
                            Text(r.notes)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(match ? Color.clear : Color.orange.opacity(0.05))

                        if r.filename != results.last?.filename {
                            Divider()
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Save button
                HStack {
                    Spacer()
                    Button(action: { saveReport() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Report")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private var reviewedCount: Int {
        results.filter { $0.verdict != "pending" }.count
    }

    private func statBadge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func summaryCard(_ title: String, pass: Int, fail: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                VStack {
                    Text("\(pass)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("PASS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(fail)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                    Text("FAIL")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func markVerdict(_ verdict: String) {
        results[currentIndex].verdict = verdict
        results[currentIndex].notes = noteText

        // Auto-advance to next unreviewed
        if currentIndex < results.count - 1 {
            currentIndex += 1
            noteText = results[currentIndex].notes
        }

        // Auto-show report when all reviewed
        if reviewedCount == results.count {
            showReport = true
        }
    }

    private func loadData() {
        // Load overlay images
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: aoiDir) {
            overlayImages = files.filter { $0.hasSuffix(".png") }
                .sorted()
                .map { "\(aoiDir)/\($0)" }
        }

        // Load analysis results
        guard let data = fm.contents(atPath: analysisPath),
              let analysis = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        results = analysis.enumerated().map { i, entry in
            AOIImageResult(
                filename: entry["filename"] as? String ?? "image_\(i).bmp",
                verdict: "pending",
                notes: "",
                handlerBallCount: entry["ball_count"] as? Int ?? 0,
                handlerVoidPct: entry["void_percentage"] as? Double ?? 0,
                handlerBridging: entry["bridging_detected"] as? Bool ?? false,
                handlerUniformity: entry["uniformity_score"] as? Double ?? 0,
                handlerVerdict: entry["pass_fail"] as? String ?? "unknown"
            )
        }
    }

    private func generateReport() {
        showReport = true
    }

    private func saveReport() {
        let reportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Work/Consulting/nRF54H20-Main-Board/Reports")
        let reportPath = reportDir.appendingPathComponent("AOI_Calibration_Report.json")

        let report: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "board": "nRF54H20 Main Board V1.03",
            "lot": "3.10",
            "total_images": results.count,
            "human_pass": results.filter { $0.verdict == "pass" }.count,
            "human_fail": results.filter { $0.verdict == "fail" }.count,
            "handler_pass": results.filter { $0.handlerVerdict == "pass" }.count,
            "handler_fail": results.filter { $0.handlerVerdict == "fail" }.count,
            "false_positives": results.filter { $0.handlerVerdict == "fail" && $0.verdict == "pass" }.count,
            "false_negatives": results.filter { $0.handlerVerdict == "pass" && $0.verdict == "fail" }.count,
            "results": results.map { r in
                [
                    "filename": r.filename,
                    "human_verdict": r.verdict,
                    "handler_verdict": r.handlerVerdict,
                    "notes": r.notes,
                    "ball_count": "\(r.handlerBallCount)",
                    "void_pct": String(format: "%.1f", r.handlerVoidPct),
                    "bridging": r.handlerBridging ? "true" : "false",
                    "uniformity": String(format: "%.3f", r.handlerUniformity)
                ]
            }
        ]

        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportPath)
        }
    }
}

// MARK: - Zoomable Image View

struct OverlayImageView: NSViewRepresentable {
    let path: String
    @Binding var zoomScale: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 5.0
        scrollView.magnification = 1.0
        scrollView.backgroundColor = .black

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        if let img = loadImage(from: path) {
            imageView.image = img
            imageView.frame = NSRect(origin: .zero, size: img.size)
        }

        scrollView.documentView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }

        if let img = loadImage(from: path) {
            if imageView.image?.tiffRepresentation != img.tiffRepresentation {
                imageView.image = img
                imageView.frame = NSRect(origin: .zero, size: img.size)
            }
        }

        if abs(scrollView.magnification - zoomScale) > 0.01 {
            scrollView.magnification = zoomScale
        }
    }

    private func loadImage(from path: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        if let img = NSImage(contentsOf: url) { return img }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
