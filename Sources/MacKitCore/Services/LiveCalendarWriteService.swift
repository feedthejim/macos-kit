import EventKit
import Foundation

public final class LiveCalendarWriteService: CalendarWriteServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
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
        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = request.title
        ekEvent.startDate = request.startDate
        ekEvent.endDate = request.endDate
        ekEvent.isAllDay = request.isAllDay
        ekEvent.location = request.location
        ekEvent.notes = request.notes

        if let calendarName = request.calendarName {
            if let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) {
                ekEvent.calendar = calendar
            } else {
                throw MacKitError.notFound("Calendar '\(calendarName)'")
            }
        } else {
            ekEvent.calendar = store.defaultCalendarForNewEvents
        }

        try store.save(ekEvent, span: .thisEvent)
        return EventKitMapper.mapEvent(ekEvent)
    }

    public func deleteEvent(id: String) async throws {
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        try store.remove(ekEvent, span: .thisEvent)
    }

    public func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        guard let ekEvent = store.event(withIdentifier: request.eventId) else {
            throw MacKitError.notFound("Event with id '\(request.eventId)'")
        }

        if let title = request.title { ekEvent.title = title }
        if let startDate = request.startDate { ekEvent.startDate = startDate }
        if let endDate = request.endDate { ekEvent.endDate = endDate }
        if let location = request.location { ekEvent.location = location }
        if let notes = request.notes { ekEvent.notes = notes }

        try store.save(ekEvent, span: .thisEvent)
        return EventKitMapper.mapEvent(ekEvent)
    }

    public func findEvent(id: String) async throws -> CalendarEvent {
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        return EventKitMapper.mapEvent(ekEvent)
    }
}
