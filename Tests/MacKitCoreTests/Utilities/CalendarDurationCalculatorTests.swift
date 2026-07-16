import Foundation
import Testing
@testable import MacKitCore

@Suite("CalendarDurationCalculator")
struct CalendarDurationCalculatorTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(
        id: String,
        startMinutes: Int,
        endMinutes: Int,
        status: EventStatus = .confirmed,
        availability: EventAvailability = .busy
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, title: id,
            startDate: base.addingTimeInterval(TimeInterval(startMinutes * 60)),
            endDate: base.addingTimeInterval(TimeInterval(endMinutes * 60)),
            calendarName: "Work", status: status, availability: availability
        )
    }

    @Test("Overlapping meetings are counted once")
    func mergesOverlaps() {
        let minutes = CalendarDurationCalculator.busyMinutes(events: [
            event(id: "a", startMinutes: 0, endMinutes: 60),
            event(id: "b", startMinutes: 30, endMinutes: 90),
        ])
        #expect(minutes == 90)
    }

    @Test("Cancelled and free events are excluded")
    func excludesNonBlockingEvents() {
        let minutes = CalendarDurationCalculator.busyMinutes(events: [
            event(id: "cancelled", startMinutes: 0, endMinutes: 60, status: .cancelled),
            event(id: "free", startMinutes: 60, endMinutes: 120, availability: .free),
        ])
        #expect(minutes == 0)
    }

    @Test("Intervals are clamped to the requested range")
    func clampsRange() {
        let minutes = CalendarDurationCalculator.busyMinutes(
            events: [event(id: "long", startMinutes: 0, endMinutes: 180)],
            rangeStart: base.addingTimeInterval(60 * 60),
            rangeEnd: base.addingTimeInterval(120 * 60)
        )
        #expect(minutes == 60)
    }
}
