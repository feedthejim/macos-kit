import Foundation

public struct MailAttachment: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let mimeType: String?
    public let sizeBytes: Int
    public let isDownloaded: Bool

    public init(
        id: String, name: String, mimeType: String? = nil,
        sizeBytes: Int = 0, isDownloaded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.isDownloaded = isDownloaded
    }
}

public struct MailMessage: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "id", "subject", "sender", "dateSent", "dateReceived",
        "isRead", "mailbox", "account", "toRecipients", "ccRecipients",
        "messageId", "replyTo", "messageSize", "threadId", "attachmentCount",
        "attachments", "content", "summary",
    ]
    public static let detailFields: Set<String> = [
        "toRecipients", "ccRecipients", "attachmentCount", "attachments", "content", "summary",
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
    public let messageId: String?
    public let replyTo: String?
    public let messageSize: Int?
    public let threadId: String
    public let attachmentCount: Int
    public let attachments: [MailAttachment]
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
        messageId: String? = nil,
        replyTo: String? = nil,
        messageSize: Int? = nil,
        threadId: String? = nil,
        attachmentCount: Int = 0,
        attachments: [MailAttachment] = [],
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
        self.messageId = messageId
        self.replyTo = replyTo
        self.messageSize = messageSize
        self.threadId = threadId ?? MailThreading.normalizedSubject(subject)
        self.attachmentCount = attachmentCount
        self.attachments = attachments
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
        if attachmentCount > 0 {
            lines.append("  Attachments: \(attachmentCount)")
        }
        if let content, !content.isEmpty {
            lines.append("  ---")
            lines.append("  \(content.prefix(500))")
        }
        return lines.joined(separator: "\n")
    }
}

public enum MailThreading {
    public static func normalizedSubject(_ subject: String) -> String {
        var value = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = ["re:", "fw:", "fwd:"]
        while let prefix = prefixes.first(where: { value.hasPrefix($0) }) {
            value.removeFirst(prefix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

public struct MailQuery: Sendable {
    public var search: String?
    public var mailbox: String?
    public var account: String?
    public var sender: String?
    public var receivedAfter: Date?
    public var receivedBefore: Date?
    public var unreadOnly: Bool
    public var limit: Int
    public var offset: Int
    public var includeDetails: Bool
    public var requestedFields: Set<String>

    public init(
        search: String? = nil, mailbox: String? = nil, account: String? = nil,
        sender: String? = nil, receivedAfter: Date? = nil, receivedBefore: Date? = nil,
        unreadOnly: Bool = false, limit: Int = 25, offset: Int = 0,
        includeDetails: Bool = false, requestedFields: Set<String> = []
    ) {
        self.search = search
        self.mailbox = mailbox
        self.account = account
        self.sender = sender
        self.receivedAfter = receivedAfter
        self.receivedBefore = receivedBefore
        self.unreadOnly = unreadOnly
        self.limit = max(0, limit)
        self.offset = max(0, offset)
        self.includeDetails = includeDetails
        self.requestedFields = requestedFields
    }
}

public struct MailPage: Codable, Sendable, Equatable {
    public let messages: [MailMessage]
    public let offset: Int
    public let nextOffset: Int?
    public let isPartial: Bool
    public let warnings: [String]

    public init(
        messages: [MailMessage], offset: Int, nextOffset: Int? = nil,
        isPartial: Bool = false, warnings: [String] = []
    ) {
        self.messages = messages
        self.offset = offset
        self.nextOffset = nextOffset
        self.isPartial = isPartial
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case offset
        case nextOffset
        case isPartial = "partial"
        case warnings
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
