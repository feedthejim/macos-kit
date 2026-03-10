import Testing
import Foundation
@testable import MacKitCore

@Suite("FreeTimeSlots")
struct FreeTimeSlotsTests {
    private let calendar = Calendar.current

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

    @Test("Events 9-10, 10:30-11:30, 2-3 produce correct free slots")
    func standardDay() {
        let events = [
            event(from: 9, to: 10),
            event(from: 10, to: 11, startMinute: 30, endMinute: 30),
            event(from: 14, to: 15),
        ]

        let slots = FreeSlotCalculator.calculate(
            events: events, rangeStart: today(hour: 9), rangeEnd: today(hour: 17)
        )

        #expect(slots.count == 3)
        #expect(slots[0].durationMinutes == 30)   // 10:00-10:30
        #expect(slots[1].durationMinutes == 150)  // 11:30-14:00
        #expect(slots[2].durationMinutes == 120)  // 15:00-17:00
    }

    @Test("No events means entire range is free")
    func noEvents() {
        let slots = FreeSlotCalculator.calculate(
            events: [], rangeStart: today(hour: 9), rangeEnd: today(hour: 17)
        )
        #expect(slots.count == 1)
        #expect(slots[0].durationMinutes == 480)
    }

    @Test("Back-to-back events produce no gap")
    func backToBack() {
        let events = [event(from: 9, to: 10), event(from: 10, to: 11)]
        let slots = FreeSlotCalculator.calculate(
            events: events, rangeStart: today(hour: 9), rangeEnd: today(hour: 17)
        )
        #expect(slots.count == 1) // Only 11:00-17:00
        #expect(slots[0].durationMinutes == 360)
    }

    @Test("Overlapping events merge correctly")
    func overlapping() {
        let events = [
            event(from: 9, to: 10, endMinute: 30),
            event(from: 10, to: 11, endMinute: 30),
        ]
        let slots = FreeSlotCalculator.calculate(
            events: events, rangeStart: today(hour: 9), rangeEnd: today(hour: 17)
        )
        #expect(slots.count == 1) // 11:30-17:00
        #expect(slots[0].durationMinutes == 330)
    }

    @Test("Duration filter removes short slots")
    func durationFilter() {
        let events = [
            event(from: 9, to: 10),
            event(from: 10, to: 10, startMinute: 15, endMinute: 30),
            event(from: 14, to: 15),
        ]
        let slots = FreeSlotCalculator.calculate(
            events: events, rangeStart: today(hour: 9), rangeEnd: today(hour: 17),
            minDurationMinutes: 60
        )
        #expect(slots.count == 2) // 10:30-14:00 and 15:00-17:00
    }

    @Test("Events filling entire range produce no free slots")
    func fullyBooked() {
        let events = [event(from: 9, to: 13), event(from: 13, to: 17)]
        let slots = FreeSlotCalculator.calculate(
            events: events, rangeStart: today(hour: 9), rangeEnd: today(hour: 17)
        )
        #expect(slots.isEmpty)
    }

    @Test("All-day events are ignored")
    func allDayIgnored() {
        let allDay = CalendarEvent(
            id: "ad", title: "Holiday", startDate: today(hour: 0), endDate: today(hour: 23, minute: 59),
            isAllDay: true, calendarName: "Work"
        )
        let slots = FreeSlotCalculator.calculate(
            events: [allDay], rangeStart: today(hour: 9), rangeEnd: today(hour: 17)
        )
        #expect(slots.count == 1)
        #expect(slots[0].durationMinutes == 480)
    }

    @Test("parseDuration handles various formats")
    func parseDuration() {
        #expect(FreeSlotCalculator.parseDuration("30m") == 30)
        #expect(FreeSlotCalculator.parseDuration("1h") == 60)
        #expect(FreeSlotCalculator.parseDuration("90m") == 90)
        #expect(FreeSlotCalculator.parseDuration(nil) == 0)
        #expect(FreeSlotCalculator.parseDuration("2h") == 120)
    }
}
