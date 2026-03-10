import Foundation

public protocol RemindersWriteServiceProtocol: Sendable {
    func requestAccess() async throws
    func addReminder(title: String, listName: String?, dueDate: Date?, priority: ReminderPriority?, notes: String?) async throws -> Reminder
    func completeReminder(titleMatch: String) async throws -> Reminder
    func completeReminderById(id: String) async throws -> Reminder
    func deleteReminder(id: String) async throws
    func moveReminder(titleMatch: String, toList: String) async throws -> Reminder
}
