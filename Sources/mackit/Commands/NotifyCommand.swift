import ArgumentParser
import MacKitCore
import Foundation

struct NotifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a local notification"
    )

    @Argument(help: "Notification title")
    var title: String

    @Argument(help: "Notification body")
    var body: String

    @Option(name: .long, help: "Subtitle text")
    var subtitle: String?

    @Option(name: .long, help: "Sound name (e.g. default, Ping)")
    var sound: String?

    func run() async throws {
        try await NotificationService.send(
            title: title,
            body: body,
            subtitle: subtitle,
            soundName: sound
        )
    }
}
