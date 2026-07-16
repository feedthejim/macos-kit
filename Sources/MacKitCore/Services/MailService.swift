import Foundation

public protocol MailServiceProtocol: Sendable {
    func ensureRunning() async throws
    func accounts() async throws -> [MailAccount]
    func mailboxes(account: String?) async throws -> [Mailbox]
    func queryMessages(_ query: MailQuery) async throws -> MailPage
    func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool, includeDetails: Bool) async throws -> [MailMessage]
    func searchMessages(query: String, mailbox: String?, account: String?, limit: Int, includeDetails: Bool) async throws -> [MailMessage]
    func getMessage(id: String, mailbox: String, account: String) async throws -> MailMessage
    func sendMessage(to: [String], cc: [String], bcc: [String], subject: String, body: String, from: String?) async throws
    func markRead(id: String, mailbox: String, account: String) async throws
    func markUnread(id: String, mailbox: String, account: String) async throws
    func moveMessage(id: String, fromMailbox: String, toMailbox: String, account: String) async throws
    func deleteMessage(id: String, mailbox: String, account: String) async throws
}

public extension MailServiceProtocol {
    func queryMessages(_ query: MailQuery) async throws -> MailPage {
        let results: [MailMessage]
        if let search = query.search {
            results = try await searchMessages(
                query: search, mailbox: query.mailbox, account: query.account,
                limit: query.limit, includeDetails: query.includeDetails
            )
        } else {
            results = try await messages(
                mailbox: query.mailbox, account: query.account, limit: query.limit,
                unreadOnly: query.unreadOnly, includeDetails: query.includeDetails
            )
        }
        return MailPage(messages: results, offset: query.offset)
    }
    func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool) async throws -> [MailMessage] {
        try await messages(mailbox: mailbox, account: account, limit: limit, unreadOnly: unreadOnly, includeDetails: false)
    }

    func searchMessages(query: String, mailbox: String?, account: String?, limit: Int) async throws -> [MailMessage] {
        try await searchMessages(query: query, mailbox: mailbox, account: account, limit: limit, includeDetails: false)
    }
}
