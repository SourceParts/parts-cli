#if os(iOS)
import SwiftUI

@main
struct PartsStudioApp_iOS: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            iOSContentView()
                .environmentObject(appState)
        }
    }
}
#endif
