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
