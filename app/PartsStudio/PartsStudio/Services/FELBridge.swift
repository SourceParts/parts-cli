import Foundation
import WebKit

/// Bridge between Parts Studio and fel.js for Allwinner FEL USB boot operations.
/// Loads fel.js in a hidden WKWebView and communicates via message handlers.
///
/// NOTE: WebUSB requires a secure context (HTTPS) and user gesture for device selection.
/// For native USB access without browser restrictions, we fall back to sunxi-fel CLI.
class FELBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var isConnected = false
    @Published var socInfo: String = ""
    @Published var sid: String = ""
    @Published var status: String = "Disconnected"
    @Published var log: [String] = []

    private var webView: WKWebView?
    private var felJSPath: String?

    override init() {
        super.init()
        setupWebView()
    }

    // MARK: - WebView Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "felBridge")
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = nil

        // Find fel.js in the bundle
        if let felPath = Bundle.main.path(forResource: "fel", ofType: "js", inDirectory: "FEL") {
            felJSPath = felPath
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "connected":
                self.isConnected = true
                self.socInfo = body["soc"] as? String ?? ""
                self.sid = body["sid"] as? String ?? ""
                self.status = "Connected: \(self.socInfo)"
                self.appendLog("FEL device connected: \(self.socInfo)")

            case "disconnected":
                self.isConnected = false
                self.status = "Disconnected"
                self.appendLog("FEL device disconnected")

            case "log":
                if let msg = body["message"] as? String {
                    self.appendLog(msg)
                }

            case "progress":
                if let pct = body["percent"] as? Int {
                    self.status = "Transfer: \(pct)%"
                }

            case "error":
                let msg = body["message"] as? String ?? "Unknown error"
                self.status = "Error: \(msg)"
                self.appendLog("ERROR: \(msg)")

            default:
                break
            }
        }
    }

    // MARK: - FEL Operations (via sunxi-fel CLI fallback)

    func getVersion() async -> String? {
        let result = try? await runFEL(["ver"])
        if let output = result {
            DispatchQueue.main.async {
                self.isConnected = true
                self.socInfo = output
                self.status = "Connected"
                self.appendLog("FEL: \(output)")
            }
        }
        return result
    }

    func getSID() async -> String? {
        let result = try? await runFEL(["sid"])
        if let output = result {
            DispatchQueue.main.async {
                self.sid = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.appendLog("SID: \(self.sid)")
            }
        }
        return result
    }

    func loadSPL(_ path: String) async throws {
        appendLog("Loading SPL: \(path)")
        let result = try await runFEL(["spl", path])
        appendLog("SPL loaded: \(result)")
    }

    func writeMemory(address: UInt32, path: String) async throws {
        appendLog("Writing \(path) to 0x\(String(address, radix: 16))")
        let result = try await runFEL(["write", "0x\(String(address, radix: 16))", path])
        appendLog("Write complete: \(result)")
    }

    func execute(address: UInt32) async throws {
        appendLog("Executing at 0x\(String(address, radix: 16))")
        let _ = try await runFEL(["exe", "0x\(String(address, radix: 16))"])
        appendLog("Execution started")
    }

    func readSPIFlash(offset: UInt32, size: UInt32, outputPath: String) async throws {
        appendLog("Reading SPI flash: offset=0x\(String(offset, radix: 16)) size=\(size)")
        let result = try await runFEL(["spiflash-read", "0x\(String(offset, radix: 16))", String(size), outputPath])
        appendLog("SPI read complete: \(result)")
    }

    func writeSPIFlash(offset: UInt32, inputPath: String) async throws {
        appendLog("Writing SPI flash: offset=0x\(String(offset, radix: 16))")
        let result = try await runFEL(["spiflash-write", "0x\(String(offset, radix: 16))", inputPath])
        appendLog("SPI write complete: \(result)")
    }

    func hexdump(address: UInt32, length: UInt32) async -> String? {
        return try? await runFEL(["hexdump", "0x\(String(address, radix: 16))", String(length)])
    }

    // MARK: - Boot sequence

    func bootPocketPC(splPath: String? = nil, ubootPath: String? = nil) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let spl = splPath ?? "\(home)/Work/PocketPC-Uboot/spl/sunxi-spl.bin"
        let uboot = ubootPath ?? "\(home)/Work/PocketPC-Uboot/u-boot.bin"

        appendLog("=== FEL Boot Sequence ===")

        try await loadSPL(spl)
        appendLog("Waiting for DRAM init...")
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s

        try await writeMemory(address: 0x4a000000, path: uboot)
        try await execute(address: 0x4a000000)

        appendLog("U-Boot booting via FEL")
        status = "U-Boot loaded"
    }

    // MARK: - Helpers

    private func runFEL(_ args: [String]) async throws -> String {
        let felPath = findFEL()
        guard let path = felPath else {
            throw FELError.notFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw FELError.failed(output)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findFEL() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/.local/bin/sunxi-fel",
            "\(home)/Work/sunxi-tools/sunxi-fel",
            "/opt/homebrew/bin/sunxi-fel",
            "/usr/local/bin/sunxi-fel",
        ]
        return paths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func appendLog(_ msg: String) {
        DispatchQueue.main.async {
            self.log.append("[\(Self.timestamp())] \(msg)")
            if self.log.count > 200 { self.log = Array(self.log.suffix(200)) }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    enum FELError: LocalizedError {
        case notFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "sunxi-fel not found"
            case .failed(let msg): return msg
            }
        }
    }
}
