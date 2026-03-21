import Foundation

/// Local HTTP server on localhost:9801 for remote control of the FEL console.
/// Send commands via: curl localhost:9801/cmd?q=info
/// Get log via: curl localhost:9801/log
/// Get device info via: curl localhost:9801/device
class FELConsoleServer {
    private var listener: FileHandle?
    private var serverSocket: Int32 = -1
    private let port: UInt16 = 9801
    private let queue = DispatchQueue(label: "parts.studio.console.server", qos: .utility)

    var onCommand: ((String) -> String)?
    var getLog: (() -> [String])?
    var getDeviceJSON: (() -> String)?

    init() {}

    func start() {
        queue.async { [weak self] in
            self?.listen()
        }
    }

    func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func listen() {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
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
            return
        }

        Darwin.listen(serverSocket, 5)

        while serverSocket >= 0 {
            let client = accept(serverSocket, nil, nil)
            guard client >= 0 else { continue }

            queue.async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ client: Int32) {
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(client, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        let path = parseRequestPath(request)

        let (status, contentType, body) = handleRoute(path)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"

        _ = response.withCString { ptr in
            send(client, ptr, strlen(ptr), 0)
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

        case "/status":
            return ("200 OK", "application/json", "{\"status\":\"ok\",\"port\":\(port)}")

        case "/":
            let help = """
            {"endpoints":{"/cmd?q=<command>":"Execute console command","/log":"Get console log","/device":"Get device info","/status":"Server status"}}
            """
            return ("200 OK", "application/json", help)

        default:
            return ("404 Not Found", "application/json", "{\"error\":\"not found\"}")
        }
    }
}
