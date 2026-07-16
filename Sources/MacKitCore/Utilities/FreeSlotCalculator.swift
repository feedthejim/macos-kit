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
        minDurationMinutes: Int = 0,
        bufferMinutes: Int = 0
    ) -> [FreeSlot] {
        guard rangeEnd > rangeStart else { return [] }
        let buffer = TimeInterval(max(0, bufferMinutes) * 60)
        let sorted = events
            .filter {
                !$0.isAllDay && $0.status != .cancelled && $0.availability != .free
                    && !$0.attendees.contains { $0.isCurrentUser && $0.status == .declined }
            }
            .sorted { $0.startDate < $1.startDate }

        var slots: [FreeSlot] = []
        var cursor = rangeStart

        for event in sorted {
            let eventStart = max(event.startDate.addingTimeInterval(-buffer), rangeStart)
            let eventEnd = min(event.endDate.addingTimeInterval(buffer), rangeEnd)

            guard eventEnd > rangeStart, eventStart < rangeEnd else { continue }

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
    public static func parseDuration(_ input: String?) throws -> Int {
        guard let input else { return 0 }
        let trimmed = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw MacKitError.systemError("Duration cannot be empty. Use formats such as 30m or 1h.")
        }

        let minutes: Int?
        if trimmed.hasSuffix("h") {
            minutes = Int(trimmed.dropLast()).map { $0 * 60 }
        } else if trimmed.hasSuffix("m") {
            minutes = Int(trimmed.dropLast())
        } else {
            minutes = Int(trimmed)
        }

        guard let minutes, minutes >= 0 else {
            throw MacKitError.systemError("Invalid duration '\(input)'. Use formats such as 30m or 1h.")
        }
        return minutes
    }
}
