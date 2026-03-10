import EventKit
import Foundation

/// Shared mapping utilities for converting EventKit types to MacKitCore models.
/// Used by both LiveCalendarService and LiveCalendarWriteService.
enum EventKitMapper {
    static func mapEvent(_ ekEvent: EKEvent) -> CalendarEvent {
        let meetingURL = MeetingURLExtractor.extract(
            fromLocation: ekEvent.location,
            notes: ekEvent.notes,
            url: ekEvent.url?.absoluteString
        )

        let status: EventStatus = switch ekEvent.status {
        case .confirmed: .confirmed
        case .tentative: .tentative
        case .canceled: .cancelled
        default: .none
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

    static func hexColor(from cgColor: CGColor) -> String? {
        guard let components = cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
