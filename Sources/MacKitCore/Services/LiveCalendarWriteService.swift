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

        if !request.attendeeEmails.isEmpty {
            // EKEvent does not support setting attendees directly via public API.
            // Attendees are managed by the calendar server.
        }

        try store.save(ekEvent, span: .thisEvent)
        return mapEvent(ekEvent)
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

        if let title = request.title {
            ekEvent.title = title
        }
        if let startDate = request.startDate {
            ekEvent.startDate = startDate
        }
        if let endDate = request.endDate {
            ekEvent.endDate = endDate
        }
        if let location = request.location {
            ekEvent.location = location
        }
        if let notes = request.notes {
            ekEvent.notes = notes
        }

        try store.save(ekEvent, span: .thisEvent)
        return mapEvent(ekEvent)
    }

    public func findEvent(id: String) async throws -> CalendarEvent {
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        return mapEvent(ekEvent)
    }

    private func mapEvent(_ ekEvent: EKEvent) -> CalendarEvent {
        let meetingURL = MeetingURLExtractor.extract(
            fromLocation: ekEvent.location,
            notes: ekEvent.notes,
            url: ekEvent.url?.absoluteString
        )

        let status: EventStatus
        switch ekEvent.status {
        case .confirmed: status = .confirmed
        case .tentative: status = .tentative
        case .canceled: status = .cancelled
        default: status = .none
        }

        return CalendarEvent(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "(No title)",
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            isAllDay: ekEvent.isAllDay,
            location: ekEvent.location,
            calendarName: ekEvent.calendar.title,
            calendarColor: ekEvent.calendar.cgColor.flatMap { hexColor(from: $0) },
            status: status,
            organizer: ekEvent.organizer?.name,
            notes: ekEvent.notes,
            url: ekEvent.url?.absoluteString,
            meetingURL: meetingURL
        )
    }

    private func hexColor(from cgColor: CGColor) -> String? {
        guard let components = cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
