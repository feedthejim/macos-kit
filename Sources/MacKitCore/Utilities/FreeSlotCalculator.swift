import Foundation

public struct FreeSlot: Sendable {
    public let start: Date
    public let end: Date
    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public enum FreeSlotCalculator: Sendable {
    /// Calculate free time slots from a list of events within a range.
    /// Events should be non-all-day. They don't need to be sorted.
    public static func calculate(
        events: [CalendarEvent],
        rangeStart: Date,
        rangeEnd: Date,
        minDurationMinutes: Int = 0
    ) -> [FreeSlot] {
        let sorted = events
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        var slots: [FreeSlot] = []
        var cursor = rangeStart

        for event in sorted {
            let eventStart = max(event.startDate, rangeStart)
            let eventEnd = min(event.endDate, rangeEnd)

            if eventStart > cursor {
                let slot = FreeSlot(start: cursor, end: eventStart)
                if slot.durationMinutes >= minDurationMinutes {
                    slots.append(slot)
                }
            }
            cursor = max(cursor, eventEnd)
        }

        if cursor < rangeEnd {
            let slot = FreeSlot(start: cursor, end: rangeEnd)
            if slot.durationMinutes >= minDurationMinutes {
                slots.append(slot)
            }
        }

        return slots
    }

    /// Parse a duration string like "30m", "1h", "90m" into minutes.
    public static func parseDuration(_ input: String?) -> Int {
        guard let input else { return 0 }
        let trimmed = input.lowercased().trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("h") {
            return (Int(trimmed.dropLast()) ?? 0) * 60
        }
        if trimmed.hasSuffix("m") {
            return Int(trimmed.dropLast()) ?? 0
        }
        return Int(trimmed) ?? 0
    }
}
