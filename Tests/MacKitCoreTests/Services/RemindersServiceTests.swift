import Testing
import Foundation
@testable import MacKitCore

@Suite("RemindersService")
struct RemindersServiceTests {
    private func reminder(
        title: String,
        list: String = "Shopping",
        dueMinutesFromNow: Int? = nil,
        isCompleted: Bool = false,
        priority: ReminderPriority = .none
    ) -> Reminder {
        Reminder(
            id: UUID().uuidString,
            title: title,
            dueDate: dueMinutesFromNow.map { Date().addingTimeInterval(TimeInterval($0 * 60)) },
            isCompleted: isCompleted,
            priority: priority,
            listName: list
        )
    }

    // MARK: - reminders(inList:includeCompleted:dueBefore:)

    @Test("Returns only incomplete reminders by default")
    func defaultIncomplete() async throws {
        let mock = MockRemindersService()
        mock.mockReminders = [
            reminder(title: "Buy milk"),
            reminder(title: "Buy eggs"),
            reminder(title: "Done item", isCompleted: true),
        ]

        let result = try await mock.reminders(inList: nil, includeCompleted: false, dueBefore: nil)
        #expect(result.count == 2)
        #expect(result.allSatisfy { !$0.isCompleted })
    }

    @Test("Includes completed when flag is set")
    func includeCompleted() async throws {
        let mock = MockRemindersService()
        mock.mockReminders = [
            reminder(title: "A"),
            reminder(title: "B", isCompleted: true),
        ]

        let result = try await mock.reminders(inList: nil, includeCompleted: true, dueBefore: nil)
        #expect(result.count == 2)
    }

    @Test("Filters by list name")
    func filterByList() async throws {
        let mock = MockRemindersService()
        mock.mockReminders = [
            reminder(title: "Milk", list: "Shopping"),
            reminder(title: "PR review", list: "Work"),
            reminder(title: "Eggs", list: "Shopping"),
        ]

        let result = try await mock.reminders(inList: "Shopping", includeCompleted: false, dueBefore: nil)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.listName == "Shopping" })
    }

    // MARK: - overdueReminders()

    @Test("Returns reminders past due date that are incomplete")
    func overdueReturnsCorrect() async throws {
        let mock = MockRemindersService()
        mock.mockReminders = [
            reminder(title: "Overdue 1", dueMinutesFromNow: -60),
            reminder(title: "Overdue 2", dueMinutesFromNow: -1440),
            reminder(title: "Future", dueMinutesFromNow: 60),
            reminder(title: "Completed overdue", dueMinutesFromNow: -60, isCompleted: true),
            reminder(title: "No due date"),
        ]

        let result = try await mock.overdueReminders()
        #expect(result.count == 2)
        #expect(result[0].title == "Overdue 2") // Older first
        #expect(result[1].title == "Overdue 1")
    }

    @Test("No overdue reminders returns empty")
    func noOverdue() async throws {
        let mock = MockRemindersService()
        mock.mockReminders = [
            reminder(title: "Future", dueMinutesFromNow: 60),
            reminder(title: "No date"),
        ]

        let result = try await mock.overdueReminders()
        #expect(result.isEmpty)
    }

    // MARK: - Permission handling

    @Test("Permission denied throws correct error")
    func permissionDenied() async {
        let mock = MockRemindersService()
        mock.shouldDenyPermission = true

        await #expect(throws: MacKitError.self) {
            try await mock.reminders(inList: nil, includeCompleted: false, dueBefore: nil)
        }
    }

    // MARK: - Priority mapping

    @Test("Priority mapping from EK values")
    func priorityMapping() {
        #expect(ReminderPriority(fromEKPriority: 1) == .high)
        #expect(ReminderPriority(fromEKPriority: 3) == .high)
        #expect(ReminderPriority(fromEKPriority: 5) == .medium)
        #expect(ReminderPriority(fromEKPriority: 9) == .low)
        #expect(ReminderPriority(fromEKPriority: 7) == .low)
        #expect(ReminderPriority(fromEKPriority: 0) == .none)
    }
}
