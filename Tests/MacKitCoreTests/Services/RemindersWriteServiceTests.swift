import Testing
import Foundation
@testable import MacKitCore

@Suite("RemindersWriteService")
struct RemindersWriteServiceTests {

    // MARK: - addReminder

    @Test("Add reminder returns correct fields")
    func addReturnsCorrectFields() async throws {
        let mock = MockRemindersWriteService()
        let dueDate = Date().addingTimeInterval(3600)

        let result = try await mock.addReminder(
            title: "Buy groceries",
            listName: "Shopping",
            dueDate: dueDate,
            priority: .high,
            notes: "Milk and eggs"
        )

        #expect(result.title == "Buy groceries")
        #expect(result.listName == "Shopping")
        #expect(result.dueDate == dueDate)
        #expect(result.priority == .high)
        #expect(result.notes == "Milk and eggs")
        #expect(!result.isCompleted)
        #expect(mock.mockReminders.count == 1)
    }

    @Test("Add reminder uses default list when none specified")
    func addUsesDefaultList() async throws {
        let mock = MockRemindersWriteService()

        let result = try await mock.addReminder(
            title: "Something",
            listName: nil,
            dueDate: nil,
            priority: nil,
            notes: nil
        )

        #expect(result.listName == "Default")
        #expect(result.priority == .none)
    }

    // MARK: - completeReminder

    @Test("Complete by fuzzy title match")
    func completeFuzzyMatch() async throws {
        let mock = MockRemindersWriteService()
        _ = try await mock.addReminder(title: "Buy groceries from store", listName: "Shopping", dueDate: nil, priority: nil, notes: nil)
        _ = try await mock.addReminder(title: "Review PR", listName: "Work", dueDate: nil, priority: nil, notes: nil)

        let result = try await mock.completeReminder(titleMatch: "groceries")

        #expect(result.isCompleted)
        #expect(result.title == "Buy groceries from store")
        #expect(result.completionDate != nil)
    }

    @Test("Complete is case-insensitive")
    func completeCaseInsensitive() async throws {
        let mock = MockRemindersWriteService()
        _ = try await mock.addReminder(title: "Buy Milk", listName: nil, dueDate: nil, priority: nil, notes: nil)

        let result = try await mock.completeReminder(titleMatch: "buy milk")

        #expect(result.isCompleted)
        #expect(result.title == "Buy Milk")
    }

    @Test("Complete non-existent throws notFound")
    func completeNotFound() async throws {
        let mock = MockRemindersWriteService()
        _ = try await mock.addReminder(title: "Buy milk", listName: nil, dueDate: nil, priority: nil, notes: nil)

        await #expect(throws: MacKitError.self) {
            try await mock.completeReminder(titleMatch: "nonexistent")
        }
    }

    // MARK: - moveReminder

    @Test("Move changes list name")
    func moveChangesListName() async throws {
        let mock = MockRemindersWriteService()
        _ = try await mock.addReminder(title: "Buy milk", listName: "Shopping", dueDate: nil, priority: nil, notes: nil)

        let result = try await mock.moveReminder(titleMatch: "milk", toList: "Groceries")

        #expect(result.listName == "Groceries")
        #expect(result.title == "Buy milk")
        #expect(mock.mockReminders[0].listName == "Groceries")
    }

    @Test("Move non-existent throws notFound")
    func moveNotFound() async throws {
        let mock = MockRemindersWriteService()

        await #expect(throws: MacKitError.self) {
            try await mock.moveReminder(titleMatch: "nonexistent", toList: "Work")
        }
    }

    // MARK: - deleteReminder

    @Test("Delete removes reminder")
    func deleteRemovesReminder() async throws {
        let mock = MockRemindersWriteService()
        let added = try await mock.addReminder(title: "Buy milk", listName: "Shopping", dueDate: nil, priority: nil, notes: nil)

        #expect(mock.mockReminders.count == 1)

        try await mock.deleteReminder(id: added.id)

        #expect(mock.mockReminders.isEmpty)
    }

    @Test("Delete non-existent throws notFound")
    func deleteNotFound() async throws {
        let mock = MockRemindersWriteService()

        await #expect(throws: MacKitError.self) {
            try await mock.deleteReminder(id: "nonexistent-id")
        }
    }

    // MARK: - Permission handling

    @Test("Permission denied throws correct error")
    func permissionDenied() async {
        let mock = MockRemindersWriteService()
        mock.shouldDenyPermission = true

        await #expect(throws: MacKitError.self) {
            try await mock.addReminder(title: "Test", listName: nil, dueDate: nil, priority: nil, notes: nil)
        }
    }
}
