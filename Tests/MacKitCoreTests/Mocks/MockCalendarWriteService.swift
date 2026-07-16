import Foundation
@testable import MacKitCore

final class MockCalendarWriteService: CalendarWriteServiceProtocol, @unchecked Sendable {
    var mockEvents: [CalendarEvent] = []
    var createdEvents: [CalendarEvent] = []
    var deletedIds: [String] = []
    var deletedScopes: [EventMutationScope] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.calendars)
        }
    }

    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MacKitError.systemError("Event title cannot be empty.") }
        let dates = try normalizedDates(start: request.startDate, end: request.endDate, isAllDay: request.isAllDay)
        let event = CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: dates.start,
            endDate: dates.end,
            isAllDay: request.isAllDay,
            location: request.location,
            calendarName: request.calendarName ?? "Default",
            notes: request.notes
        )
        createdEvents.append(event)
        mockEvents.append(event)
        return event
    }

    func deleteEvent(id: String, scope: EventMutationScope) async throws {
        try await requestAccess()
        guard let index = mockEvents.firstIndex(where: { $0.id == id }) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        mockEvents.remove(at: index)
        deletedIds.append(id)
        deletedScopes.append(scope)
    }

    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        guard let index = mockEvents.firstIndex(where: { $0.id == request.eventId }) else {
            throw MacKitError.notFound("Event with id '\(request.eventId)'")
        }
        let existing = mockEvents[index]
        let title = try request.title.map(validatedTitle) ?? existing.title
        let isAllDay = request.isAllDay ?? existing.isAllDay
        let dates = try normalizedDates(
            start: request.startDate ?? existing.startDate,
            end: request.endDate ?? existing.endDate,
            isAllDay: isAllDay
        )
        let location: String? = switch request.location {
        case .unchanged: existing.location
        case .set(let value): value
        case .clear: nil
        }
        let notes: String? = switch request.notes {
        case .unchanged: existing.notes
        case .set(let value): value
        case .clear: nil
        }
        let updated = CalendarEvent(
            id: existing.id,
            title: title,
            startDate: dates.start,
            endDate: dates.end,
            isAllDay: isAllDay,
            location: location,
            calendarId: existing.calendarId,
            calendarName: request.calendarName ?? existing.calendarName,
            calendarColor: existing.calendarColor,
            status: existing.status,
            availability: existing.availability,
            isRecurring: existing.isRecurring,
            attendees: existing.attendees,
            organizer: existing.organizer,
            notes: notes,
            url: existing.url,
            meetingURL: existing.meetingURL
        )
        mockEvents[index] = updated
        return updated
    }

    func findEvent(id: String) async throws -> CalendarEvent {
        try await requestAccess()
        guard let event = mockEvents.first(where: { $0.id == id }) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        return event
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

    private func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MacKitError.systemError("Event title cannot be empty.")
        }
        return trimmed
    }
}
