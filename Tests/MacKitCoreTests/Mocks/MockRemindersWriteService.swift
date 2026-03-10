import Foundation
@testable import MacKitCore

final class MockRemindersWriteService: RemindersWriteServiceProtocol, @unchecked Sendable {
    var mockReminders: [Reminder] = []
    var shouldDenyPermission = false
    private var nextId = 1

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.reminders)
        }
    }

    func addReminder(title: String, listName: String?, dueDate: Date?, priority: ReminderPriority?, notes: String?) async throws -> Reminder {
        try await requestAccess()
        let reminder = Reminder(
            id: "mock-\(nextId)",
            title: title,
            dueDate: dueDate,
            isCompleted: false,
            priority: priority ?? .none,
            listName: listName ?? "Default",
            notes: notes
        )
        nextId += 1
        mockReminders.append(reminder)
        return reminder
    }

    func completeReminder(titleMatch: String) async throws -> Reminder {
        try await requestAccess()
        let lowered = titleMatch.lowercased()
        guard let index = mockReminders.firstIndex(where: {
            !$0.isCompleted && $0.title.lowercased().contains(lowered)
        }) else {
            throw MacKitError.notFound("Reminder matching '\(titleMatch)'")
        }

        let original = mockReminders[index]
        let completed = Reminder(
            id: original.id,
            title: original.title,
            dueDate: original.dueDate,
            isCompleted: true,
            completionDate: Date(),
            priority: original.priority,
            listName: original.listName,
            notes: original.notes
        )
        mockReminders[index] = completed
        return completed
    }

    func completeReminderById(id: String) async throws -> Reminder {
        try await requestAccess()
        guard let index = mockReminders.firstIndex(where: { $0.id == id && !$0.isCompleted }) else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }

        let original = mockReminders[index]
        let completed = Reminder(
            id: original.id,
            title: original.title,
            dueDate: original.dueDate,
            isCompleted: true,
            completionDate: Date(),
            priority: original.priority,
            listName: original.listName,
            notes: original.notes
        )
        mockReminders[index] = completed
        return completed
    }

    func deleteReminder(id: String) async throws {
        try await requestAccess()
        guard let index = mockReminders.firstIndex(where: { $0.id == id }) else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }
        mockReminders.remove(at: index)
    }

    func moveReminder(titleMatch: String, toList: String) async throws -> Reminder {
        try await requestAccess()
        let lowered = titleMatch.lowercased()
        guard let index = mockReminders.firstIndex(where: {
            !$0.isCompleted && $0.title.lowercased().contains(lowered)
        }) else {
            throw MacKitError.notFound("Reminder matching '\(titleMatch)'")
        }

        let original = mockReminders[index]
        let moved = Reminder(
            id: original.id,
            title: original.title,
            dueDate: original.dueDate,
            isCompleted: original.isCompleted,
            completionDate: original.completionDate,
            priority: original.priority,
            listName: toList,
            notes: original.notes
        )
        mockReminders[index] = moved
        return moved
    }
}
