import EventKit
import Foundation

public final class LiveCalendarService: CalendarServiceProtocol, @unchecked Sendable {
    private static let permissionTimeoutSeconds = 30
    private static let maximumQueryInterval: TimeInterval = 366 * 24 * 60 * 60
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

    public func calendars() async throws -> [CalendarInfo] {
        store.calendars(for: .event).map { cal in
            CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                source: cal.source.title,
                color: cal.cgColor.flatMap { EventKitMapper.hexColor(from: $0) },
                isSubscribed: cal.isSubscribed,
                isWritable: cal.allowsContentModifications
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func events(from startDate: Date, to endDate: Date, calendars: [String]?, limit: Int?) async throws -> [CalendarEvent] {
        guard endDate > startDate else {
            throw MacKitError.systemError("Calendar range must end after it starts.")
        }
        guard endDate.timeIntervalSince(startDate) <= Self.maximumQueryInterval else {
            throw MacKitError.systemError(
                "Calendar ranges are limited to 366 days. Split larger queries into smaller ranges."
            )
        }
        if let limit, limit <= 0 { return [] }

        let ekCalendars: [EKCalendar]?
        if let calendars {
            let available = store.calendars(for: .event)
            var selected: [EKCalendar] = []
            for reference in calendars {
                if let byIdentifier = available.first(where: { $0.calendarIdentifier == reference }) {
                    selected.append(byIdentifier)
                    continue
                }
                let byTitle = available.filter { $0.title == reference }
                guard !byTitle.isEmpty else {
                    throw MacKitError.notFound("Calendar '\(reference)'")
                }
                guard byTitle.count == 1 else {
                    throw MacKitError.systemError(
                        "More than one calendar is named '\(reference)'. Use a calendar ID from 'mackit cal calendars --format json'."
                    )
                }
                selected.append(byTitle[0])
            }
            ekCalendars = selected
        } else {
            ekCalendars = nil
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: ekCalendars)
        let sorted = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        let selected = limit.map { sorted.prefix($0) } ?? sorted.prefix(sorted.count)
        return selected.map { EventKitMapper.mapEvent($0) }
    }

    public func currentEvent() async throws -> CalendarEvent? {
        let now = Date()
        let events = try await events(
            from: now,
            to: now.addingTimeInterval(1),
            calendars: nil,
            limit: 1
        )
        return events.first { $0.startDate <= now && $0.endDate > now }
    }

    public func nextEvent() async throws -> CalendarEvent? {
        let now = Date()
        for days in [7, 30, 366] {
            let events = try await events(
                from: now,
                to: Calendar.current.date(byAdding: .day, value: days, to: now)!,
                calendars: nil,
                limit: 1
            )
            if let event = events.first { return event }
        }
        return nil
    }
}
