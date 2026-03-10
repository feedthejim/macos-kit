import Foundation
@testable import MacKitCore

final class MockCalendarWriteService: CalendarWriteServiceProtocol, @unchecked Sendable {
    var mockEvents: [CalendarEvent] = []
    var createdEvents: [CalendarEvent] = []
    var deletedIds: [String] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.calendars)
        }
    }

    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        let event = CalendarEvent(
            id: UUID().uuidString,
            title: request.title,
            startDate: request.startDate,
            endDate: request.endDate,
            isAllDay: request.isAllDay,
            location: request.location,
            calendarName: request.calendarName ?? "Default",
            notes: request.notes
        )
        createdEvents.append(event)
        mockEvents.append(event)
        return event
    }

    func deleteEvent(id: String) async throws {
        try await requestAccess()
        guard let index = mockEvents.firstIndex(where: { $0.id == id }) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        mockEvents.remove(at: index)
        deletedIds.append(id)
    }

    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        guard let index = mockEvents.firstIndex(where: { $0.id == request.eventId }) else {
            throw MacKitError.notFound("Event with id '\(request.eventId)'")
        }
        let existing = mockEvents[index]
        let updated = CalendarEvent(
            id: existing.id,
            title: request.title ?? existing.title,
            startDate: request.startDate ?? existing.startDate,
            endDate: request.endDate ?? existing.endDate,
            isAllDay: existing.isAllDay,
            location: request.location ?? existing.location,
            calendarName: existing.calendarName,
            notes: request.notes ?? existing.notes
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
}
