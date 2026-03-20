import Foundation

/// Bridges to the `parts` CLI binary for API operations.
class CLIBridge {
    static let shared = CLIBridge()

    private var partsPath: String? {
        // Check common locations
        let paths = [
            "/opt/homebrew/bin/parts",
            "/usr/local/bin/parts",
            ProcessInfo.processInfo.environment["HOME"].map { "\($0)/.local/bin/parts" },
        ].compactMap { $0 }

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try `which parts`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["parts"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == false ? result : nil
    }

    func run(_ arguments: [String]) async throws -> String {
        guard let path = partsPath else {
            throw CLIError.notFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw CLIError.failed(output)
        }
        return output
    }

    enum CLIError: LocalizedError {
        case notFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "parts CLI not found in PATH"
            case .failed(let msg): return msg
            }
        }
    }
}
