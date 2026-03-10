import ArgumentParser
import MacKitCore
import Foundation

struct ContactsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contacts",
        abstract: "Contacts",
        subcommands: [
            Search.self,
            Birthdays.self,
        ]
    )
}

extension ContactsCommand {
    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search",
            abstract: "Search contacts by name, email, or phone"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Search query")
        var query: String

        @Flag(name: .long, help: "Output only email addresses (one per line)")
        var email: Bool = false

        @Flag(name: .long, help: "Output only phone numbers (one per line)")
        var phone: Bool = false

        @Option(name: .long, help: "Filter by organization")
        var org: String?

        @Option(name: [.short, .customLong("limit")], help: "Max results")
        var limit: Int?

        @Option(name: .customLong("json"), help: "Output JSON with specific fields")
        var jsonFields: String?

        func run() async throws {
            let service = LiveContactsService()
            try await service.requestAccess()

            var contacts = try await service.search(query: query, limit: limit)

            if let org {
                contacts = contacts.filter {
                    $0.organizationName?.localizedCaseInsensitiveContains(org) ?? false
                }
            }

            // Composable single-value output
            if email {
                let emails = contacts.flatMap(\.emailAddresses)
                if emails.isEmpty {
                    FileHandle.standardError.write(Data("No email addresses found\n".utf8))
                    throw ExitCode.failure
                }
                for e in emails { print(e) }
                return
            }

            if phone {
                let phones = contacts.flatMap(\.phoneNumbers)
                if phones.isEmpty {
                    FileHandle.standardError.write(Data("No phone numbers found\n".utf8))
                    throw ExitCode.failure
                }
                for p in phones { print(p) }
                return
            }

            if let jsonFields {
                let fields = jsonFields.split(separator: ",").map(String.init)
                print(try FieldSelection.select(fields: fields, from: contacts))
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(contacts))
                case .text:
                    if contacts.isEmpty {
                        print("No contacts found for '\(query)'")
                    } else {
                        print(contacts.map(\.textDetail).joined(separator: "\n\n"))
                    }
                case .table:
                    print(OutputRenderer.renderTable(contacts, emptyMessage: "No contacts found"))
                }
            }
        }
    }

    struct Birthdays: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "birthdays",
            abstract: "Upcoming birthdays"
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Days ahead to search (default: 30)")
        var days: Int = 30

        func run() async throws {
            let service = LiveContactsService()
            try await service.requestAccess()

            let contacts = try await service.upcomingBirthdays(withinDays: days)

            switch globals.effectiveFormat {
            case .json:
                print(try OutputRenderer.renderJSON(contacts))
            case .text:
                if contacts.isEmpty {
                    print("No birthdays in the next \(days) days")
                } else {
                    for contact in contacts {
                        let bdayStr = contact.birthday ?? "?"
                        print("  \(bdayStr)   \(contact.fullName)")
                    }
                }
            case .table:
                print(OutputRenderer.renderTable(contacts, emptyMessage: "No upcoming birthdays"))
            }
        }
    }
}
