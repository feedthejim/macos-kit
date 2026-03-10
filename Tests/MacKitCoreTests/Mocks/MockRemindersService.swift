import Foundation
@testable import MacKitCore

final class MockRemindersService: RemindersServiceProtocol, @unchecked Sendable {
    var mockLists: [ReminderList] = []
    var mockReminders: [Reminder] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.reminders)
        }
    }

    func lists() async throws -> [ReminderList] {
        try await requestAccess()
        return mockLists
    }

    func reminders(inList listName: String?, includeCompleted: Bool, dueBefore: Date?) async throws -> [Reminder] {
        try await requestAccess()
        var result = mockReminders

        if let listName {
            result = result.filter { $0.listName == listName }
        }

        if !includeCompleted {
            result = result.filter { !$0.isCompleted }
        }

        if let dueBefore {
            result = result.filter { reminder in
                guard let due = reminder.dueDate else { return true }
                return due <= dueBefore
            }
        }

        return result
    }

    func overdueReminders() async throws -> [Reminder] {
        try await requestAccess()
        let now = Date()
        return mockReminders
            .filter { !$0.isCompleted }
            .filter { reminder in
                guard let due = reminder.dueDate else { return false }
                return due < now
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}
