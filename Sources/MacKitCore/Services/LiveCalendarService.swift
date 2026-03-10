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
                color: cal.cgColor.flatMap { EventKitMapper.hexColor(from: $0) },
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

        return ekEvents.map { EventKitMapper.mapEvent($0) }
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
}
