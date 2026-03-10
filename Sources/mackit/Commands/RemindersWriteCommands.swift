import ArgumentParser
import MacKitCore
import Foundation

extension RemindersCommand {
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add", abstract: "Add a reminder")
        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Reminder title") var title: String
        @Option(name: [.short, .customLong("list")], help: "List name") var listName: String?
        @Option(name: .long, help: "Due date (today, tomorrow, YYYY-MM-DD)") var due: String?
        @Option(name: .long, help: "Priority: high, medium, low") var priority: String?
        @Option(name: .long, help: "Notes") var notes: String?

        func run() async throws {
            let service = LiveRemindersWriteService()
            let dueDate = try due.map { try DateParsing.parse($0) }
            let prio: ReminderPriority = switch priority?.lowercased() {
            case "high": .high
            case "medium": .medium
            case "low": .low
            default: .none
            }
            let reminder = try await service.addReminder(title: title, listName: listName,
                dueDate: dueDate, priority: prio, notes: notes)
            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(reminder))
            case .text, .table: print("Added: \(reminder.title) \u{2192} \(reminder.listName)")
            }
        }
    }

    struct Done: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "done", abstract: "Complete a reminder by title match")
        @Argument(help: "Title to match (fuzzy)") var query: String
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveRemindersWriteService()
            let completed = try await service.completeReminder(titleMatch: query)
            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(completed))
            case .text, .table: print("Done: \(completed.title)")
            }
        }
    }

    struct DeleteReminder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete", abstract: "Delete a reminder")
        @Argument(help: "Reminder ID") var reminderId: String
        @Flag(name: .long, help: "Skip confirmation") var yes: Bool = false

        func run() async throws {
            if !yes {
                FileHandle.standardError.write(Data("Use --yes to confirm deletion.\n".utf8))
                throw ExitCode.failure
            }
            let service = LiveRemindersWriteService()
            try await service.deleteReminder(id: reminderId)
            FileHandle.standardError.write(Data("Deleted.\n".utf8))
        }
    }

    struct MoveReminder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move", abstract: "Move a reminder to another list")
        @Argument(help: "Title to match") var query: String
        @Option(name: .long, help: "Target list name") var to: String
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveRemindersWriteService()
            let moved = try await service.moveReminder(titleMatch: query, toList: to)
            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(moved))
            case .text, .table: print("Moved: \(moved.title) \u{2192} \(moved.listName)")
            }
        }
    }
}
