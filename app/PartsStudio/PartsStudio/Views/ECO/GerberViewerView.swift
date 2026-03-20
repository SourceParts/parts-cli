import SwiftUI

struct GerberViewerView: View {
    let filePaths: [String]
    @State private var renderedImage: NSImage?
    @State private var isRendering = false
    @State private var error: String?
    @State private var selectedLayers: Set<Int> = []

    private var layerNames: [(Int, String, Color)] {
        let colors: [Color] = [.red, .green, .yellow, .blue, .purple, .cyan, .orange, .pink]
        return filePaths.enumerated().map { i, path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (i, name, colors[i % colors.count])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(Color.accentColor)
                Text("Gerber Viewer")
                    .font(.headline)
                Spacer()

                if isRendering {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Rendering...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: render) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-render")
                .disabled(isRendering)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HSplitView {
                // Image view
                if let img = renderedImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .contextMenu {
                                Button("Copy Image") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.writeObjects([img])
                                }
                                Button("Save PNG...") {
                                    saveImage(img)
                                }
                            }
                    }
                } else if let err = error {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { render() }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack {
                        Spacer()
                        ProgressView("Rendering Gerber layers...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }

                // Layer list
                VStack(alignment: .leading, spacing: 0) {
                    Text("Layers (\(filePaths.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(layerNames, id: \.0) { index, name, color in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(selectedLayers.contains(index) || selectedLayers.isEmpty ? color : color.opacity(0.3))
                                        .frame(width: 10, height: 10)
                                    Text(name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(selectedLayers.contains(index) || selectedLayers.isEmpty ? .primary : .tertiary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedLayers.contains(index) {
                                        selectedLayers.remove(index)
                                    } else {
                                        selectedLayers.insert(index)
                                    }
                                }
                                .contextMenu {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.selectFile(filePaths[index], inFileViewerRootedAtPath: "")
                                    }
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            Button("Show All") {
                                selectedLayers.removeAll()
                                render()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                            .padding(.horizontal, 10)

                            Button("Render Selected") {
                                render()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                            .padding(.horizontal, 10)
                            .disabled(selectedLayers.isEmpty)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onAppear { render() }
    }

    private func render() {
        isRendering = true
        error = nil

        let paths: [String]
        if selectedLayers.isEmpty {
            paths = filePaths
        } else {
            paths = selectedLayers.sorted().compactMap { i in
                i < filePaths.count ? filePaths[i] : nil
            }
        }

        Task {
            do {
                let img = try await renderGerber(paths: paths)
                await MainActor.run {
                    renderedImage = img
                    isRendering = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isRendering = false
                }
            }
        }
    }

    private func renderGerber(paths: [String]) async throws -> NSImage {
        let renderTool = findGerbvRender()
        guard let tool = renderTool else {
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "gerbv-render not found.\nInstall with: brew install gerbv\nThen build tools/gerbv-render.c"])
        }

        let outputPath = NSTemporaryDirectory() + "parts_gerber_\(UUID().uuidString).png"
        var args = [outputPath, "2400", "1600", "--bg", "000000"]
        args.append(contentsOf: paths)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let img = NSImage(contentsOfFile: outputPath) else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: errStr])
        }

        try? FileManager.default.removeItem(atPath: outputPath)
        return img
    }

    private func findGerbvRender() -> String? {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/gerbv-render",
            "/opt/homebrew/bin/gerbv-render",
            "/usr/local/bin/gerbv-render",
        ]
        return paths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func saveImage(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "gerber_render.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
    }
}
