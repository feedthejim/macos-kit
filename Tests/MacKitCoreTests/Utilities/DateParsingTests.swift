import Testing
import Foundation
@testable import MacKitCore

@Suite("DateParsing")
struct DateParsingTests {
    private let calendar = Calendar.current

    @Test("Parses 'today' to start of today")
    func parsesToday() throws {
        let result = try DateParsing.parse("today")
        let expected = calendar.startOfDay(for: Date())
        #expect(result == expected)
    }

    @Test("Parses 'tomorrow' to start of tomorrow")
    func parsesTomorrow() throws {
        let result = try DateParsing.parse("tomorrow")
        let expected = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        #expect(result == expected)
    }

    @Test("Parses 'yesterday' to start of yesterday")
    func parsesYesterday() throws {
        let result = try DateParsing.parse("yesterday")
        let expected = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        #expect(result == expected)
    }

    @Test("Parses ISO 8601 date")
    func parsesISO8601Date() throws {
        let result = try DateParsing.parse("2026-03-15")
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("Parses ISO 8601 datetime")
    func parsesISO8601DateTime() throws {
        let result = try DateParsing.parse("2026-03-15T14:30")
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 15)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test("Parses day name to next occurrence")
    func parsesDayName() throws {
        let result = try DateParsing.parse("monday")
        let weekday = calendar.component(.weekday, from: result)
        #expect(weekday == 2) // Monday = 2 in Calendar
        #expect(result >= calendar.startOfDay(for: Date()))
    }

    @Test("Parses 'next monday'")
    func parsesNextDayName() throws {
        let result = try DateParsing.parse("next monday")
        let weekday = calendar.component(.weekday, from: result)
        #expect(weekday == 2)
        #expect(result > Date())
    }

    @Test("Parses 'next week' to monday of next week")
    func parsesNextWeek() throws {
        let result = try DateParsing.parse("next week")
        let weekday = calendar.component(.weekday, from: result)
        #expect(weekday == 2) // Monday
        #expect(result > Date())
    }

    @Test("Throws on garbage input")
    func throwsOnGarbage() {
        #expect(throws: MacKitError.self) {
            try DateParsing.parse("garbage")
        }
    }

    @Test("Throws on empty input")
    func throwsOnEmpty() {
        #expect(throws: MacKitError.self) {
            try DateParsing.parse("")
        }
    }

    @Test("Case insensitive")
    func caseInsensitive() throws {
        let result = try DateParsing.parse("TODAY")
        let expected = calendar.startOfDay(for: Date())
        #expect(result == expected)
    }

    @Test("Parses 'friday'")
    func parsesFriday() throws {
        let result = try DateParsing.parse("friday")
        let weekday = calendar.component(.weekday, from: result)
        #expect(weekday == 6) // Friday = 6
    }

    // MARK: - parseTime tests

    @Test("Parses '3pm' to hour 15, minute 0")
    func parsesTime3pm() throws {
        let result = try DateParsing.parseTime("3pm")
        let components = calendar.dateComponents([.hour, .minute], from: result)
        #expect(components.hour == 15)
        #expect(components.minute == 0)
    }

    @Test("Parses '14:30' to hour 14, minute 30")
    func parsesTime1430() throws {
        let result = try DateParsing.parseTime("14:30")
        let components = calendar.dateComponents([.hour, .minute], from: result)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test("Parses '9:30am' to hour 9, minute 30")
    func parsesTime930am() throws {
        let result = try DateParsing.parseTime("9:30am")
        let components = calendar.dateComponents([.hour, .minute], from: result)
        #expect(components.hour == 9)
        #expect(components.minute == 30)
    }

    @Test("Parses '12pm' to hour 12 (noon)")
    func parsesTime12pm() throws {
        let result = try DateParsing.parseTime("12pm")
        let components = calendar.dateComponents([.hour, .minute], from: result)
        #expect(components.hour == 12)
        #expect(components.minute == 0)
    }

    @Test("Parses '12am' to hour 0 (midnight)")
    func parsesTime12am() throws {
        let result = try DateParsing.parseTime("12am")
        let components = calendar.dateComponents([.hour, .minute], from: result)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test("parseDateTime combines 'tomorrow' and '3pm'")
    func parsesDateTimeTomorrow3pm() throws {
        let result = try DateParsing.parseDateTime("tomorrow", time: "3pm")
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)

        let expectedDate = calendar.date(byAdding: .day, value: 1, to: Date())!
        let expectedComponents = calendar.dateComponents([.year, .month, .day], from: expectedDate)

        #expect(components.year == expectedComponents.year)
        #expect(components.month == expectedComponents.month)
        #expect(components.day == expectedComponents.day)
        #expect(components.hour == 15)
        #expect(components.minute == 0)
    }

    @Test("parseTime throws on invalid time")
    func parseTimeThrowsOnInvalid() {
        #expect(throws: MacKitError.self) {
            try DateParsing.parseTime("not-a-time")
        }
    }
}
