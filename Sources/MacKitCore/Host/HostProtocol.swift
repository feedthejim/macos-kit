import Foundation

public enum HostRequestMode: String, Codable, Sendable {
    case command
    case stream
}

public struct HostRequest: Codable, Sendable {
    public let mode: HostRequestMode
    public let arguments: [String]
    public let currentDirectory: String
    public let environment: [String: String]
    public let standardOutputIsTTY: Bool
    public let timeoutSeconds: Int

    public init(
        mode: HostRequestMode,
        arguments: [String],
        currentDirectory: String,
        environment: [String: String],
        standardOutputIsTTY: Bool,
        timeoutSeconds: Int = HostLimits.defaultCommandTimeoutSeconds
    ) {
        self.mode = mode
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.standardOutputIsTTY = standardOutputIsTTY
        self.timeoutSeconds = HostLimits.clampedTimeout(timeoutSeconds)
    }
}

public struct HostResponse: Codable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum HostPaths {
    public static var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacKit", isDirectory: true)
    }

    public static var socketURL: URL {
        applicationSupportDirectory.appendingPathComponent("host.sock")
    }

    public static var lockURL: URL {
        applicationSupportDirectory.appendingPathComponent("host.lock")
    }

    public static var logURL: URL {
        applicationSupportDirectory.appendingPathComponent("host.jsonl")
    }

    public static var standardAppURLs: [URL] {
        var urls: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["MACKIT_HOST_APP"] {
            urls.append(URL(fileURLWithPath: configured))
        }
        urls.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/MacKit.app")
        )
        urls.append(URL(fileURLWithPath: "/Applications/MacKit.app"))
        return urls
    }
}

public enum HostLimits {
    public static let defaultCommandTimeoutSeconds = 45
    public static let minimumCommandTimeoutSeconds = 5
    public static let maximumCommandTimeoutSeconds = 300
    public static let maximumOutputBytes = 32 * 1_048_576
    public static let maximumConcurrentCommands = 4

    public static func clampedTimeout(_ seconds: Int) -> Int {
        min(max(seconds, minimumCommandTimeoutSeconds), maximumCommandTimeoutSeconds)
    }

    public static func commandTimeout(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        guard let value = environment["MACKIT_TIMEOUT"], let seconds = Int(value) else {
            return defaultCommandTimeoutSeconds
        }
        return clampedTimeout(seconds)
    }
}

public enum HostRouting {
    private static let hostedCommands: Set<String> = [
        "cal", "contacts", "mail", "mcp", "notify", "rem", "reminders",
    ]

    public static func shouldForward(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard environment["MACKIT_DIRECT"] != "1", arguments.count > 1 else {
            return false
        }
        return hostedCommands.contains(arguments[1])
    }
}
