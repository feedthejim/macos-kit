import Foundation
@testable import MacKitCore

final class MockCalendarService: CalendarServiceProtocol, @unchecked Sendable {
    var mockCalendars: [CalendarInfo] = []
    var mockEvents: [CalendarEvent] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.calendars)
        }
    }

    func calendars() async throws -> [CalendarInfo] {
        try await requestAccess()
        return mockCalendars
    }

    func events(from startDate: Date, to endDate: Date, calendars: [String]?, limit: Int?) async throws -> [CalendarEvent] {
        try await requestAccess()
        let results = mockEvents
            .filter { $0.endDate > startDate && $0.startDate < endDate }
            .filter { event in
                guard let cals = calendars else { return true }
                return cals.contains(event.calendarName)
            }
            .sorted { $0.startDate < $1.startDate }
        guard let limit else { return results }
        return Array(results.prefix(max(0, limit)))
    }

    func currentEvent() async throws -> CalendarEvent? {
        try await requestAccess()
        let now = Date()
        return mockEvents.first { $0.startDate <= now && $0.endDate > now }
    }

    func nextEvent() async throws -> CalendarEvent? {
        try await requestAccess()
        let now = Date()
        return mockEvents
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }
}
