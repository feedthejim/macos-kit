import Testing
import Foundation
@testable import MacKitCore

@Suite("DurationFormatter")
struct DurationFormatterTests {
    @Test("15 minutes")
    func fifteenMinutes() {
        #expect(DurationFormatter.format(minutes: 15) == "15 min")
    }

    @Test("30 minutes")
    func thirtyMinutes() {
        #expect(DurationFormatter.format(minutes: 30) == "30 min")
    }

    @Test("60 minutes shows 1 hr")
    func sixtyMinutes() {
        #expect(DurationFormatter.format(minutes: 60) == "1 hr")
    }

    @Test("90 minutes")
    func ninetyMinutes() {
        #expect(DurationFormatter.format(minutes: 90) == "1 hr 30 min")
    }

    @Test("120 minutes shows 2 hrs")
    func twoHours() {
        #expect(DurationFormatter.format(minutes: 120) == "2 hrs")
    }

    @Test("0 minutes")
    func zeroMinutes() {
        #expect(DurationFormatter.format(minutes: 0) == "0 min")
    }

    @Test("1 minute")
    func oneMinute() {
        #expect(DurationFormatter.format(minutes: 1) == "1 min")
    }

    @Test("480 minutes shows 8 hrs")
    func eightHours() {
        #expect(DurationFormatter.format(minutes: 480) == "8 hrs")
    }

    @Test("Format from TimeInterval")
    func fromTimeInterval() {
        #expect(DurationFormatter.format(seconds: 5400) == "1 hr 30 min")
    }

    @Test("Format from two dates")
    func fromDates() {
        let start = Date()
        let end = start.addingTimeInterval(2700) // 45 min
        #expect(DurationFormatter.format(from: start, to: end) == "45 min")
    }
}
