import Darwin
import Foundation
import MacKitCore

private enum HostServerError: LocalizedError {
    case invalidRequest(String)
    case socket(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): message
        case .socket(let message): message
        }
    }
}

private final class HostServer: @unchecked Sendable {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let socketPath = HostPaths.socketURL.path
    private let helperURL: URL
    private let commandSlots = DispatchSemaphore(value: HostLimits.maximumConcurrentCommands)
    private let logQueue = DispatchQueue(label: "com.mackit.host.log")
    private var lockDescriptor: Int32 = -1

    init() throws {
        helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/mackit")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw HostServerError.invalidRequest(
                "Bundled mackit executable is missing at \(helperURL.path)"
            )
        }
    }

    func run() throws -> Never {
        try FileManager.default.createDirectory(
            at: HostPaths.applicationSupportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: HostPaths.applicationSupportDirectory.path
        )
        try acquireInstanceLock()

        signal(SIGPIPE, SIG_IGN)
        unlink(socketPath)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0 else { throw socketError("Could not create host socket") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < pathCapacity else {
            close(server)
            throw HostServerError.socket("Host socket path is too long")
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                socketPath.withCString { source in
                    _ = strncpy(destination, source, pathCapacity - 1)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(server)
            throw socketError("Could not bind host socket")
        }
        guard chmod(socketPath, 0o600) == 0 else {
            close(server)
            throw socketError("Could not protect host socket")
        }
        guard listen(server, 16) == 0 else {
            close(server)
            throw socketError("Could not listen on host socket")
        }

        while true {
            let client = accept(server, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                throw socketError("Could not accept host connection")
            }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                handle(client)
            }
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }

        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == geteuid() else {
            return
        }

        do {
            let data = try readLine(from: client, maximumBytes: 1_048_576)
            let request = try decoder.decode(HostRequest.self, from: data)
            guard commandSlots.wait(timeout: .now()) == .success else {
                let response = HostResponse(
                    exitCode: 75,
                    standardOutput: "",
                    standardError: "MacKit.app is busy. Try again shortly.\n"
                )
                var responseData = try encoder.encode(response)
                responseData.append(0x0A)
                try writeAll(responseData, to: client)
                log(event: "rejected", request: request, fields: ["reason": "concurrency_limit"])
                return
            }
            defer { commandSlots.signal() }
            switch request.mode {
            case .command:
                let response = execute(request, client: client)
                var responseData = try encoder.encode(response)
                responseData.append(0x0A)
                try writeAll(responseData, to: client)
            case .stream:
                try stream(request, over: client)
            }
        } catch {
            let response = HostResponse(
                exitCode: 70,
                standardOutput: "",
                standardError: "MacKit host error: \(error.localizedDescription)\n"
            )
            if var data = try? encoder.encode(response) {
                data.append(0x0A)
                try? writeAll(data, to: client)
            }
        }
    }

    private func configuredProcess(for request: HostRequest) -> Process {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = request.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: request.currentDirectory)
        var environment = ProcessInfo.processInfo.environment
        environment.merge(request.environment) { _, requested in requested }
        environment["MACKIT_DIRECT"] = "1"
        environment["MACKIT_STDOUT_IS_TTY"] = request.standardOutputIsTTY ? "1" : "0"
        process.environment = environment
        return process
    }

    private func execute(_ request: HostRequest, client: Int32) -> HostResponse {
        let id = UUID().uuidString
        let stdoutURL = HostPaths.applicationSupportDirectory.appendingPathComponent("\(id).stdout")
        let stderrURL = HostPaths.applicationSupportDirectory.appendingPathComponent("\(id).stderr")
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        for url in [stdoutURL, stderrURL] {
            guard FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                return HostResponse(exitCode: 70, standardOutput: "", standardError: "Could not capture host output.\n")
            }
        }

        do {
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            let process = configuredProcess(for: request)
            process.standardOutput = stdout
            process.standardError = stderr
            let started = Date()
            try process.run()
            log(event: "started", request: request, fields: ["pid": process.processIdentifier])

            var forcedError: String?
            while process.isRunning {
                if Date().timeIntervalSince(started) >= TimeInterval(request.timeoutSeconds) {
                    forcedError = "Command exceeded the \(request.timeoutSeconds)-second host deadline."
                    stop(process)
                    break
                }
                if peerDisconnected(client) {
                    forcedError = "Client disconnected before the command completed."
                    stop(process)
                    break
                }
                if capturedBytes(stdoutURL) + capturedBytes(stderrURL) > HostLimits.maximumOutputBytes {
                    forcedError = "Command output exceeded the \(HostLimits.maximumOutputBytes / 1_048_576) MB host limit."
                    stop(process)
                    break
                }
                usleep(100_000)
            }
            process.waitUntilExit()
            if forcedError == nil,
               capturedBytes(stdoutURL) + capturedBytes(stderrURL) > HostLimits.maximumOutputBytes {
                forcedError = "Command output exceeded the \(HostLimits.maximumOutputBytes / 1_048_576) MB host limit."
            }
            try stdout.close()
            try stderr.close()

            let elapsedMS = Int(Date().timeIntervalSince(started) * 1_000)
            if let forcedError {
                log(event: "terminated", request: request, fields: [
                    "duration_ms": elapsedMS, "reason": forcedError,
                ])
                return HostResponse(
                    exitCode: forcedError.hasPrefix("Command exceeded") ? 124 : 74,
                    standardOutput: boundedString(from: stdoutURL),
                    standardError: forcedError + "\n"
                )
            }

            log(event: "completed", request: request, fields: [
                "duration_ms": elapsedMS, "exit_code": process.terminationStatus,
            ])

            return HostResponse(
                exitCode: process.terminationStatus,
                standardOutput: boundedString(from: stdoutURL),
                standardError: boundedString(from: stderrURL)
            )
        } catch {
            return HostResponse(
                exitCode: 70,
                standardOutput: "",
                standardError: "Could not execute mackit: \(error.localizedDescription)\n"
            )
        }
    }

    private func stream(_ request: HostRequest, over client: Int32) throws {
        try writeAll(Data("READY\n".utf8), to: client)
        let process = configuredProcess(for: request)
        let socketHandle = FileHandle(fileDescriptor: dup(client), closeOnDealloc: true)
        process.standardInput = socketHandle
        process.standardOutput = socketHandle
        process.standardError = FileHandle.nullDevice
        try process.run()
        log(event: "stream_started", request: request, fields: ["pid": process.processIdentifier])
        // The CLI half-closes its write side after stdin reaches EOF. The child
        // receives that EOF through the duplicated socket and exits naturally.
        // Treating recv() == 0 as a disconnect here would drop its final response.
        process.waitUntilExit()
        log(event: "stream_completed", request: request, fields: [
            "exit_code": process.terminationStatus,
        ])
    }

    private func acquireInstanceLock() throws {
        lockDescriptor = open(HostPaths.lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard lockDescriptor >= 0 else {
            throw socketError("Could not open host lock")
        }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw HostServerError.socket("Another MacKit host is already running")
        }
    }

    private func peerDisconnected(_ client: Int32) -> Bool {
        var byte: UInt8 = 0
        let result = Darwin.recv(client, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return result == 0
    }

    private func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 where process.isRunning { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private func capturedBytes(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func boundedString(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: HostLimits.maximumOutputBytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func log(event: String, request: HostRequest, fields: [String: Any] = [:]) {
        var value: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "event": event,
            "command": request.arguments.first ?? "",
        ]
        value.merge(fields) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return
        }
        logQueue.async {
            let fileManager = FileManager.default
            if self.capturedBytes(HostPaths.logURL) > 5 * 1_048_576 {
                try? fileManager.removeItem(at: HostPaths.logURL)
            }
            if !fileManager.fileExists(atPath: HostPaths.logURL.path) {
                fileManager.createFile(
                    atPath: HostPaths.logURL.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            guard let handle = try? FileHandle(forWritingTo: HostPaths.logURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
        }
    }

    private func readLine(from descriptor: Int32, maximumBytes: Int) throws -> Data {
        var result = Data()
        var byte: UInt8 = 0
        while result.count < maximumBytes {
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw socketError("Could not read host request")
            }
            if byte == 0x0A { return result }
            result.append(byte)
        }
        guard !result.isEmpty, result.count < maximumBytes else {
            throw HostServerError.invalidRequest("Invalid or oversized host request")
        }
        return result
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw socketError("Could not write host response")
                }
                offset += count
            }
        }
    }

    private func socketError(_ message: String) -> HostServerError {
        HostServerError.socket("\(message): \(String(cString: strerror(errno)))")
    }
}

do {
    try HostServer().run()
} catch {
    FileHandle.standardError.write(Data("MacKitHost: \(error.localizedDescription)\n".utf8))
    exit(1)
}
