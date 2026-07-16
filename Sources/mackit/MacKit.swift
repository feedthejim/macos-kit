import ArgumentParser
import Darwin
import Foundation
import MacKitCore

struct MacKitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mackit",
        abstract: "Native macOS data from the command line",
        version: "0.1.0",
        subcommands: [
            CalendarCommand.self,
            RemindersCommand.self,
            ContactsCommand.self,
            MailCommand.self,
            FocusCommand.self,
            NotifyCommand.self,
            MCPCommand.self,
            DoctorCommand.self,
            CompletionsCommand.self,
        ]
    )
}

@main
enum MacKitEntryPoint {
    static func main() async {
        if HostRouting.shouldForward(arguments: CommandLine.arguments) {
            do {
                let exitCode = try HostClient.forward(
                    arguments: Array(CommandLine.arguments.dropFirst())
                )
                exit(exitCode)
            } catch {
                FileHandle.standardError.write(
                    Data("Error: \(error.localizedDescription)\n".utf8)
                )
                exit(69)
            }
        }

        await MacKitCommand.main()
    }
}
