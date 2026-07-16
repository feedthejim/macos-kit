import ArgumentParser
import MacKitCore
import Foundation

private func reportPage(_ page: MailPage) {
    for warning in page.warnings {
        FileHandle.standardError.write(Data("Warning: \(warning)\n".utf8))
    }
    if let nextOffset = page.nextOffset {
        FileHandle.standardError.write(
            Data("More messages available. Use --offset \(nextOffset).\n".utf8)
        )
    }
}

private func groupedByThread(_ messages: [MailMessage]) -> [MailMessage] {
    Dictionary(grouping: messages, by: \.threadId)
        .compactMap { $0.value.max(by: { $0.dateReceived < $1.dateReceived }) }
        .sorted { $0.dateReceived > $1.dateReceived }
}

struct MailCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Mail.app messages",
        subcommands: [
            ListMessages.self,
            ReadMessage.self,
            SearchMessages.self,
            ListMailboxes.self,
            ListAccounts.self,
            Send.self,
            MarkRead.self,
            MarkUnread.self,
            MoveMessage.self,
            DeleteMessage.self,
        ],
        defaultSubcommand: ListMessages.self
    )
}

extension MailCommand {
    struct ListMessages: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List recent messages",
            discussion: """
                Lists messages from a mailbox (default: INBOX). Shows subject, sender, \
                date, and read status.

                EXAMPLES:
                  mackit mail list                          # Recent INBOX messages
                  mackit mail list --unread                 # Unread only
                  mackit mail list -m "Sent Mail" -a Gmail  # Sent from Gmail
                  mackit mail list -n 5                     # Last 5 messages
                  mackit mail list --sender stripe --from monday --to today
                  mackit mail list --offset 25 -n 25        # Next page
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: [.short, .customLong("mailbox")], help: "Mailbox name (default: INBOX)")
        var mailbox: String?

        @Option(name: [.short, .customLong("account")], help: "Account name")
        var account: String?

        @Flag(name: .long, help: "Show only unread messages")
        var unread: Bool = false

        @Option(name: [.customShort("n"), .customLong("limit")], help: "Max messages to return (default: 25)")
        var limit: Int = 25

        @Option(name: .long, help: "Skip messages for pagination (default: 0)")
        var offset: Int = 0

        @Option(name: .long, help: "Filter sender by name or address")
        var sender: String?

        @Option(name: .long, help: "Only messages received after this date")
        var from: String?

        @Option(name: .long, help: "Only messages received through this inclusive date")
        var to: String?

        @Flag(name: .customLong("group-threads"), help: "Show only the newest message per normalized subject")
        var groupThreads = false

        @Option(name: .customLong("json"), help: """
            Output JSON with specific fields (comma-separated). \
            Fields: \(MailMessage.availableFields.joined(separator: ", "))
            """)
        var jsonFields: String?

        func run() async throws {
            let service = LiveMailService()
            let fields = jsonFields?.split(separator: ",").map(String.init)
            let includeDetails = fields.map { !MailMessage.detailFields.isDisjoint(with: $0) }
                ?? (globals.effectiveFormat == .json)
            guard limit > 0, limit <= 200, offset >= 0 else {
                throw ValidationError("--limit must be 1...200 and --offset cannot be negative")
            }
            let page = try await service.queryMessages(MailQuery(
                mailbox: mailbox, account: account, sender: sender,
                receivedAfter: try from.map { try DateParsing.parse($0) },
                receivedBefore: try to.map { try DateParsing.parseRangeEnd($0) },
                unreadOnly: unread, limit: limit, offset: offset,
                includeDetails: includeDetails, requestedFields: Set(fields ?? [])
            ))
            let messages = groupThreads
                ? groupedByThread(page.messages)
                : page.messages
            reportPage(page)

            if globals.effectiveFormat == .json, jsonFields == nil {
                print(try OutputRenderer.renderJSON(MailPage(
                    messages: messages, offset: page.offset, nextOffset: page.nextOffset,
                    isPartial: page.isPartial, warnings: page.warnings
                )))
                return
            }
            if let fields {
                print(try FieldSelection.select(fields: fields, from: messages))
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(messages))
                case .text:
                    if messages.isEmpty {
                        print("No messages")
                    } else {
                        print(messages.map(\.textSummary).joined(separator: "\n"))
                    }
                case .table:
                    print(OutputRenderer.renderTable(messages, emptyMessage: "No messages"))
                }
            }
        }
    }

    struct ReadMessage: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "read",
            abstract: "Read a message",
            discussion: """
                Shows full message content. Get message IDs from 'mackit mail list --json id,subject'.

