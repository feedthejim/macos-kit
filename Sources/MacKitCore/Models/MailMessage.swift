import Foundation

public struct MailMessage: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "id", "subject", "sender", "dateSent", "dateReceived",
        "isRead", "mailbox", "account", "toRecipients", "ccRecipients",
        "content", "summary",
    ]

    public let id: String
    public let subject: String
    public let sender: String
    public let dateSent: Date?
    public let dateReceived: Date
    public let isRead: Bool
    public let mailbox: String
    public let account: String
    public let toRecipients: [String]
    public let ccRecipients: [String]
    public let content: String?
    public let summary: String?

    public init(
        id: String,
        subject: String,
        sender: String,
        dateSent: Date? = nil,
        dateReceived: Date,
        isRead: Bool = false,
        mailbox: String = "INBOX",
        account: String = "",
        toRecipients: [String] = [],
        ccRecipients: [String] = [],
        content: String? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.dateSent = dateSent
        self.dateReceived = dateReceived
        self.isRead = isRead
        self.mailbox = mailbox
        self.account = account
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.content = content
        self.summary = summary
    }
}

extension MailMessage: TextRepresentable {
    public var textSummary: String {
        let read = isRead ? " " : "*"
        let dateStr = DateFormatter.shortDate.string(from: dateReceived)
        return "\(read) \(dateStr)  \(sender.prefix(30))  \(subject)"
    }

    public var textDetail: String {
        var lines = [subject]
        lines.append("  From:     \(sender)")
        if !toRecipients.isEmpty {
            lines.append("  To:       \(toRecipients.joined(separator: ", "))")
        }
        if !ccRecipients.isEmpty {
            lines.append("  CC:       \(ccRecipients.joined(separator: ", "))")
        }
        lines.append("  Date:     \(DateFormatter.shortDate.string(from: dateReceived))")
        lines.append("  Mailbox:  \(mailbox) (\(account))")
        lines.append("  Read:     \(isRead ? "yes" : "no")")
        if let content, !content.isEmpty {
            lines.append("  ---")
            lines.append("  \(content.prefix(500))")
        }
        return lines.joined(separator: "\n")
    }
}

extension MailMessage: TableRepresentable {
    public static var tableHeaders: [String] { ["Status", "Date", "From", "Subject"] }
    public var tableRow: [String] {
        [
            isRead ? "read" : "NEW",
            DateFormatter.shortDate.string(from: dateReceived),
            String(sender.prefix(30)),
            String(subject.prefix(50)),
        ]
    }
}

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Mailbox

public struct Mailbox: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "name", "account", "unreadCount", "messageCount",
    ]

    public let name: String
    public let account: String
    public let unreadCount: Int
    public let messageCount: Int

    public init(name: String, account: String, unreadCount: Int = 0, messageCount: Int = 0) {
        self.name = name
        self.account = account
        self.unreadCount = unreadCount
        self.messageCount = messageCount
    }
}

extension Mailbox: TextRepresentable {
    public var textSummary: String {
        let unread = unreadCount > 0 ? " (\(unreadCount) unread)" : ""
        return "\(account)/\(name)\(unread)"
    }

    public var textDetail: String {
        var lines = ["\(account)/\(name)"]
        lines.append("  Messages:  \(messageCount)")
        lines.append("  Unread:    \(unreadCount)")
        return lines.joined(separator: "\n")
    }
}

extension Mailbox: TableRepresentable {
    public static var tableHeaders: [String] { ["Account", "Mailbox", "Unread", "Total"] }
    public var tableRow: [String] {
        [account, name, "\(unreadCount)", "\(messageCount)"]
    }
}

// MARK: - MailAccount

public struct MailAccount: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "name", "emailAddresses",
    ]

    public let name: String
    public let emailAddresses: [String]

    public init(name: String, emailAddresses: [String] = []) {
        self.name = name
        self.emailAddresses = emailAddresses
    }
}

extension MailAccount: TextRepresentable {
    public var textSummary: String { name }

    public var textDetail: String {
        var lines = [name]
        for email in emailAddresses {
            lines.append("  Email:  \(email)")
        }
        return lines.joined(separator: "\n")
    }
}

extension MailAccount: TableRepresentable {
    public static var tableHeaders: [String] { ["Account", "Email"] }
    public var tableRow: [String] {
        [name, emailAddresses.first ?? "-"]
    }
}
