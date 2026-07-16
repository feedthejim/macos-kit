import Darwin
import Foundation

enum HostNotificationClient {
    static func send(_ notification: HostNotificationRequest) throws {
        let socket = try connectedSocket()
        defer { close(socket) }

        let request = HostRequest(
            mode: .notification,
            arguments: [],
            currentDirectory: FileManager.default.currentDirectoryPath,
            environment: [:],
            standardOutputIsTTY: false,
            notification: notification
        )
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        try writeAll(data, to: socket)
        let response = try JSONDecoder().decode(
            HostResponse.self,
            from: readLine(from: socket, maximumBytes: 1_048_576)
        )
        guard response.exitCode == 0 else {
            let message = response.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MacKitError.systemError(message.isEmpty ? "MacKit.app could not send the notification." : message)
        }
    }

    private static func connectedSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw MacKitError.systemError("Could not create a connection to MacKit.app.")
        }

        let socketPath = HostPaths.socketURL.path
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < capacity else {
            close(descriptor)
            throw MacKitError.systemError("The MacKit.app socket path is too long.")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                socketPath.withCString { source in
                    _ = strncpy(destination, source, capacity - 1)
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
            throw MacKitError.systemError(
                "MacKit.app is not reachable. Run 'mackit doctor' and try again."
            )
        }
        var timeout = timeval(tv_sec: HostLimits.defaultCommandTimeoutSeconds, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        return descriptor
    }

    private static func readLine(from descriptor: Int32, maximumBytes: Int) throws -> Data {
        var result = Data()
        var byte: UInt8 = 0
        while result.count < maximumBytes {
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw MacKitError.systemError("Lost the connection to MacKit.app.")
            }
            if byte == 0x0A { return result }
            result.append(byte)
        }
        guard !result.isEmpty, result.count < maximumBytes else {
            throw MacKitError.systemError("MacKit.app returned an invalid notification response.")
        }
        return result
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw MacKitError.systemError("Could not send the notification to MacKit.app.")
                }
                offset += count
            }
        }
    }
}
