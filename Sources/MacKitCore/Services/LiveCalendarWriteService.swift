import EventKit
import Foundation

public final class LiveCalendarWriteService: CalendarWriteServiceProtocol, @unchecked Sendable {
    private static let permissionTimeoutSeconds = 30
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted = try await withAsyncTimeout(
            seconds: Self.permissionTimeoutSeconds,
            timeoutError: permissionTimeoutError(.calendars)
        ) { [self] in
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        }

        guard granted else {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .denied, .restricted:
                throw MacKitError.permissionDenied(.calendars)
            default:
                throw MacKitError.permissionNotDetermined(.calendars)
            }
        }
    }

    public func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        let title = try validatedTitle(request.title)
        let dates = try normalizedDates(
            start: request.startDate,
            end: request.endDate,
            isAllDay: request.isAllDay
        )
        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = title
        ekEvent.startDate = dates.start
        ekEvent.endDate = dates.end
        ekEvent.isAllDay = request.isAllDay
        ekEvent.location = request.location
        ekEvent.notes = request.notes

        if let calendarName = request.calendarName {
            ekEvent.calendar = try writableCalendar(matching: calendarName)
        } else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw MacKitError.notFound("Default calendar")
            }
            guard calendar.allowsContentModifications else {
                throw MacKitError.systemError("The default calendar is read-only.")
            }
            ekEvent.calendar = calendar
        }

        try store.save(ekEvent, span: .thisEvent)
        return EventKitMapper.mapEvent(ekEvent)
    }

    public func deleteEvent(id: String, scope: EventMutationScope) async throws {
        try await requestAccess()
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        try store.remove(ekEvent, span: eventSpan(scope))
    }

    public func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        guard let ekEvent = store.event(withIdentifier: request.eventId) else {
            throw MacKitError.notFound("Event with id '\(request.eventId)'")
        }

        if let title = request.title { ekEvent.title = try validatedTitle(title) }

        let isAllDay = request.isAllDay ?? ekEvent.isAllDay
        let dates = try normalizedDates(
            start: request.startDate ?? ekEvent.startDate,
            end: request.endDate ?? ekEvent.endDate,
            isAllDay: isAllDay
        )
        ekEvent.startDate = dates.start
        ekEvent.endDate = dates.end
        ekEvent.isAllDay = isAllDay

        switch request.location {
        case .unchanged: break
        case .set(let value): ekEvent.location = value
        case .clear: ekEvent.location = nil
        }
        switch request.notes {
        case .unchanged: break
        case .set(let value): ekEvent.notes = value
        case .clear: ekEvent.notes = nil
        }
        if let calendarName = request.calendarName {
            ekEvent.calendar = try writableCalendar(matching: calendarName)
        }

        try store.save(ekEvent, span: eventSpan(request.scope))
        return EventKitMapper.mapEvent(ekEvent)
    }

    public func findEvent(id: String) async throws -> CalendarEvent {
        try await requestAccess()
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        return EventKitMapper.mapEvent(ekEvent)
    }

    private func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MacKitError.systemError("Event title cannot be empty.")
        }
        return trimmed
    }

    private func normalizedDates(start: Date, end: Date, isAllDay: Bool) throws -> (start: Date, end: Date) {
        if isAllDay {
            let calendar = Calendar.current
            let normalizedStart = calendar.startOfDay(for: start)
            var normalizedEnd = calendar.startOfDay(for: end)
            if normalizedEnd <= normalizedStart {
                normalizedEnd = calendar.date(byAdding: .day, value: 1, to: normalizedStart)!
            }
            return (normalizedStart, normalizedEnd)
        }

        guard end > start else {
            throw MacKitError.systemError("Event end time must be after its start time.")
        }
        return (start, end)
    }

    private func writableCalendar(matching reference: String) throws -> EKCalendar {
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .event)
        if let byIdentifier = calendars.first(where: { $0.calendarIdentifier == reference }) {
            guard byIdentifier.allowsContentModifications else {
                throw MacKitError.systemError("Calendar '\(byIdentifier.title)' is read-only.")
            }
            return byIdentifier
        }

        let byTitle = calendars.filter { $0.title == reference }
        guard !byTitle.isEmpty else {
            throw MacKitError.notFound("Calendar '\(reference)'")
        }
        guard byTitle.count == 1 else {
            throw MacKitError.systemError(
                "More than one calendar is named '\(reference)'. Use the calendar ID from 'mackit cal calendars --format json'."
            )
        }
        guard byTitle[0].allowsContentModifications else {
            throw MacKitError.systemError("Calendar '\(reference)' is read-only.")
        }
        return byTitle[0]
    }

    private func eventSpan(_ scope: EventMutationScope) -> EKSpan {
        scope == .futureEvents ? .futureEvents : .thisEvent
    }
}
