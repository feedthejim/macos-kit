import Foundation

public enum EventMutationScope: String, Codable, Sendable {
    case thisEvent
    case futureEvents
}

public enum EventTextUpdate: Sendable, Equatable {
    case unchanged
    case set(String)
    case clear
}

public struct CreateEventRequest: Sendable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarName: String?
    public let location: String?
    public let notes: String?
    public let isAllDay: Bool

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        calendarName: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
    }
}

public struct UpdateEventRequest: Sendable {
    public let eventId: String
    public let title: String?
    public let startDate: Date?
    public let endDate: Date?
    public let location: EventTextUpdate
    public let notes: EventTextUpdate
    public let calendarName: String?
    public let isAllDay: Bool?
    public let scope: EventMutationScope

    public init(
        eventId: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        clearLocation: Bool = false,
        clearNotes: Bool = false,
        calendarName: String? = nil,
        isAllDay: Bool? = nil,
        scope: EventMutationScope = .thisEvent
    ) {
        self.eventId = eventId
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = clearLocation ? .clear : location.map(EventTextUpdate.set) ?? .unchanged
        self.notes = clearNotes ? .clear : notes.map(EventTextUpdate.set) ?? .unchanged
        self.calendarName = calendarName
        self.isAllDay = isAllDay
        self.scope = scope
    }
}

public protocol CalendarWriteServiceProtocol: Sendable {
    func requestAccess() async throws
    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent
    func deleteEvent(id: String, scope: EventMutationScope) async throws
    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent
    func findEvent(id: String) async throws -> CalendarEvent
}

public extension CalendarWriteServiceProtocol {
    func deleteEvent(id: String) async throws {
        try await deleteEvent(id: id, scope: .thisEvent)
    }
}
