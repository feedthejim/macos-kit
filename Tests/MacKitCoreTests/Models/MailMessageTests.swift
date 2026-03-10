import Foundation
import Testing
@testable import MacKitCore

@Suite("MailMessage Model")
struct MailMessageTests {
    private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func message(
        id: String = "1",
        subject: String = "Test Subject",
        sender: String = "alice@example.com",
        isRead: Bool = false,
        mailbox: String = "INBOX",
        account: String = "iCloud",
        content: String? = nil
    ) -> MailMessage {
        MailMessage(
            id: id, subject: subject, sender: sender,
            dateReceived: sampleDate, isRead: isRead,
            mailbox: mailbox, account: account, content: content,
            summary: content.map { String($0.prefix(200)) }
        )
    }

    @Test("FieldSelectable lists expected fields")
    func fieldSelectable() {
        #expect(MailMessage.availableFields.contains("subject"))
        #expect(MailMessage.availableFields.contains("sender"))
        #expect(MailMessage.availableFields.contains("isRead"))
        #expect(MailMessage.availableFields.contains("content"))
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let msg = message(content: "Hello world")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(MailMessage.self, from: data)
        #expect(decoded == msg)
    }

    @Test("TextSummary shows unread marker for unread messages")
    func textSummaryUnread() {
        let msg = message(isRead: false)
        #expect(msg.textSummary.hasPrefix("*"))
    }

    @Test("TextSummary shows space for read messages")
    func textSummaryRead() {
        let msg = message(isRead: true)
        #expect(msg.textSummary.hasPrefix(" "))
    }

    @Test("TextDetail includes sender and mailbox")
    func textDetail() {
        let msg = message(sender: "bob@test.com", mailbox: "INBOX", account: "Gmail")
        let detail = msg.textDetail
        #expect(detail.contains("bob@test.com"))
        #expect(detail.contains("INBOX"))
        #expect(detail.contains("Gmail"))
    }

    @Test("TableRow shows NEW for unread")
    func tableRowUnread() {
        let msg = message(isRead: false)
        #expect(msg.tableRow[0] == "NEW")
    }

    @Test("TableRow shows read for read messages")
    func tableRowRead() {
        let msg = message(isRead: true)
        #expect(msg.tableRow[0] == "read")
    }
}

@Suite("Mailbox Model")
struct MailboxTests {
    @Test("TextSummary includes unread count when non-zero")
    func textSummaryUnread() {
        let mb = Mailbox(name: "INBOX", account: "iCloud", unreadCount: 5, messageCount: 100)
        #expect(mb.textSummary.contains("5 unread"))
    }

    @Test("TextSummary omits unread count when zero")
    func textSummaryNoUnread() {
        let mb = Mailbox(name: "INBOX", account: "iCloud", unreadCount: 0)
        #expect(!mb.textSummary.contains("unread"))
    }

    @Test("TableRow includes all fields")
    func tableRow() {
        let mb = Mailbox(name: "Sent", account: "Gmail", unreadCount: 2, messageCount: 50)
        #expect(mb.tableRow == ["Gmail", "Sent", "2", "50"])
    }
}

@Suite("MailAccount Model")
struct MailAccountTests {
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let acct = MailAccount(name: "iCloud", emailAddresses: ["me@icloud.com"])
        let data = try JSONEncoder().encode(acct)
        let decoded = try JSONDecoder().decode(MailAccount.self, from: data)
        #expect(decoded == acct)
    }

    @Test("TextDetail lists emails")
    func textDetail() {
        let acct = MailAccount(name: "Work", emailAddresses: ["a@work.com", "b@work.com"])
        #expect(acct.textDetail.contains("a@work.com"))
        #expect(acct.textDetail.contains("b@work.com"))
    }
}
