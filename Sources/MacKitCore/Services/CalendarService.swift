import Foundation

public protocol CalendarServiceProtocol: Sendable {
    func requestAccess() async throws
    func calendars() async throws -> [CalendarInfo]
    func events(from startDate: Date, to endDate: Date, calendars: [String]?) async throws -> [CalendarEvent]
    func currentEvent() async throws -> CalendarEvent?
    func nextEvent() async throws -> CalendarEvent?
}
