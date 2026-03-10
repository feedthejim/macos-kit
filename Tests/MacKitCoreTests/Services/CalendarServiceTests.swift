import Testing
import Foundation
@testable import MacKitCore

@Suite("CalendarService")
struct CalendarServiceTests {
    private let now = Date()

    private func event(
        title: String,
        minutesFromNow: Int,
        durationMinutes: Int = 30,
        calendar: String = "Work",
        meetingURL: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: title,
            startDate: now.addingTimeInterval(TimeInterval(minutesFromNow * 60)),
            endDate: now.addingTimeInterval(TimeInterval((minutesFromNow + durationMinutes) * 60)),
            calendarName: calendar,
            meetingURL: meetingURL
        )
    }

    // MARK: - events(from:to:calendars:)

    @Test("Returns events within date range sorted by start time")
    func eventsInRange() async throws {
        let mock = MockCalendarService()
        mock.mockEvents = [
            event(title: "C", minutesFromNow: 180),
            event(title: "A", minutesFromNow: 60),
            event(title: "B", minutesFromNow: 120),
        ]

        let start = now.addingTimeInterval(50 * 60)
        let end = now.addingTimeInterval(150 * 60)
        let events = try await mock.events(from: start, to: end, calendars: nil)

        #expect(events.count == 2)
        #expect(events[0].title == "A")
        #expect(events[1].title == "B")
    }

    @Test("Returns empty array when no events in range")
    func noEventsInRange() async throws {
        let mock = MockCalendarService()
        mock.mockEvents = [event(title: "Far away", minutesFromNow: 10000)]

        let events = try await mock.events(
            from: now,
            to: now.addingTimeInterval(60),
            calendars: nil
        )
        #expect(events.isEmpty)
    }

    @Test("Filters by calendar name")
    func filterByCalendar() async throws {
        let mock = MockCalendarService()
        mock.mockEvents = [
            event(title: "Work meeting", minutesFromNow: 60, calendar: "Work"),
            event(title: "Lunch", minutesFromNow: 120, calendar: "Personal"),
            event(title: "Standup", minutesFromNow: 180, calendar: "Work"),
        ]

        let start = now
        let end = now.addingTimeInterval(300 * 60)
        let events = try await mock.events(from: start, to: end, calendars: ["Work"])

        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.calendarName == "Work" })
    }

    @Test("Filters by multiple calendars (union)")
    func filterByMultipleCalendars() async throws {
        let mock = MockCalendarService()
        mock.mockEvents = [
            event(title: "A", minutesFromNow: 60, calendar: "Work"),
            event(title: "B", minutesFromNow: 120, calendar: "Personal"),
            event(title: "C", minutesFromNow: 180, calendar: "Other"),
        ]

        let events = try await mock.events(
            from: now,
            to: now.addingTimeInterval(300 * 60),
            calendars: ["Work", "Personal"]
        )
        #expect(events.count == 2)
    }

    // MARK: - nextEvent()

    @Test("Returns soonest future event")
    func nextEventReturnsSoonest() async throws {
        let mock = MockCalendarService()
        mock.mockEvents = [
            event(title: "Later", minutesFromNow: 120),
            event(title: "Soonest", minutesFromNow: 30),
            event(title: "Latest", minutesFromNow: 240),
        ]

        let next = try await mock.nextEvent()
        #expect(next?.title == "Soonest")
    }

    @Test("Returns nil when no future events")
    func nextEventNil() async throws {
        let mock = MockCalendarService()
        mock.mockEvents = [event(title: "Past", minutesFromNow: -120, durationMinutes: 30)]

        let next = try await mock.nextEvent()
        #expect(next == nil)
    }

    // MARK: - Permission handling

    @Test("Permission denied throws correct error")
    func permissionDenied() async {
        let mock = MockCalendarService()
        mock.shouldDenyPermission = true

        await #expect(throws: MacKitError.self) {
            try await mock.events(from: Date(), to: Date(), calendars: nil)
        }
    }

    @Test("Permission denied on nextEvent")
    func permissionDeniedNextEvent() async {
        let mock = MockCalendarService()
        mock.shouldDenyPermission = true

        await #expect(throws: MacKitError.self) {
            try await mock.nextEvent()
        }
    }
}
