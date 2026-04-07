import SwiftUI

struct SplashView: View {
    @State private var bounce: Bool = false

    /// Load the app icon — try the .icns next to the source tree first, then fall back to the bundle icon.
    private var appIcon: NSImage? {
        // SwiftPM builds don't embed the icon in the app bundle, so load from the known path.
        let iconPaths = [
            Bundle.main.path(forResource: "PartsStudio", ofType: "icns"),
            Bundle.main.path(forResource: "AppIcon", ofType: "png"),
        ].compactMap { $0 }

        for path in iconPaths {
            if let img = NSImage(contentsOfFile: path) { return img }
        }

        // Fallback: try alongside the binary (SwiftPM debug layout)
        if let execURL = Bundle.main.executableURL {
            let sibling = execURL.deletingLastPathComponent()
            for name in ["PartsStudio.icns", "AppIcon.png"] {
                let url = sibling.appendingPathComponent(name)
                if let img = NSImage(contentsOf: url) { return img }
            }
            // Walk up to find the project root (where build.sh lives)
            var dir = execURL.deletingLastPathComponent()
            for _ in 0..<10 {
                let icns = dir.appendingPathComponent("PartsStudio.icns")
                if FileManager.default.fileExists(atPath: icns.path),
                   let img = NSImage(contentsOf: icns) {
                    return img
                }
                dir = dir.deletingLastPathComponent()
            }
        }

        return NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 20) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .scaleEffect(bounce ? 1.05 : 0.95)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            bounce = true
                        }
                    }
            }

            Text("Parts Studio")
                .font(.title)
                .fontWeight(.bold)

            ProgressView()
                .controlSize(.small)

            Text("Loading project...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
