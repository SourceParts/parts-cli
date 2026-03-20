import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the app to be a regular foreground app that accepts keyboard input
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure we stay activated when clicked
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PartsStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import PDF...") {
                    appState.showImportPanel = true
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
            ToolCommands(appState: appState)
        }
    }
}

struct ToolCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Tools") {
            ForEach(ToolMode.allCases) { mode in
                Button(mode.label) {
                    appState.currentTool = mode
                }
                .keyboardShortcut(mode.shortcut, modifiers: [.command])
            }

            Divider()

            Button("Strip Metadata") {
                appState.showStripMetadata = true
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(appState.selectedDatasheet == nil)

            Button("Export with Redactions...") {
                appState.showExport = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.selectedDatasheet == nil)
        }
    }
}
