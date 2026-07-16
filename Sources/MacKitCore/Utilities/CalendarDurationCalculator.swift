import Foundation

public enum CalendarDurationCalculator: Sendable {
    public static func busyMinutes(
        events: [CalendarEvent],
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil
    ) -> Int {
        let intervals = events
            .filter {
                !$0.isAllDay && $0.status != .cancelled && $0.availability != .free
            }
            .compactMap { event -> (Date, Date)? in
                let start = rangeStart.map { max(event.startDate, $0) } ?? event.startDate
                let end = rangeEnd.map { min(event.endDate, $0) } ?? event.endDate
                return end > start ? (start, end) : nil
            }
            .sorted { $0.0 < $1.0 }

        guard var current = intervals.first else { return 0 }
        var seconds: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                seconds += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        seconds += current.1.timeIntervalSince(current.0)
        return Int(seconds / 60)
    }
}
