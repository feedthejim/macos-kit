import ArgumentParser
import MacKitCore
import Foundation

struct FocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus/Do Not Disturb status",
        discussion: """
            Shows whether macOS Focus mode is active. No permissions required.

            Exit codes with --quiet: 0 = Focus is ON, 1 = Focus is OFF. \
            This inverts typical Unix convention because the common use case \
            is "if focus is on, skip notifications."

            EXAMPLES:
              mackit focus                            # Show status
              mackit focus --format json              # JSON output
              mackit focus --quiet && echo "DND on"   # Scripting
              mackit focus --quiet || mackit notify "Done" "Build finished"
            """
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "No output, exit code only (0=Focus ON, 1=Focus OFF)")
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
