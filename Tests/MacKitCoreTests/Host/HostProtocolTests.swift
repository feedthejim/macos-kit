import MacKitCore
import Foundation
import Testing

@Suite("Host routing")
struct HostProtocolTests {
    @Test("Permission-sensitive commands use the host", arguments: [
        "cal", "contacts", "mail", "mcp", "notify", "rem", "reminders",
    ])
    func hostedCommand(_ command: String) {
        #expect(HostRouting.shouldForward(arguments: ["mackit", command]))
    }

    @Test("Local commands do not use the host", arguments: [
        "focus", "completions", "--help", "--version",
        "doctor",
    ])
    func localCommand(_ command: String) {
        #expect(!HostRouting.shouldForward(arguments: ["mackit", command]))
    }

    @Test("Direct mode prevents recursive forwarding")
    func directMode() {
        #expect(!HostRouting.shouldForward(
            arguments: ["mackit", "cal"],
            environment: ["MACKIT_DIRECT": "1"]
        ))
    }

    @Test("Host timeouts are clamped")
    func timeoutClamping() {
        #expect(HostLimits.clampedTimeout(1) == HostLimits.minimumCommandTimeoutSeconds)
        #expect(HostLimits.clampedTimeout(60) == 60)
        #expect(HostLimits.clampedTimeout(1_000) == HostLimits.maximumCommandTimeoutSeconds)
        #expect(HostLimits.commandTimeout(environment: ["MACKIT_TIMEOUT": "12"]) == 12)
    }

    @Test("Host requests persist their deadline")
    func requestDeadline() throws {
        let request = HostRequest(
            mode: .command, arguments: ["mail", "list"], currentDirectory: "/tmp",
            environment: [:], standardOutputIsTTY: false, timeoutSeconds: 12
        )
        let decoded = try JSONDecoder().decode(
            HostRequest.self, from: JSONEncoder().encode(request)
        )
        #expect(decoded.timeoutSeconds == 12)
    }

    @Test("Notification requests preserve their application payload")
    func notificationRequest() throws {
        let notification = HostNotificationRequest(
            title: "Build complete",
            body: "MacKit finished successfully.",
            subtitle: "MacKit",
            soundName: "default"
        )
        let request = HostRequest(
            mode: .notification,
            arguments: [],
            currentDirectory: "/tmp",
            environment: [:],
            standardOutputIsTTY: false,
            notification: notification
        )

        let decoded = try JSONDecoder().decode(
            HostRequest.self, from: JSONEncoder().encode(request)
        )

        #expect(decoded.mode == .notification)
        #expect(decoded.notification == notification)
    }
}
