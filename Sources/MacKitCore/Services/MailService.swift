import Foundation

public protocol MailServiceProtocol: Sendable {
    func ensureRunning() async throws
    func accounts() async throws -> [MailAccount]
    func mailboxes(account: String?) async throws -> [Mailbox]
    func messages(mailbox: String?, account: String?, limit: Int, unreadOnly: Bool) async throws -> [MailMessage]
    func searchMessages(query: String, mailbox: String?, account: String?, limit: Int) async throws -> [MailMessage]
    func getMessage(id: String, mailbox: String, account: String) async throws -> MailMessage
    func sendMessage(to: [String], cc: [String], bcc: [String], subject: String, body: String, from: String?) async throws
    func markRead(id: String, mailbox: String, account: String) async throws
    func markUnread(id: String, mailbox: String, account: String) async throws
    func moveMessage(id: String, fromMailbox: String, toMailbox: String, account: String) async throws
    func deleteMessage(id: String, mailbox: String, account: String) async throws
}
