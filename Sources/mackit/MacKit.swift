import ArgumentParser
import MacKitCore

@main
struct MacKit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mackit",
        abstract: "Native macOS data from the command line",
        version: "0.1.0",
        subcommands: [
            CalendarCommand.self,
            RemindersCommand.self,
            ContactsCommand.self,
            FocusCommand.self,
            NotifyCommand.self,
            MCPCommand.self,
            CompletionsCommand.self,
        ]
    )
}
