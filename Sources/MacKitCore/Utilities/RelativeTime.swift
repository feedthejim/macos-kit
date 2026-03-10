import Foundation

public enum RelativeTime: Sendable {
    public static func format(_ date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        let totalMinutes = Int(seconds / 60)
        let absTotalMinutes = abs(totalMinutes)
        let isFuture = seconds >= 0

        // Within 1 minute of now
        if absTotalMinutes == 0 {
            return "now"
        }

        // 23-48 hours: "tomorrow" / "yesterday" (standalone, no prefix/suffix)
        if absTotalMinutes >= 23 * 60 && absTotalMinutes < 48 * 60 {
            return isFuture ? "tomorrow" : "yesterday"
        }

        // More than 48 hours: use days
        if absTotalMinutes >= 48 * 60 {
            let days = absTotalMinutes / (24 * 60)
            return isFuture ? "in \(days) days" : "\(days) days ago"
        }

        // Less than 23 hours: hours and minutes
        let formatted = formatDuration(minutes: absTotalMinutes)
        return isFuture ? "in \(formatted)" : "\(formatted) ago"
    }

    private static func formatDuration(minutes: Int) -> String {
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
}
