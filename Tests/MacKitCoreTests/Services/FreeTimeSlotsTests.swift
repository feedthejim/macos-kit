import Testing
import Foundation
@testable import MacKitCore

@Suite("FreeTimeSlots")
struct FreeTimeSlotsTests {
    private let calendar = Calendar.current

    // Create a date at a specific hour today
    private func today(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    private func event(from startHour: Int, to endHour: Int, startMinute: Int = 0, endMinute: Int = 0) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString,
            title: "Meeting",
            startDate: today(hour: startHour, minute: startMinute),
            endDate: today(hour: endHour, minute: endMinute),
            calendarName: "Work"
        )
    }

    // Reuse the free slot calculation from CalendarCommand
    private func calculateFreeSlots(events: [CalendarEvent], rangeStart: Date, rangeEnd: Date) -> [(start: Date, end: Date, duration: Int)] {
        var slots: [(start: Date, end: Date, duration: Int)] = []
        var cursor = rangeStart

        let sorted = events.sorted { $0.startDate < $1.startDate }
        for e in sorted {
            let eventStart = max(e.startDate, rangeStart)
            let eventEnd = min(e.endDate, rangeEnd)

            if eventStart > cursor {
                let duration = Int(eventStart.timeIntervalSince(cursor) / 60)
                slots.append((start: cursor, end: eventStart, duration: duration))
            }
            cursor = max(cursor, eventEnd)
        }

        if cursor < rangeEnd {
            let duration = Int(rangeEnd.timeIntervalSince(cursor) / 60)
            slots.append((start: cursor, end: rangeEnd, duration: duration))
        }

        return slots
    }

    @Test("Events 9-10, 10:30-11:30, 2-3 produce correct free slots")
    func standardDay() {
        let events = [
            event(from: 9, to: 10),
            event(from: 10, to: 11, startMinute: 30, endMinute: 30),
            event(from: 14, to: 15),
        ]

        let slots = calculateFreeSlots(
            events: events,
            rangeStart: today(hour: 9),
            rangeEnd: today(hour: 17)
        )

        #expect(slots.count == 3)
        // 10:00-10:30
        #expect(slots[0].duration == 30)
        // 11:30-14:00
        #expect(slots[1].duration == 150)
        // 15:00-17:00
        #expect(slots[2].duration == 120)
    }

    @Test("No events means entire range is free")
    func noEvents() {
        let slots = calculateFreeSlots(
            events: [],
            rangeStart: today(hour: 9),
            rangeEnd: today(hour: 17)
        )

        #expect(slots.count == 1)
        #expect(slots[0].duration == 480) // 8 hours
    }

    @Test("Back-to-back events produce no gap")
    func backToBack() {
        let events = [
            event(from: 9, to: 10),
            event(from: 10, to: 11),
        ]

        let slots = calculateFreeSlots(
            events: events,
            rangeStart: today(hour: 9),
            rangeEnd: today(hour: 17)
        )

        #expect(slots.count == 1) // Only 11:00-17:00
        #expect(slots[0].duration == 360)
    }

    @Test("Overlapping events merge correctly")
    func overlapping() {
        let events = [
            event(from: 9, to: 10, endMinute: 30),
            event(from: 10, to: 11, endMinute: 30),
        ]

        let slots = calculateFreeSlots(
            events: events,
            rangeStart: today(hour: 9),
            rangeEnd: today(hour: 17)
        )

        #expect(slots.count == 1) // 11:30-17:00
        #expect(slots[0].duration == 330) // 5.5 hours
    }

    @Test("Duration filter removes short slots")
    func durationFilter() {
        let events = [
            event(from: 9, to: 10),
            event(from: 10, to: 10, startMinute: 15, endMinute: 30), // 15 min gap at 10:00
            event(from: 14, to: 15),
        ]

        let slots = calculateFreeSlots(
            events: events,
            rangeStart: today(hour: 9),
            rangeEnd: today(hour: 17)
        )

        let filtered = slots.filter { $0.duration >= 60 } // >= 1 hour
        #expect(filtered.count == 2) // 10:30-14:00 and 15:00-17:00
    }

    @Test("Events filling entire range produce no free slots")
    func fullyBooked() {
        let events = [
            event(from: 9, to: 13),
            event(from: 13, to: 17),
        ]

        let slots = calculateFreeSlots(
            events: events,
            rangeStart: today(hour: 9),
            rangeEnd: today(hour: 17)
        )

        #expect(slots.isEmpty)
    }
}
