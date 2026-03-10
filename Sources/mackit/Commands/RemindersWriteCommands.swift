import ArgumentParser
import MacKitCore
import Foundation

extension RemindersCommand {
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a reminder",
            discussion: """
                Creates a reminder in the specified list. Uses the system default list \
                if --list is omitted.

                EXAMPLES:
                  mackit rem add "Buy milk" --list Shopping
                  mackit rem add "Review PR" --list Work --due tomorrow --priority high
                  mackit rem add "Call dentist" --due 2026-03-15 --notes "Ask about cleaning"
                """
        )
        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Reminder title") var title: String
        @Option(name: [.short, .customLong("list")], help: "List name (default: system default list)") var listName: String?
        @Option(name: .long, help: "Due date: YYYY-MM-DD, 'today', 'tomorrow', day name") var due: String?
        @Option(name: .long, help: "Priority: high, medium, low (default: none)") var priority: String?
        @Option(name: .long, help: "Reminder notes") var notes: String?

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
            commandName: "done",
            abstract: "Complete a reminder by title match",
            discussion: """
                Matches the first incomplete reminder whose title contains the query \
                (case-insensitive substring match). Completes that reminder.

                EXAMPLES:
                  mackit rem done "milk"     # Completes "Buy milk"
                  mackit rem done "PR"       # Completes "Review PR #456"
                """
        )
        @Argument(help: "Title substring to match (case-insensitive, matches first incomplete)") var query: String
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
            commandName: "delete",
            abstract: "Delete a reminder",
            discussion: """
                Requires --yes to confirm. Get reminder IDs from 'mackit rem --json id,title'.

                EXAMPLES:
                  mackit rem delete REMINDER_ID --yes
                """
        )
        @Argument(help: "Reminder ID (get from 'mackit rem --json id,title')") var reminderId: String
        @Flag(name: .long, help: "Confirm deletion (required)") var yes: Bool = false

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
            commandName: "move",
            abstract: "Move a reminder to another list",
            discussion: """
                Matches by title substring (case-insensitive, first match). \
                Use 'mackit rem lists' to see available list names.

                EXAMPLES:
                  mackit rem move "Buy eggs" --to Groceries
                  mackit rem move "PR" --to "Done"
                """
        )
        @Argument(help: "Title substring to match (case-insensitive, first match)") var query: String
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
