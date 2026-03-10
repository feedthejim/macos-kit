import Foundation
import Testing
@testable import MacKitCore

@Suite("MailService")
struct MailServiceTests {
    private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func message(
        id: String = "1",
        subject: String = "Test",
        sender: String = "alice@test.com",
        isRead: Bool = false,
        mailbox: String = "INBOX",
        account: String = "iCloud",
        content: String? = nil
    ) -> MailMessage {
        MailMessage(
            id: id, subject: subject, sender: sender,
            dateReceived: sampleDate, isRead: isRead,
            mailbox: mailbox, account: account, content: content
        )
    }

    @Test("Messages filters by mailbox")
    func filterByMailbox() async throws {
        let mock = MockMailService()
        mock.mockMessages = [
            message(id: "1", mailbox: "INBOX"),
            message(id: "2", mailbox: "Sent"),
            message(id: "3", mailbox: "INBOX"),
        ]

        let results = try await mock.messages(mailbox: "INBOX", account: nil, limit: 25, unreadOnly: false)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.mailbox == "INBOX" })
    }

    @Test("Messages filters by account")
    func filterByAccount() async throws {
        let mock = MockMailService()
        mock.mockMessages = [
            message(id: "1", account: "iCloud"),
            message(id: "2", account: "Gmail"),
        ]

        let results = try await mock.messages(mailbox: nil, account: "iCloud", limit: 25, unreadOnly: false)
        #expect(results.count == 1)
        #expect(results[0].account == "iCloud")
    }

    @Test("Messages filters unread only")
    func filterUnreadOnly() async throws {
        let mock = MockMailService()
        mock.mockMessages = [
            message(id: "1", isRead: true),
            message(id: "2", isRead: false),
            message(id: "3", isRead: false),
        ]

        let results = try await mock.messages(mailbox: nil, account: nil, limit: 25, unreadOnly: true)
        #expect(results.count == 2)
        #expect(results.allSatisfy { !$0.isRead })
    }

    @Test("Messages respects limit")
    func respectsLimit() async throws {
        let mock = MockMailService()
        mock.mockMessages = (1...10).map { message(id: "\($0)") }

        let results = try await mock.messages(mailbox: nil, account: nil, limit: 3, unreadOnly: false)
        #expect(results.count == 3)
    }

    @Test("Search matches subject")
    func searchBySubject() async throws {
        let mock = MockMailService()
        mock.mockMessages = [
            message(id: "1", subject: "Meeting tomorrow"),
            message(id: "2", subject: "Invoice #123"),
            message(id: "3", subject: "Re: Meeting notes"),
        ]

        let results = try await mock.searchMessages(query: "meeting", mailbox: nil, account: nil, limit: 25)
        #expect(results.count == 2)
    }

    @Test("Search matches sender")
    func searchBySender() async throws {
        let mock = MockMailService()
        mock.mockMessages = [
            message(id: "1", sender: "bob@test.com"),
            message(id: "2", sender: "alice@test.com"),
        ]

        let results = try await mock.searchMessages(query: "bob", mailbox: nil, account: nil, limit: 25)
        #expect(results.count == 1)
    }

    @Test("GetMessage returns matching message")
    func getMessageById() async throws {
        let mock = MockMailService()
        mock.mockMessages = [
            message(id: "42", subject: "Found it"),
        ]

        let msg = try await mock.getMessage(id: "42", mailbox: "INBOX", account: "iCloud")
        #expect(msg.subject == "Found it")
    }

    @Test("GetMessage throws notFound for missing ID")
    func getMessageNotFound() async {
        let mock = MockMailService()
        await #expect(throws: MacKitError.self) {
            try await mock.getMessage(id: "999", mailbox: "INBOX", account: "iCloud")
        }
    }

    @Test("EnsureRunning throws when not running")
    func ensureRunningFails() async {
        let mock = MockMailService()
        mock.isRunning = false
        await #expect(throws: MacKitError.self) {
            try await mock.accounts()
        }
    }

    @Test("SendMessage throws when shouldFail is true")
    func sendMessageFails() async {
        let mock = MockMailService()
        mock.shouldFail = true
        await #expect(throws: MacKitError.self) {
            try await mock.sendMessage(to: ["a@test.com"], cc: [], bcc: [], subject: "Test", body: "Hi", from: nil)
        }
    }

    @Test("Mailboxes filters by account")
    func mailboxesByAccount() async throws {
        let mock = MockMailService()
        mock.mockMailboxes = [
            Mailbox(name: "INBOX", account: "iCloud"),
            Mailbox(name: "INBOX", account: "Gmail"),
            Mailbox(name: "Sent", account: "iCloud"),
        ]

        let results = try await mock.mailboxes(account: "iCloud")
        #expect(results.count == 2)
    }
}
