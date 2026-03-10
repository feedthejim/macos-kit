import Testing
import Foundation
@testable import MacKitCore

@Suite("Reminder Model")
struct ReminderTests {
    // MARK: - Codable round-trip

    @Test("Encodes and decodes without data loss")
    func codableRoundTrip() throws {
        let original = Reminder(
            id: "rem-1",
            title: "Buy milk",
            dueDate: Date(timeIntervalSince1970: 1700000000),
            isCompleted: false,
            priority: .high,
            listName: "Shopping",
            notes: "Organic"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Reminder.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - TextRepresentable

    @Test("Incomplete reminder shows checkbox")
    func incompleteCheckbox() {
        let r = Reminder(id: "1", title: "Do thing", listName: "Work")
        #expect(r.textSummary.contains("☐"))
        #expect(r.textSummary.contains("Do thing"))
    }

    @Test("Completed reminder shows checked box")
    func completedCheckbox() {
        let r = Reminder(id: "1", title: "Done", isCompleted: true, listName: "Work")
        #expect(r.textSummary.contains("☑"))
    }

    @Test("Overdue reminder shows days overdue")
    func overdueText() {
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 3600)
        let r = Reminder(id: "1", title: "Late", dueDate: twoDaysAgo, listName: "Work")
        #expect(r.textSummary.contains("overdue"))
    }

    // MARK: - TableRepresentable

    @Test("Table headers match row count")
    func tableStructure() {
        let r = Reminder(id: "1", title: "Test", listName: "Work")
        #expect(Reminder.tableHeaders.count == r.tableRow.count)
    }

    // MARK: - Priority

    @Test("Priority labels are correct")
    func priorityLabels() {
        #expect(ReminderPriority.high.label == "high")
        #expect(ReminderPriority.medium.label == "medium")
        #expect(ReminderPriority.low.label == "low")
        #expect(ReminderPriority.none.label == "none")
    }
}
