import Foundation

public enum EventStatus: String, Codable, Sendable {
    case confirmed
    case tentative
    case cancelled
    case none
}

public struct CalendarEvent: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "id", "title", "startDate", "endDate", "isAllDay", "location",
        "calendarName", "calendarColor", "status", "organizer", "notes",
        "url", "meetingURL",
    ]

    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let location: String?
    public let calendarName: String
    public let calendarColor: String?
    public let status: EventStatus
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
        calendarName: String = "",
        calendarColor: String? = nil,
        status: EventStatus = .confirmed,
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
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.status = status
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

        let timePadded = timeStr.padding(toLength: 10, withPad: " ", startingAt: 0)
        let titlePadded = title.padding(toLength: 30, withPad: " ", startingAt: 0)
        let durationPadded = duration.padding(toLength: 12, withPad: " ", startingAt: 0)
        let calPadded = calendarName.padding(toLength: 12, withPad: " ", startingAt: 0)

        return "\(timePadded)\(titlePadded)\(durationPadded)\(calPadded)\(relative)\(meetingIndicator)"
    }

    public var textDetail: String {
        var lines = [title]
        let timeRange = isAllDay ? "All day" : "\(startDate.formatted(date: .omitted, time: .shortened)) – \(endDate.formatted(date: .omitted, time: .shortened)) (\(RelativeTime.format(startDate)))"
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
