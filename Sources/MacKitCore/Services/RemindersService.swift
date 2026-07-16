import Foundation

public protocol RemindersServiceProtocol: Sendable {
    func requestAccess() async throws
    func lists() async throws -> [ReminderList]
    func reminders(inList listName: String?, includeCompleted: Bool, dueBefore: Date?, limit: Int?) async throws -> [Reminder]
    func overdueReminders() async throws -> [Reminder]
}

public extension RemindersServiceProtocol {
    func reminders(inList listName: String?, includeCompleted: Bool, dueBefore: Date?) async throws -> [Reminder] {
        try await reminders(
            inList: listName,
            includeCompleted: includeCompleted,
            dueBefore: dueBefore,
            limit: nil
        )
    }
}
