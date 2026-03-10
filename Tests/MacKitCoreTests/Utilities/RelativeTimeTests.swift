import Testing
import Foundation
@testable import MacKitCore

@Suite("RelativeTime")
struct RelativeTimeTests {
    // Use a fixed reference point to avoid timing issues between Date() calls
    private let now = Date()

    private func date(minutesFromNow minutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    @Test("5 minutes from now")
    func fiveMinutes() {
        let result = RelativeTime.format(date(minutesFromNow: 5), relativeTo: now)
        #expect(result == "in 5 min")
    }

    @Test("30 minutes from now")
    func thirtyMinutes() {
        let result = RelativeTime.format(date(minutesFromNow: 30), relativeTo: now)
        #expect(result == "in 30 min")
    }

    @Test("90 minutes from now")
    func ninetyMinutes() {
        let result = RelativeTime.format(date(minutesFromNow: 90), relativeTo: now)
        #expect(result == "in 1 hr 30 min")
    }

    @Test("3 hours from now")
    func threeHours() {
        let result = RelativeTime.format(date(minutesFromNow: 180), relativeTo: now)
        #expect(result == "in 3 hrs")
    }

    @Test("10 minutes ago")
    func tenMinutesAgo() {
        let result = RelativeTime.format(date(minutesFromNow: -10), relativeTo: now)
        #expect(result == "10 min ago")
    }

    @Test("1 minute from now")
    func oneMinute() {
        let result = RelativeTime.format(date(minutesFromNow: 1), relativeTo: now)
        #expect(result == "in 1 min")
    }

    @Test("Now (0 minutes)")
    func nowTest() {
        let result = RelativeTime.format(now, relativeTo: now)
        #expect(result == "now")
    }

    @Test("25 hours from now shows 'tomorrow'")
    func tomorrow() {
        let result = RelativeTime.format(date(minutesFromNow: 25 * 60), relativeTo: now)
        #expect(result == "tomorrow")
    }

    @Test("3 days from now")
    func threeDays() {
        let result = RelativeTime.format(date(minutesFromNow: 3 * 24 * 60), relativeTo: now)
        #expect(result == "in 3 days")
    }

    @Test("1 hour exactly")
    func oneHourExactly() {
        let result = RelativeTime.format(date(minutesFromNow: 60), relativeTo: now)
        #expect(result == "in 1 hr")
    }

    @Test("2 hours exactly")
    func twoHoursExactly() {
        let result = RelativeTime.format(date(minutesFromNow: 120), relativeTo: now)
        #expect(result == "in 2 hrs")
    }

    @Test("1 day ago")
    func oneDayAgo() {
        let result = RelativeTime.format(date(minutesFromNow: -24 * 60), relativeTo: now)
        #expect(result == "yesterday")
    }
}
