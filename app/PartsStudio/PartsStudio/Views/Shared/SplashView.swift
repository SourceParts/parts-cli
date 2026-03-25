import SwiftUI

struct SplashView: View {
    @State private var bounce: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Use the app icon (picker claw logo) from the bundle
            if let icon = NSApplication.shared.applicationIconImage {
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
