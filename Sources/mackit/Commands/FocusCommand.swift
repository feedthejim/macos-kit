import ArgumentParser
import MacKitCore
import Foundation

struct FocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus/Do Not Disturb status"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "No output, exit code only (0=on, 1=off)")
    var quiet: Bool = false

    func run() async throws {
        let status = FocusService.currentStatus()

        if quiet {
            throw status.isEnabled ? ExitCode.success : ExitCode.failure
        }

        switch globals.effectiveFormat {
        case .json:
            print(try OutputRenderer.renderJSON(status))
        case .text, .table:
            print(status.textSummary)
        }
    }
}
