#if os(macOS)
import Foundation

/// Local HTTP server on localhost:9801 for remote control of the FEL console.
/// Send commands via: curl localhost:9801/cmd?q=info
/// Get log via: curl localhost:9801/log
/// Get device info via: curl localhost:9801/device
class FELConsoleServer {
    private var serverSocket: Int32 = -1
    private let port: UInt16 = 9801
    private let acceptQueue = DispatchQueue(label: "parts.studio.console.server.accept", qos: .utility)
    private var running = false

    var onCommand: ((String) -> String)?
    var getLog: (() -> [String])?
    var getDeviceJSON: (() -> String)?
    var onReload: (() -> String)?
    var onSetRevision: ((String) -> String)?
    var onNavigate: ((String) -> String)?
    var getESLRDeviceJSON: (() -> String)?

    init() {}

    func start() {
        guard !running else { return }
        running = true
        acceptQueue.async { [weak self] in
            self?.listen()
        }
    }

    func stop() {
        running = false
        let fd = serverSocket
        serverSocket = -1
        if fd >= 0 {
            // Shutting down the socket unblocks the blocking accept() call
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }

    private func listen() {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            running = false
            return
        }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEPORT, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = UInt32(0x7F000001).bigEndian // 127.0.0.1

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverSocket)
            serverSocket = -1
            running = false
            return
        }

        guard Darwin.listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            serverSocket = -1
            running = false
            return
        }

        while running && serverSocket >= 0 {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientAddrLen)
                }
            }
            guard client >= 0 else {
                // accept failed — if we're still supposed to be running, just retry;
                // otherwise the socket was closed by stop(), so exit the loop.
                continue
            }

            // Handle each client on a concurrent queue so the accept loop is never blocked
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(client)
            }
        }

        running = false
    }

    private func handleClient(_ client: Int32) {
        defer { close(client) }

        // Set a read timeout so a misbehaving client can't block this thread forever
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        let path = parseRequestPath(request)

        let (status, contentType, body) = handleRoute(path)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"

        // Send using the known byte count, not strlen, to handle the full response correctly
        let data = Array(response.utf8)
        data.withUnsafeBufferPointer { bufferPtr in
            guard let base = bufferPtr.baseAddress else { return }
            var totalSent = 0
            while totalSent < data.count {
                let sent = send(client, base + totalSent, data.count - totalSent, 0)
                if sent <= 0 { break }
                totalSent += sent
            }
        }
    }

    private func parseRequestPath(_ request: String) -> String {
        // GET /path?query HTTP/1.1
        let lines = request.split(separator: "\r\n")
        guard let first = lines.first else { return "/" }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private func handleRoute(_ path: String) -> (String, String, String) {
        let components = URLComponents(string: path)
        let route = components?.path ?? "/"
        let queryItems = components?.queryItems ?? []
        let queryMap = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        switch route {
        case "/cmd":
            guard let cmd = queryMap["q"], !cmd.isEmpty else {
                return ("400 Bad Request", "application/json", "{\"error\":\"missing ?q= parameter\"}")
            }
            let result = onCommand?(cmd) ?? "no handler"
            let escaped = result.replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return ("200 OK", "application/json", "{\"command\":\"\(cmd)\",\"result\":\"\(escaped)\"}")

        case "/log":
            let lines = getLog?() ?? []
            let json = lines.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
                .joined(separator: ",")
            return ("200 OK", "application/json", "{\"log\":[\(json)]}")

        case "/device":
            let json = getDeviceJSON?() ?? "{}"
            return ("200 OK", "application/json", json)

        case "/eslr":
            let json = getESLRDeviceJSON?() ?? "{\"connected\":false}"
            return ("200 OK", "application/json", json)

        case "/status":
            return ("200 OK", "application/json", "{\"status\":\"ok\",\"port\":\(port)}")

        case "/reload":
            let result = onReload?() ?? "{\"error\":\"no handler\"}"
            return ("200 OK", "application/json", result)

        case "/revision":
            if let newRev = queryMap["set"], !newRev.isEmpty {
                let result = onSetRevision?(newRev) ?? "{\"error\":\"no handler\"}"
                return ("200 OK", "application/json", result)
            }
            let config = PartsConfig.shared
            return ("200 OK", "application/json", "{\"revision\":\"\(config.revision)\",\"assembly\":\"\(config.assemblyPath)\",\"fab_release\":\"\(config.fabReleasePath)\"}")

        case "/navigate":
            guard let view = queryMap["view"], !view.isEmpty else {
                return ("400 Bad Request", "application/json", "{\"error\":\"missing ?view= parameter. Options: fel, iqc, eco, usb, credits, search, datasheets\"}")
            }
            let result = onNavigate?(view) ?? "{\"error\":\"no handler\"}"
            return ("200 OK", "application/json", result)

        case "/":
            let help = """
            {"endpoints":{"/cmd?q=<command>":"Execute console command","/log":"Get console log","/device":"Get FEL device info","/eslr":"Get ESLR radio info","/status":"Server status","/reload":"Reload config and refresh assembly","/revision":"Show current revision","/revision?set=EVT1":"Switch board variant","/navigate?view=<name>":"Navigate to view (fel, eslr, iqc, eco, usb, credits, search, datasheets)"}}
            """
            return ("200 OK", "application/json", help)

        default:
            return ("404 Not Found", "application/json", "{\"error\":\"not found\"}")
        }
    }
}
#endif
