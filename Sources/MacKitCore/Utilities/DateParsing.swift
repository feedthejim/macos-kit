import Foundation

public enum DateParsing: Sendable {
    private static let calendar = Calendar.current

    private static let dayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    public static func parse(_ input: String) throws -> Date {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        guard !trimmed.isEmpty else {
            throw MacKitError.invalidDateFormat(input)
        }

        // Natural language keywords
        switch trimmed {
        case "today":
            return calendar.startOfDay(for: Date())
        case "tomorrow":
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        case "yesterday":
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        case "next week":
            return nextWeekday(2) // Monday of next week
        default:
            break
        }

        // "next <day>" pattern
        if trimmed.hasPrefix("next ") {
            let dayPart = String(trimmed.dropFirst(5))
            if let targetWeekday = dayNames[dayPart] {
                return nextWeekday(targetWeekday)
            }
        }

        // Day name alone (next occurrence, including today)
        if let targetWeekday = dayNames[trimmed] {
            return nextWeekday(targetWeekday, includeToday: true)
        }

        // ISO 8601 datetime: YYYY-MM-DDTHH:MM
        if trimmed.contains("t") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let date = formatter.date(from: trimmed.uppercased()) {
                return date
            }
        }

        // ISO 8601 date: YYYY-MM-DD
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: trimmed) {
            return date
        }

        throw MacKitError.invalidDateFormat(input)
    }

    /// Parses a time string like "3pm", "14:30", "9:30am" to today at that time.
    public static func parseTime(_ input: String) throws -> Date {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        guard !trimmed.isEmpty else {
            throw MacKitError.invalidDateFormat(input)
        }

        let hour: Int
        let minute: Int

        if let match = trimmed.wholeMatch(of: /(\d{1,2}):(\d{2})\s*(am|pm)?/) {
            // Formats: "14:30", "9:30am", "2:30pm"
            guard let h = Int(match.1), let m = Int(match.2) else {
                throw MacKitError.invalidDateFormat(input)
            }
            if let period = match.3 {
                guard h >= 1 && h <= 12 && m >= 0 && m <= 59 else {
                    throw MacKitError.invalidDateFormat(input)
                }
                if period == "am" {
                    hour = h == 12 ? 0 : h
                } else {
                    hour = h == 12 ? 12 : h + 12
                }
            } else {
                // 24-hour format
                guard h >= 0 && h <= 23 && m >= 0 && m <= 59 else {
                    throw MacKitError.invalidDateFormat(input)
                }
                hour = h
            }
            minute = m
        } else if let match = trimmed.wholeMatch(of: /(\d{1,2})\s*(am|pm)/) {
            // Formats: "3pm", "12am"
            guard let h = Int(match.1), h >= 1 && h <= 12 else {
                throw MacKitError.invalidDateFormat(input)
            }
            let period = match.2
            if period == "am" {
                hour = h == 12 ? 0 : h
            } else {
                hour = h == 12 ? 12 : h + 12
            }
            minute = 0
        } else {
            throw MacKitError.invalidDateFormat(input)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let date = calendar.date(from: components) else {
            throw MacKitError.invalidDateFormat(input)
        }
        return date
    }

    /// Combines a date string (parsed via `parse`) with a time string (parsed via `parseTime`).
    public static func parseDateTime(_ dateStr: String, time timeStr: String) throws -> Date {
        let dateOnly = try parse(dateStr)
        let timeOnly = try parseTime(timeStr)

        let dateComponents = calendar.dateComponents([.year, .month, .day], from: dateOnly)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeOnly)

        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second

        guard let date = calendar.date(from: combined) else {
            throw MacKitError.invalidDateFormat("\(dateStr) \(timeStr)")
        }
        return date
    }

    private static func nextWeekday(_ target: Int, includeToday: Bool = false) -> Date {
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today)

        var daysToAdd: Int
        if includeToday && todayWeekday == target {
            daysToAdd = 0
        } else {
            daysToAdd = (target - todayWeekday + 7) % 7
            if daysToAdd == 0 { daysToAdd = 7 }
        }

        let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: today)!
        return calendar.startOfDay(for: targetDate)
    }
}
