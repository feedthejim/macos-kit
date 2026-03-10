@preconcurrency import EventKit
import Foundation

public final class LiveRemindersWriteService: RemindersWriteServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }

        guard granted else {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            switch status {
            case .denied, .restricted:
                throw MacKitError.permissionDenied(.reminders)
            default:
                throw MacKitError.permissionNotDetermined(.reminders)
            }
        }
    }

    public func addReminder(title: String, listName: String?, dueDate: Date?, priority: ReminderPriority?, notes: String?) async throws -> Reminder {
        let ekReminder = EKReminder(eventStore: store)
        ekReminder.title = title

        if let listName {
            guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
                throw MacKitError.notFound("Reminder list '\(listName)'")
            }
            ekReminder.calendar = calendar
        } else {
            ekReminder.calendar = store.defaultCalendarForNewReminders()
        }

        if let dueDate {
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueDate
            )
        }

        if let priority {
            ekReminder.priority = priority.rawValue
        }

        ekReminder.notes = notes

        try store.save(ekReminder, commit: true)

        return mapReminder(ekReminder)
    }

    public func completeReminder(titleMatch: String) async throws -> Reminder {
        let ekReminders = try await fetchEKReminders(
            matching: store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
        )

        let lowered = titleMatch.lowercased()
        guard let match = ekReminders.first(where: { ($0.title ?? "").lowercased().contains(lowered) }) else {
            throw MacKitError.notFound("Reminder matching '\(titleMatch)'")
        }

        match.isCompleted = true
        try store.save(match, commit: true)

        return mapReminder(match)
    }

    public func completeReminderById(id: String) async throws -> Reminder {
        guard let ekReminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }

        ekReminder.isCompleted = true
        try store.save(ekReminder, commit: true)

        return mapReminder(ekReminder)
    }

    public func deleteReminder(id: String) async throws {
        guard let ekReminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }

        try store.remove(ekReminder, commit: true)
    }

    public func moveReminder(titleMatch: String, toList: String) async throws -> Reminder {
        let ekReminders = try await fetchEKReminders(
            matching: store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
        )

        let lowered = titleMatch.lowercased()
        guard let match = ekReminders.first(where: { ($0.title ?? "").lowercased().contains(lowered) }) else {
            throw MacKitError.notFound("Reminder matching '\(titleMatch)'")
        }

        guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == toList }) else {
            throw MacKitError.notFound("Reminder list '\(toList)'")
        }

        match.calendar = calendar
        try store.save(match, commit: true)

        return mapReminder(match)
    }

    // MARK: - Private

    /// Fetch raw EKReminder objects for mutation. We need mutable EKReminder objects
    /// to update properties (isCompleted, calendar, etc.) before saving.
    /// EKReminder is not Sendable, so we use nonisolated(unsafe) to bridge it across
    /// the concurrency boundary, which is safe because EventKit synchronizes internally.
    private func fetchEKReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { ekReminders in
                nonisolated(unsafe) let result = ekReminders ?? []
                continuation.resume(returning: result)
            }
        }
    }

    private func mapReminder(_ ekReminder: EKReminder) -> Reminder {
        Reminder(
            id: ekReminder.calendarItemIdentifier,
            title: ekReminder.title ?? "(No title)",
            dueDate: ekReminder.dueDateComponents?.date,
            isCompleted: ekReminder.isCompleted,
            completionDate: ekReminder.completionDate,
            priority: ReminderPriority(fromEKPriority: ekReminder.priority),
            listName: ekReminder.calendar.title,
            notes: ekReminder.notes
        )
    }
}
