#if os(macOS)
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
        WindowGroup("Parts Studio") {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
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
            AppearanceCommands(appState: appState)
            FELCommands(appState: appState)
            UpdateCommands(updater: appState.updater)
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

            Divider()

            Button("Export Annotations (JSON)...") {
                appState.showExportAnnotations = true
            }
            .disabled(appState.annotationStore.annotations.annotations.isEmpty)

            Button("Export Labels (CSV)...") {
                appState.showExportLabels = true
            }
            .disabled(appState.dataLabelStore.labels.isEmpty)

            Button("Export Page as PNG...") {
                appState.showExportPagePNG = true
            }
            .disabled(appState.pdfDocument == nil)
        }
    }
}

struct AppearanceCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Appearance") {
            ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                Button(mode.label) {
                    appState.appearanceMode = mode
                }
                .disabled(appState.appearanceMode == mode)
            }
        }
    }
}

struct FELCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("FEL") {
            Button("Show FEL Device") {
                appState.showFEL = true
                appState.selectedDatasheet = nil
                appState.selectedECO = nil
                appState.selectedIQCItem = nil
                appState.selectedAssemblyDoc = nil
                appState.showCredits = false
                appState.showUSBMonitor = false
                appState.pdfDocument = nil
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Connect FEL") {
                appState.felService.connect()
            }
            .disabled(appState.felService.connectionState == .connected)

            Button("Disconnect FEL") {
                appState.felService.disconnect()
            }
            .disabled(appState.felService.connectionState != .connected)
        }
    }
}

struct UpdateCommands: Commands {
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandMenu("Update") {
            Button("Check for Updates...") {
                updater.checkForUpdates()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(updater.isChecking || updater.isUpdating)

            if updater.hasUpdate {
                Button("Install Update (\(updater.latestCommit))") {
                    updater.performUpdate()
                }
                .disabled(updater.isUpdating)
            }

            if updater.status.contains("Restart") {
                Button("Restart Parts Studio") {
                    updater.relaunch()
                }
            }

            Divider()

            if !updater.status.isEmpty {
                Text(updater.status)
            }
            if !updater.currentCommit.isEmpty {
                Text("Current: \(updater.currentCommit)")
            }
        }
    }
}
#endif
