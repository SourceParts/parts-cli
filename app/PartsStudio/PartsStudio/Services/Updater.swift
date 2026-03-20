import Foundation
import AppKit

/// Self-update mechanism for Parts Studio.
/// Pulls latest from git, rebuilds with swift build, copies binary to app bundle, relaunches.
class Updater: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var status: String = ""
    @Published var hasUpdate = false
    @Published var currentCommit: String = ""
    @Published var latestCommit: String = ""
    @Published var error: String?

    private let repoPath: String
    private let appBundlePath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.repoPath = "\(home)/Work/SourceParts/parts-cli/app/PartsStudio"
        self.appBundlePath = "\(home)/Applications/Parts Studio.app"
    }

    // MARK: - Check for updates

    func checkForUpdates() {
        isChecking = true
        error = nil
        status = "Checking for updates..."

        Task {
            do {
                // Get current local commit
                let localCommit = try await shell("git", "-C", repoPath, "rev-parse", "--short", "HEAD")

                // Fetch from remote
                _ = try? await shell("git", "-C", repoPath, "fetch", "origin", "main", "--quiet")

                // Get remote commit
                let remoteCommit = try await shell("git", "-C", repoPath, "rev-parse", "--short", "origin/main")

                await MainActor.run {
                    currentCommit = localCommit
                    latestCommit = remoteCommit
                    hasUpdate = localCommit != remoteCommit
                    isChecking = false
                    status = hasUpdate ? "Update available (\(remoteCommit))" : "Up to date (\(localCommit))"
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isChecking = false
                    self.status = "Check failed"
                }
            }
        }
    }

    // MARK: - Perform update

    func performUpdate() {
        isUpdating = true
        error = nil

        Task {
            do {
                // Step 1: Pull latest
                await setStatus("Pulling latest changes...")
                _ = try await shell("git", "-C", repoPath, "pull", "origin", "main", "--ff-only")

                // Step 2: Build
                await setStatus("Building Parts Studio...")
                let swiftPath = try await findSwift()
                _ = try await shell(swiftPath, "build", "--package-path", repoPath)

                // Step 3: Copy binary to app bundle
                await setStatus("Installing update...")
                let builtBinary = "\(repoPath)/.build/arm64-apple-macosx/debug/PartsStudio"
                let appBinary = "\(appBundlePath)/Contents/MacOS/PartsStudio"

                let fm = FileManager.default
                if fm.fileExists(atPath: appBinary) {
                    try fm.removeItem(atPath: appBinary)
                }
                try fm.copyItem(atPath: builtBinary, toPath: appBinary)

                // Step 4: Also rebuild parts CLI
                await setStatus("Rebuilding parts CLI...")
                let goPath = try? await findGo()
                if let goPath = goPath {
                    let cliRepo = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Work/SourceParts/parts-cli"
                    let cliDest = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/parts"
                    _ = try? await shell(goPath, "build", "-o", cliDest, "\(cliRepo)/cmd/parts/...")
                }

                // Step 5: Get new commit
                let newCommit = try await shell("git", "-C", repoPath, "rev-parse", "--short", "HEAD")

                await MainActor.run {
                    currentCommit = newCommit
                    latestCommit = newCommit
                    hasUpdate = false
                    isUpdating = false
                    status = "Updated to \(newCommit). Restart to apply."
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isUpdating = false
                    self.status = "Update failed"
                }
            }
        }
    }

    // MARK: - Relaunch

    func relaunch() {
        let appURL = URL(fileURLWithPath: appBundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Helpers

    private func shell(_ args: String...) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())

        // Inherit PATH
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(env["PATH"] ?? "/usr/bin")"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw UpdateError.commandFailed(output)
        }
        return output
    }

    private func findSwift() async throws -> String {
        for path in ["/opt/homebrew/bin/swift", "/usr/bin/swift"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        throw UpdateError.commandFailed("swift not found")
    }

    private func findGo() async throws -> String {
        for path in ["/opt/homebrew/bin/go", "/usr/local/go/bin/go", "/usr/local/bin/go"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        throw UpdateError.commandFailed("go not found")
    }

    @MainActor
    private func setStatus(_ s: String) {
        status = s
    }

    enum UpdateError: LocalizedError {
        case commandFailed(String)
        var errorDescription: String? {
            switch self {
            case .commandFailed(let msg): return msg
            }
        }
    }
}
