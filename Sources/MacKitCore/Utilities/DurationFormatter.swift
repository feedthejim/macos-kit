import Foundation

public enum DurationFormatter: Sendable {
    public static func format(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let hourUnit = hours == 1 ? "hr" : "hrs"

        if remainingMinutes == 0 {
            return "\(hours) \(hourUnit)"
        }
        return "\(hours) \(hourUnit) \(remainingMinutes) min"
    }

    public static func format(seconds: TimeInterval) -> String {
        format(minutes: Int(seconds / 60))
    }

    public static func format(from start: Date, to end: Date) -> String {
        format(seconds: end.timeIntervalSince(start))
    }
}
