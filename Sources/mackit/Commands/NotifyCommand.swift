import ArgumentParser
import MacKitCore
import Foundation

struct NotifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a local notification",
        discussion: """
            Sends a macOS notification via the system notification center. \
            Requires Notifications permission on first use.

            SOUNDS: 'default' for the standard sound, or system sound names \
            like 'Ping', 'Basso', 'Blow', 'Bottle', 'Frog', 'Funk', 'Glass', \
            'Hero', 'Morse', 'Pop', 'Purr', 'Sosumi', 'Submarine', 'Tink'.

            EXAMPLES:
              mackit notify "Build Done" "All tests passed"
              mackit notify "Deploy" "v2.1.0" --subtitle "us-east-1" --sound default
              mackit notify "Reminder" "Check email" --sound Ping
            """
    )

    @Argument(help: "Notification title")
    var title: String

    @Argument(help: "Notification body text")
    var body: String

    @Option(name: .long, help: "Subtitle text (shown below title)")
    var subtitle: String?

    @Option(name: .long, help: "Sound: 'default', or name like 'Ping', 'Glass', 'Hero'")
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
