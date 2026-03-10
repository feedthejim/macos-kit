import ArgumentParser
import MacKitCore
import Foundation

struct RemindersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rem",
        abstract: "Reminders",
        subcommands: [
            ListReminders.self,
            Overdue.self,
            ListLists.self,
            Add.self,
            Done.self,
            DeleteReminder.self,
            MoveReminder.self,
        ],
        defaultSubcommand: ListReminders.self
    )
}

extension RemindersCommand {
    struct ListReminders: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List reminders (default: incomplete across all lists)"
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: [.short, .customLong("list")], help: "Filter by list name")
        var listName: String?

        @Flag(name: .long, help: "Include completed reminders")
        var completed: Bool = false

        @Option(name: .long, help: "Filter by due date (today, tomorrow, ISO date)")
        var due: String?

        @Option(name: [.customShort("n"), .customLong("limit")], help: "Max reminders")
        var limit: Int?

        @Option(name: .customLong("json"), help: "Output JSON with specific fields")
        var jsonFields: String?

        func run() async throws {
            let service = LiveRemindersService()
            try await service.requestAccess()

            let dueBefore: Date?
            if let due {
                dueBefore = try DateParsing.parse(due)
            } else {
                dueBefore = nil
            }

            var reminders = try await service.reminders(
                inList: listName,
                includeCompleted: completed,
                dueBefore: dueBefore
            )

            if let limit {
                reminders = Array(reminders.prefix(limit))
            }

            if let jsonFields {
                let fields = jsonFields.split(separator: ",").map(String.init)
                print(try FieldSelection.select(fields: fields, from: reminders))
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(reminders))
                case .text:
                    print(OutputRenderer.renderText(reminders, emptyMessage: "No reminders"))
                case .table:
                    print(OutputRenderer.renderTable(reminders, emptyMessage: "No reminders"))
                }
            }
        }
    }

    struct Overdue: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "overdue",
            abstract: "Show overdue reminders"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveRemindersService()
            try await service.requestAccess()

            let reminders = try await service.overdueReminders()

            switch globals.effectiveFormat {
            case .json:
                print(try OutputRenderer.renderJSON(reminders))
            case .text:
                if reminders.isEmpty {
                    print("No overdue reminders")
                } else {
                    for reminder in reminders {
                        print(reminder.textSummary)
                    }
                }
            case .table:
                print(OutputRenderer.renderTable(reminders, emptyMessage: "No overdue reminders"))
            }
        }
    }

    struct ListLists: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "lists",
            abstract: "Show all reminder lists"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveRemindersService()
            try await service.requestAccess()

            let lists = try await service.lists()

            switch globals.effectiveFormat {
            case .json:
                print(try OutputRenderer.renderJSON(lists))
            case .text:
                print(OutputRenderer.renderText(lists, emptyMessage: "No lists"))
                let total = lists.reduce(0) { $0 + $1.count }
                print("Total: \(total) incomplete reminder\(total == 1 ? "" : "s")")
            case .table:
                print(OutputRenderer.renderTable(lists, emptyMessage: "No lists"))
            }
        }
    }
}
