import Foundation

public enum EventStatus: String, Codable, Sendable {
    case confirmed
    case tentative
    case cancelled
    case none
}

public enum EventAvailability: String, Codable, Sendable {
    case busy
    case free
    case tentative
    case unavailable
    case notSupported
}

public enum EventParticipationStatus: String, Codable, Sendable {
    case unknown
    case pending
    case accepted
    case declined
    case tentative
    case delegated
    case completed
    case inProcess
}

public struct CalendarAttendee: Codable, Sendable, Equatable {
    public let name: String?
    public let email: String?
    public let status: EventParticipationStatus
    public let isCurrentUser: Bool

    public init(
        name: String? = nil,
        email: String? = nil,
        status: EventParticipationStatus = .unknown,
        isCurrentUser: Bool = false
    ) {
        self.name = name
        self.email = email
        self.status = status
        self.isCurrentUser = isCurrentUser
    }
}

public struct CalendarEvent: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "id", "title", "startDate", "endDate", "isAllDay", "location",
        "calendarId", "calendarName", "calendarColor", "status", "availability",
        "isRecurring", "attendees", "organizer", "notes", "url", "meetingURL",
    ]

    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let location: String?
    public let calendarId: String
    public let calendarName: String
    public let calendarColor: String?
    public let status: EventStatus
    public let availability: EventAvailability
    public let isRecurring: Bool
    public let attendees: [CalendarAttendee]
    public let organizer: String?
    public let notes: String?
    public let url: String?
    public let meetingURL: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        calendarId: String = "",
        calendarName: String = "",
        calendarColor: String? = nil,
        status: EventStatus = .confirmed,
        availability: EventAvailability = .busy,
        isRecurring: Bool = false,
        attendees: [CalendarAttendee] = [],
        organizer: String? = nil,
        notes: String? = nil,
        url: String? = nil,
        meetingURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.calendarId = calendarId
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.status = status
        self.availability = availability
        self.isRecurring = isRecurring
        self.attendees = attendees
        self.organizer = organizer
        self.notes = notes
        self.url = url
        self.meetingURL = meetingURL
    }
}

// MARK: - TextRepresentable

extension CalendarEvent: TextRepresentable {
    public var textSummary: String {
        let timeStr: String
        if isAllDay {
            timeStr = "All day"
        } else {
            timeStr = startDate.formatted(date: .omitted, time: .shortened)
        }

        let duration = isAllDay ? "" : DurationFormatter.format(from: startDate, to: endDate)
        let relative = RelativeTime.format(startDate)
        let meetingIndicator = meetingURL != nil ? "  \(shortenURL(meetingURL!))" : ""

        let timePadded = column(timeStr, width: 10)
        let titlePadded = column(title, width: 30)
        let durationPadded = column(duration, width: 12)
        let calPadded = column(calendarName, width: 12)

        return "\(timePadded)\(titlePadded)\(durationPadded)\(calPadded)\(relative)\(meetingIndicator)"
    }

    public var textDetail: String {
        var lines = [title]
        let date = startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let timeRange = isAllDay
            ? "\(date), all day"
            : "\(date), \(startDate.formatted(date: .omitted, time: .shortened)) – \(endDate.formatted(date: .omitted, time: .shortened)) (\(RelativeTime.format(startDate)))"
        lines.append("  Time:      \(timeRange)")
        lines.append("  Calendar:  \(calendarName)")
        if let location { lines.append("  Location:  \(location)") }
        if let meetingURL { lines.append("  Meeting:   \(meetingURL)") }
        if let organizer { lines.append("  Organizer: \(organizer)") }
        if let notes, !notes.isEmpty { lines.append("  Notes:     \(notes.prefix(200))") }
        return lines.joined(separator: "\n")
    }

    private func shortenURL(_ url: String) -> String {
        // Show just the domain for compact display
        if let parsed = URL(string: url), let host = parsed.host {
            return host
        }
        return url
    }

    private func column(_ value: String, width: Int) -> String {
        let truncated = value.count > width ? String(value.prefix(max(0, width - 1))) + "…" : value
        return truncated.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

// MARK: - TableRepresentable

extension CalendarEvent: TableRepresentable {
    public static var tableHeaders: [String] {
        ["Time", "Title", "Duration", "Calendar"]
    }

    public var tableRow: [String] {
        let time = isAllDay ? "All day" : startDate.formatted(date: .omitted, time: .shortened)
        let duration = isAllDay ? "-" : DurationFormatter.format(from: startDate, to: endDate)
        return [time, title, duration, calendarName]
    }
}
