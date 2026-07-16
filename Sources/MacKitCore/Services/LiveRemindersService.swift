@preconcurrency import EventKit
import Foundation

public final class LiveRemindersService: RemindersServiceProtocol, @unchecked Sendable {
    private static let permissionTimeoutSeconds = 30
    private static let fetchTimeoutSeconds = 30
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted = try await withAsyncTimeout(
            seconds: Self.permissionTimeoutSeconds,
            timeoutError: permissionTimeoutError(.reminders)
        ) { [self] in
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToReminders()
            } else {
                return try await store.requestAccess(to: .reminder)
            }
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

    public func lists() async throws -> [ReminderList] {
        let ekCalendars = store.calendars(for: .reminder)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        let counts = try await fetchReminderCounts(matching: predicate)

        return ekCalendars.map { cal in
            ReminderList(
                id: cal.calendarIdentifier,
                title: cal.title,
                count: counts[cal.calendarIdentifier, default: 0],
                color: cal.cgColor.flatMap { hexColor(from: $0) }
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func reminders(inList listName: String?, includeCompleted: Bool, dueBefore: Date?, limit: Int?) async throws -> [Reminder] {
        let calendars: [EKCalendar]?
        if let listName {
            calendars = store.calendars(for: .reminder).filter { $0.title == listName }
            if calendars?.isEmpty ?? true {
                throw MacKitError.notFound("Reminder list '\(listName)'")
            }
        } else {
            calendars = nil
        }

        let predicate: NSPredicate
        if includeCompleted {
            predicate = store.predicateForReminders(in: calendars)
        } else {
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: dueBefore,
                calendars: calendars
            )
        }

        let sorted = try await fetchReminders(matching: predicate)
            .sorted { sortReminders($0, $1) }
        guard let limit else { return sorted }
        return Array(sorted.prefix(max(0, limit)))
    }

    public func overdueReminders() async throws -> [Reminder] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Date(),
            calendars: nil
        )

        return try await fetchReminders(matching: predicate)
            .filter { reminder in
                guard let dueDate = reminder.dueDate else { return false }
                return dueDate < Date() && !reminder.isCompleted
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Fetch reminders and map to our Sendable Reminder type within the callback,
    /// avoiding sending non-Sendable EKReminder across concurrency boundaries.
    private func fetchReminders(matching predicate: NSPredicate) async throws -> [Reminder] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ReminderFetchGate<[Reminder]>(store: store, continuation: continuation)
            let request = store.fetchReminders(matching: predicate) { [self] ekReminders in
                let mapped = (ekReminders ?? []).map { self.mapReminder($0) }
                gate.resume(returning: mapped)
            }
            gate.install(fetchRequest: request, timeoutSeconds: Self.fetchTimeoutSeconds)
        }
    }

    private func fetchReminderCounts(matching predicate: NSPredicate) async throws -> [String: Int] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ReminderFetchGate<[String: Int]>(store: store, continuation: continuation)
            let request = store.fetchReminders(matching: predicate) { ekReminders in
                var counts: [String: Int] = [:]
                for reminder in ekReminders ?? [] {
                    counts[reminder.calendar.calendarIdentifier, default: 0] += 1
                }
                gate.resume(returning: counts)
            }
            gate.install(fetchRequest: request, timeoutSeconds: Self.fetchTimeoutSeconds)
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

    private func sortReminders(_ a: Reminder, _ b: Reminder) -> Bool {
        let now = Date()
        let aOverdue = a.dueDate.map { $0 < now } ?? false
        let bOverdue = b.dueDate.map { $0 < now } ?? false

        if aOverdue != bOverdue { return aOverdue }
        if let aDate = a.dueDate, let bDate = b.dueDate { return aDate < bDate }
        if a.dueDate != nil { return true }
        return false
    }

    private func hexColor(from cgColor: CGColor) -> String? {
        guard let components = cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
