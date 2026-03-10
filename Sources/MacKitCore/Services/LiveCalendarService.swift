import EventKit
import Foundation

public final class LiveCalendarService: CalendarServiceProtocol, @unchecked Sendable {
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

    public func calendars() async throws -> [CalendarInfo] {
        store.calendars(for: .event).map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                source: cal.source.title,
                color: cal.cgColor.flatMap { hexColor(from: $0) },
                isSubscribed: cal.isSubscribed
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func events(from startDate: Date, to endDate: Date, calendars: [String]?) async throws -> [CalendarEvent] {
        let ekCalendars: [EKCalendar]?
        if let calendars {
            ekCalendars = store.calendars(for: .event).filter { calendars.contains($0.title) }
        } else {
            ekCalendars = nil
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: ekCalendars)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { mapEvent($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    public func currentEvent() async throws -> CalendarEvent? {
        let now = Date()
        let events = try await events(
            from: now.addingTimeInterval(-12 * 3600),
            to: now.addingTimeInterval(1),
            calendars: nil
        )
        return events.first { $0.startDate <= now && $0.endDate > now }
    }

    public func nextEvent() async throws -> CalendarEvent? {
        let now = Date()
        let events = try await events(
            from: now,
            to: now.addingTimeInterval(7 * 24 * 3600),
            calendars: nil
        )
        return events.first { $0.startDate >= now || ($0.startDate <= now && $0.endDate > now) }
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
