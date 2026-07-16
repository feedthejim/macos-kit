import Darwin
import Foundation
import MacKitCore

enum HostClientError: LocalizedError {
    case hostNotInstalled
    case connection(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .hostNotInstalled:
            "MacKit.app is not installed. Run scripts/install-mackit.sh from the source checkout."
        case .connection(let message):
            message
        case .invalidResponse:
            "MacKit.app returned an invalid response."
        }
    }
}

enum HostClient {
    static func forward(arguments: [String]) throws -> Int32 {
        let mode: HostRequestMode = arguments.first == "mcp" ? .stream : .command
        let socket = try connectedSocket()
        let request = HostRequest(
            mode: mode,
            arguments: arguments,
            currentDirectory: FileManager.default.currentDirectoryPath,
            environment: forwardedEnvironment(),
            standardOutputIsTTY: isatty(STDOUT_FILENO) != 0,
            timeoutSeconds: HostLimits.commandTimeout()
        )
        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0A)
        try writeAll(requestData, to: socket)

        switch mode {
        case .command:
            defer { close(socket) }
            setReadTimeout(on: socket, seconds: request.timeoutSeconds + 5)
            let responseData = try readLine(from: socket, maximumBytes: 128 * 1_048_576)
            let response = try JSONDecoder().decode(HostResponse.self, from: responseData)
            FileHandle.standardOutput.write(Data(response.standardOutput.utf8))
            FileHandle.standardError.write(Data(response.standardError.utf8))
            return response.exitCode
        case .stream:
            return try proxyStandardIO(over: socket)
        }
    }

    static func diagnostics() -> [(name: String, passed: Bool, detail: String)] {
        let fileManager = FileManager.default
        let installedApp = HostPaths.standardAppURLs.first {
            fileManager.fileExists(atPath: $0.path)
        }
        var checks: [(String, Bool, String)] = [
            (
                "App installation", installedApp != nil,
                installedApp?.path ?? "MacKit.app was not found"
            ),
        ]

        var socket = connectToHost()
        if socket == nil, installedApp != nil {
            try? launchHost()
            for _ in 0..<40 where socket == nil {
                usleep(50_000)
                socket = connectToHost()
            }
        }
        if let socket { close(socket) }
        checks.append((
            "Host service", socket != nil,
            socket != nil ? "reachable at (HostPaths.socketURL.path)" : "not reachable"
        ))

        let permissions = (try? fileManager.attributesOfItem(
            atPath: HostPaths.socketURL.path
        )[.posixPermissions] as? NSNumber)?.intValue
        checks.append((
            "Socket permissions", permissions == 0o600,
            permissions.map { String(format: "%03o", $0) } ?? "socket missing"
        ))
        checks.append((
            "Host log", true, HostPaths.logURL.path
        ))
        return checks
    }

    private static func connectedSocket() throws -> Int32 {
        if let socket = connectToHost() { return socket }
        try launchHost()

        for _ in 0..<100 {
            if let socket = connectToHost() { return socket }
            usleep(50_000)
        }
        throw HostClientError.connection("MacKit.app did not start its local service.")
    }

    private static func connectToHost() -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }

        let socketPath = HostPaths.socketURL.path
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < pathCapacity else {
            close(descriptor)
            return nil
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                socketPath.withCString { source in
                    _ = strncpy(destination, source, pathCapacity - 1)
                }
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func launchHost() throws {
        guard let appURL = HostPaths.standardAppURLs.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw HostClientError.hostNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-gja", appURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HostClientError.connection("Could not launch MacKit.app.")
        }
    }

    private static func proxyStandardIO(over socket: Int32) throws -> Int32 {
        let ready = try readLine(from: socket, maximumBytes: 1024)
        guard ready == Data("READY".utf8) else {
            close(socket)
            throw HostClientError.invalidResponse
        }

        let inputFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
                if count <= 0 { break }
                do {
                    try writeAll(Data(buffer[0..<count]), to: socket)
                } catch {
                    break
                }
            }
            _ = Darwin.shutdown(socket, SHUT_WR)
            inputFinished.signal()
        }

        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(socket, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                close(socket)
                throw HostClientError.connection("Lost connection to MacKit.app.")
            }
            FileHandle.standardOutput.write(Data(buffer[0..<count]))
        }
        close(socket)
        _ = inputFinished.wait(timeout: .now() + 1)
        return 0
    }

    private static func forwardedEnvironment() -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let keys = ["LANG", "LC_ALL", "LC_CTYPE", "NO_COLOR", "TERM", "TZ"]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            environment[key].map { (key, $0) }
        })
    }

    private static func setReadTimeout(on socket: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    private static func readLine(from descriptor: Int32, maximumBytes: Int) throws -> Data {
        var result = Data()
        var byte: UInt8 = 0
        while result.count < maximumBytes {
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw HostClientError.connection("Could not read from MacKit.app.")
            }
            if byte == 0x0A { return result }
            result.append(byte)
        }
        guard !result.isEmpty, result.count < maximumBytes else {
            throw HostClientError.invalidResponse
        }
        return result
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw HostClientError.connection("Could not write to MacKit.app.")
                }
                offset += count
            }
        }
    }
}
