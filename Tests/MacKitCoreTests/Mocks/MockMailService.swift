import Foundation
@testable import MacKitCore

final class MockMailService: MailServiceProtocol, @unchecked Sendable {
    var mockAccounts: [MailAccount] = []
    var mockMailboxes: [Mailbox] = []
    var mockMessages: [MailMessage] = []
    var shouldFail = false
    var isRunning = true

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

    func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool) async throws -> [MailMessage] {
        try await ensureRunning()
        var results = mockMessages
        if let mailbox { results = results.filter { $0.mailbox == mailbox } }
        if let account { results = results.filter { $0.account == account } }
        if unreadOnly { results = results.filter { !$0.isRead } }
        return Array(results.prefix(limit))
    }

    func searchMessages(query: String, mailbox: String?, account: String?, limit: Int) async throws -> [MailMessage] {
        try await ensureRunning()
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
