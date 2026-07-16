import Foundation
@testable import MacKitCore

final class MockMailService: MailServiceProtocol, @unchecked Sendable {
    var mockAccounts: [MailAccount] = []
    var mockMailboxes: [Mailbox] = []
    var mockMessages: [MailMessage] = []
    var shouldFail = false
    var isRunning = true
    var lastIncludeDetails = false

    func ensureRunning() async throws {
        if !isRunning {
            throw MacKitError.appNotRunning("Mail")
        }
    }

    func accounts() async throws -> [MailAccount] {
        try await ensureRunning()
        return mockAccounts
    }

    func mailboxes(account: String?) async throws -> [Mailbox] {
        try await ensureRunning()
        if let account {
            return mockMailboxes.filter { $0.account == account }
        }
        return mockMailboxes
    }

    func queryMessages(_ query: MailQuery) async throws -> MailPage {
        try await ensureRunning()
        lastIncludeDetails = query.includeDetails
        var results = mockMessages
        if let mailbox = query.mailbox { results = results.filter { $0.mailbox == mailbox } }
        if let account = query.account { results = results.filter { $0.account == account } }
        if let sender = query.sender?.lowercased() {
            results = results.filter { $0.sender.lowercased().contains(sender) }
        }
        if let after = query.receivedAfter { results = results.filter { $0.dateReceived > after } }
        if let before = query.receivedBefore { results = results.filter { $0.dateReceived < before } }
        if query.unreadOnly { results = results.filter { !$0.isRead } }
        if let search = query.search?.lowercased() {
            results = results.filter {
                $0.subject.lowercased().contains(search) || $0.sender.lowercased().contains(search)
            }
        }
        results.sort { $0.dateReceived > $1.dateReceived }
        let page = Array(results.dropFirst(query.offset).prefix(query.limit))
        let nextOffset = results.count > query.offset + page.count
            ? query.offset + page.count : nil
        return MailPage(messages: page, offset: query.offset, nextOffset: nextOffset)
    }

    func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool, includeDetails: Bool) async throws -> [MailMessage] {
        try await ensureRunning()
        lastIncludeDetails = includeDetails
        var results = mockMessages
        if let mailbox { results = results.filter { $0.mailbox == mailbox } }
        if let account { results = results.filter { $0.account == account } }
        if unreadOnly { results = results.filter { !$0.isRead } }
        return Array(results.prefix(limit))
    }

    func searchMessages(query: String, mailbox: String?, account: String?, limit: Int, includeDetails: Bool) async throws -> [MailMessage] {
        try await ensureRunning()
        lastIncludeDetails = includeDetails
        let lowerQuery = query.lowercased()
        var results = mockMessages.filter {
            $0.subject.lowercased().contains(lowerQuery)
            || $0.sender.lowercased().contains(lowerQuery)
            || ($0.content?.lowercased().contains(lowerQuery) ?? false)
        }
        if let mailbox { results = results.filter { $0.mailbox == mailbox } }
        if let account { results = results.filter { $0.account == account } }
        return Array(results.prefix(limit))
    }

    func getMessage(id: String, mailbox: String, account: String) async throws -> MailMessage {
        try await ensureRunning()
        guard let msg = mockMessages.first(where: { $0.id == id }) else {
            throw MacKitError.notFound("Message \(id)")
        }
        return msg
    }

    func sendMessage(to: [String], cc: [String], bcc: [String], subject: String, body: String, from: String?) async throws {
        try await ensureRunning()
        if shouldFail { throw MacKitError.systemError("Send failed") }
    }

    func markRead(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
    }

    func markUnread(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
    }

    func moveMessage(id: String, fromMailbox: String, toMailbox: String, account: String) async throws {
        try await ensureRunning()
    }

    func deleteMessage(id: String, mailbox: String, account: String) async throws {
        try await ensureRunning()
    }
}
