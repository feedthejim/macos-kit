import Foundation

public struct CreateEventRequest: Sendable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarName: String?
    public let location: String?
    public let notes: String?
    public let attendeeEmails: [String]
    public let isAllDay: Bool

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        calendarName: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        attendeeEmails: [String] = [],
        isAllDay: Bool = false
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
        self.location = location
        self.notes = notes
        self.attendeeEmails = attendeeEmails
        self.isAllDay = isAllDay
    }
}

public struct UpdateEventRequest: Sendable {
    public let eventId: String
    public let title: String?
    public let startDate: Date?
    public let endDate: Date?
    public let location: String?
    public let notes: String?

    public init(
        eventId: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.eventId = eventId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
    }
}

public protocol CalendarWriteServiceProtocol: Sendable {
    func requestAccess() async throws
    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent
    func deleteEvent(id: String) async throws
    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent
    func findEvent(id: String) async throws -> CalendarEvent
}