                EXAMPLES:
                  mackit mail read 12345 -m INBOX -a iCloud
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Message ID (get from 'mackit mail list --json id,subject')")
        var messageId: String

        @Option(name: [.short, .customLong("mailbox")], help: "Mailbox name")
        var mailbox: String = "INBOX"

        @Option(name: [.short, .customLong("account")], help: "Account name")
        var account: String

        func run() async throws {
            let service = LiveMailService()
            let message = try await service.getMessage(id: messageId, mailbox: mailbox, account: account)

            switch globals.effectiveFormat {
            case .json:
                print(try OutputRenderer.renderJSON(message))
            case .text, .table:
                print(message.textDetail)
            }
        }
    }

    struct SearchMessages: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search",
            abstract: "Search messages",
            discussion: """
                Searches message subjects and senders across mailboxes.

                EXAMPLES:
                  mackit mail search "invoice"               # Search all INBOX
                  mackit mail search "meeting" -m "All Mail"  # Search specific mailbox
                  mackit mail search "bob" -a Gmail -n 10
                  mackit mail search "invoice" --sender stripe --from "last monday"
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Search query (matches subject and sender)")
        var query: String

        @Option(name: [.short, .customLong("mailbox")], help: "Mailbox to search (default: INBOX)")
        var mailbox: String?

        @Option(name: [.short, .customLong("account")], help: "Account name")
        var account: String?

        @Option(name: [.customShort("n"), .customLong("limit")], help: "Max results (default: 25)")
        var limit: Int = 25

        @Option(name: .long, help: "Skip results for pagination (default: 0)")
        var offset: Int = 0

        @Option(name: .long, help: "Filter sender by name or address")
        var sender: String?

        @Option(name: .long, help: "Only messages received after this date")
        var from: String?

        @Option(name: .long, help: "Only messages received through this inclusive date")
        var to: String?

        @Flag(name: .customLong("group-threads"), help: "Show only the newest message per normalized subject")
        var groupThreads = false

        @Option(name: .customLong("json"), help: """
            Output JSON with specific fields (comma-separated). \
            Fields: \(MailMessage.availableFields.joined(separator: ", "))
            """)
        var jsonFields: String?

        func run() async throws {
            let service = LiveMailService()
            let fields = jsonFields?.split(separator: ",").map(String.init)
            let includeDetails = fields.map { !MailMessage.detailFields.isDisjoint(with: $0) }
                ?? (globals.effectiveFormat == .json)
            guard limit > 0, limit <= 200, offset >= 0 else {
                throw ValidationError("--limit must be 1...200 and --offset cannot be negative")
            }
            let page = try await service.queryMessages(MailQuery(
                search: query, mailbox: mailbox, account: account, sender: sender,
                receivedAfter: try from.map { try DateParsing.parse($0) },
                receivedBefore: try to.map { try DateParsing.parseRangeEnd($0) },
                limit: limit, offset: offset, includeDetails: includeDetails,
                requestedFields: Set(fields ?? [])
            ))
            let messages = groupThreads
                ? groupedByThread(page.messages)
                : page.messages
            reportPage(page)

            if globals.effectiveFormat == .json, jsonFields == nil {
                print(try OutputRenderer.renderJSON(MailPage(
                    messages: messages, offset: page.offset, nextOffset: page.nextOffset,
                    isPartial: page.isPartial, warnings: page.warnings
                )))
                return
            }
            if let fields {
                print(try FieldSelection.select(fields: fields, from: messages))
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(messages))
                case .text:
                    if messages.isEmpty {
                        print("No messages matching '\(query)'")
                    } else {
                        print(messages.map(\.textSummary).joined(separator: "\n"))
                    }
                case .table:
                    print(OutputRenderer.renderTable(messages, emptyMessage: "No messages found"))
                }
            }
        }
    }

    struct ListMailboxes: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mailboxes",
            abstract: "List mailboxes",
            discussion: """
                Shows all mailboxes with unread and total message counts.

                EXAMPLES:
                  mackit mail mailboxes                  # All accounts
                  mackit mail mailboxes -a iCloud        # Specific account
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: [.short, .customLong("account")], help: "Filter by account name")
        var account: String?

        @Option(name: .customLong("json"), help: """
            Output JSON with specific fields (comma-separated). \
            Fields: \(Mailbox.availableFields.joined(separator: ", "))
            """)
        var jsonFields: String?

        func run() async throws {
            let service = LiveMailService()
            let mailboxes = try await service.mailboxes(account: account)

            if let jsonFields {
                let fields = jsonFields.split(separator: ",").map(String.init)
                print(try FieldSelection.select(fields: fields, from: mailboxes))
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(mailboxes))
                case .text:
                    if mailboxes.isEmpty {
                        print("No mailboxes found")
                    } else {
                        print(mailboxes.map(\.textDetail).joined(separator: "\n\n"))
                    }
                case .table:
                    print(OutputRenderer.renderTable(mailboxes, emptyMessage: "No mailboxes found"))
                }
            }
        }
    }

    struct ListAccounts: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "accounts",
            abstract: "List mail accounts"
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .customLong("json"), help: """
            Output JSON with specific fields (comma-separated). \
            Fields: \(MailAccount.availableFields.joined(separator: ", "))
            """)
        var jsonFields: String?

        func run() async throws {
            let service = LiveMailService()
            let accounts = try await service.accounts()

            if let jsonFields {
                let fields = jsonFields.split(separator: ",").map(String.init)
                print(try FieldSelection.select(fields: fields, from: accounts))
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(accounts))
                case .text:
                    if accounts.isEmpty {
                        print("No mail accounts configured")
                    } else {
                        print(accounts.map(\.textDetail).joined(separator: "\n\n"))
                    }
                case .table:
                    print(OutputRenderer.renderTable(accounts, emptyMessage: "No accounts"))
                }
            }
        }
    }

    struct Send: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "send",
            abstract: "Send an email",
            discussion: """
                Sends an email via Mail.app. Requires --to, --subject, and --body. \
                Use --dry-run to preview without sending.

                EXAMPLES:
                  mackit mail send --to bob@test.com --subject "Hello" --body "Hi Bob"
                  mackit mail send --to a@test.com --cc b@test.com --subject "FYI" --body "See attached"
                  mackit mail send --to bob@test.com --subject "Test" --body "Hi" --dry-run
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Recipient email (repeatable)")
        var to: [String]

        @Option(name: .long, help: "CC recipient (repeatable)")
        var cc: [String] = []

        @Option(name: .long, help: "BCC recipient (repeatable)")
        var bcc: [String] = []

        @Option(name: .long, help: "Email subject")
        var subject: String

        @Option(name: .long, help: "Email body (plain text)")
        var body: String

        @Option(name: .long, help: "Send from specific account email")
        var from: String?

        @Flag(name: .customLong("dry-run"), help: "Preview the email without sending it")
        var dryRun: Bool = false

        func run() async throws {
            if dryRun {
                FileHandle.standardError.write(Data("Dry run - would send:\n".utf8))
                print("  To:      \(to.joined(separator: ", "))")
                if !cc.isEmpty { print("  CC:      \(cc.joined(separator: ", "))") }
                if !bcc.isEmpty { print("  BCC:     \(bcc.joined(separator: ", "))") }
                if let from { print("  From:    \(from)") }
                print("  Subject: \(subject)")
                print("  Body:    \(body)")
                return
            }

            let service = LiveMailService()
            try await service.sendMessage(to: to, cc: cc, bcc: bcc, subject: subject, body: body, from: from)

            switch globals.effectiveFormat {
            case .json:
                print("{\"sent\": true, \"to\": \"\(to.joined(separator: ", "))\"}")
            case .text, .table:
                print("Sent to: \(to.joined(separator: ", "))")
            }
        }
    }

    struct MarkRead: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mark-read",
            abstract: "Mark a message as read"
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Message ID") var messageId: String
        @Option(name: [.short, .customLong("mailbox")], help: "Mailbox name") var mailbox: String = "INBOX"
        @Option(name: [.short, .customLong("account")], help: "Account name") var account: String

        func run() async throws {
            let service = LiveMailService()
            try await service.markRead(id: messageId, mailbox: mailbox, account: account)
            switch globals.effectiveFormat {
            case .json: print("{\"markedRead\": true, \"id\": \"\(messageId)\"}")
            case .text, .table: print("Marked as read: \(messageId)")
            }
        }
    }

    struct MarkUnread: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mark-unread",
            abstract: "Mark a message as unread"
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Message ID") var messageId: String
        @Option(name: [.short, .customLong("mailbox")], help: "Mailbox name") var mailbox: String = "INBOX"
        @Option(name: [.short, .customLong("account")], help: "Account name") var account: String

        func run() async throws {
            let service = LiveMailService()
            try await service.markUnread(id: messageId, mailbox: mailbox, account: account)
            switch globals.effectiveFormat {
            case .json: print("{\"markedUnread\": true, \"id\": \"\(messageId)\"}")
            case .text, .table: print("Marked as unread: \(messageId)")
            }
        }
    }

    struct MoveMessage: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move a message to another mailbox",
            discussion: """
                EXAMPLES:
                  mackit mail move 12345 --to Archive -m INBOX -a iCloud
                """
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Message ID") var messageId: String
        @Option(name: .long, help: "Destination mailbox") var to: String
        @Option(name: [.short, .customLong("mailbox")], help: "Source mailbox") var mailbox: String = "INBOX"
        @Option(name: [.short, .customLong("account")], help: "Account name") var account: String

        func run() async throws {
            let service = LiveMailService()
            try await service.moveMessage(id: messageId, fromMailbox: mailbox, toMailbox: to, account: account)
            switch globals.effectiveFormat {
            case .json: print("{\"moved\": true, \"id\": \"\(messageId)\", \"to\": \"\(to)\"}")
            case .text, .table: print("Moved message \(messageId) to \(to)")
            }
        }
    }

    struct DeleteMessage: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a message",
            discussion: """
                Without --yes, shows the message details and exits without deleting. \
                Use --yes to confirm deletion.

                EXAMPLES:
                  mackit mail delete 12345 -m INBOX -a iCloud          # Preview
                  mackit mail delete 12345 -m INBOX -a iCloud --yes    # Actually delete
                """
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Message ID") var messageId: String
        @Option(name: [.short, .customLong("mailbox")], help: "Mailbox name") var mailbox: String = "INBOX"
        @Option(name: [.short, .customLong("account")], help: "Account name") var account: String
        @Flag(name: .long, help: "Confirm deletion") var yes: Bool = false

        func run() async throws {
            let service = LiveMailService()
            guard yes else {
                let msg = try await service.getMessage(id: messageId, mailbox: mailbox, account: account)
                print("Would delete: \(msg.subject)")
                print("  From: \(msg.sender)")
                print("  Date: \(msg.dateReceived)")
                print("\nRe-run with --yes to confirm deletion.")
                return
            }
            try await service.deleteMessage(id: messageId, mailbox: mailbox, account: account)
            switch globals.effectiveFormat {
            case .json: print("{\"deleted\": true, \"id\": \"\(messageId)\"}")
            case .text, .table: print("Deleted message \(messageId)")
            }
        }
    }
}
