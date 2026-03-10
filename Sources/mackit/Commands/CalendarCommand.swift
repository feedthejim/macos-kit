import ArgumentParser
import MacKitCore
import Foundation

struct CalendarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cal",
        abstract: "Calendar events",
        subcommands: [
            ListEvents.self,
            NextEvent.self,
            FreeSlots.self,
            ListCalendars.self,
            Create.self,
            Delete.self,
            Move.self,
            Update.self,
        ],
        defaultSubcommand: ListEvents.self
    )
}

extension CalendarCommand {
    struct ListEvents: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List calendar events (default: today's remaining events)",
            discussion: """
                Shows events for a date range. By default, shows today's remaining events \
                (past events are hidden unless --include-past is used).

                DATE FORMATS: YYYY-MM-DD, 'today', 'tomorrow', 'yesterday', day names \
                ('monday', 'friday'), 'next monday', 'next week'

                EXAMPLES:
                  mackit cal                              # Today's remaining events
                  mackit cal tomorrow                     # Tomorrow's events
                  mackit cal week                         # Next 7 days
                  mackit cal --from monday --to friday    # Date range
                  mackit cal -c Work -c Personal          # Multiple calendars
                  mackit cal --json title,startDate,meetingURL
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Start date: YYYY-MM-DD, 'today', 'tomorrow', day name, 'next week'")
        var from: String?

        @Option(name: .long, help: "End date (same formats as --from)")
        var to: String?

        @Option(name: [.short, .customLong("calendar")], help: "Filter by calendar name (repeatable)")
        var calendarNames: [String] = []

        @Option(name: [.short, .customLong("limit")], help: "Max number of events")
        var limit: Int?

        @Flag(name: .customLong("include-past"), help: "Include past events today (default: hidden)")
        var includePast: Bool = false

        @Option(name: .customLong("json"), help: """
            Output JSON with specific fields (comma-separated). \
            Fields: id, title, startDate, endDate, isAllDay, location, \
            calendarName, calendarColor, status, organizer, notes, url, meetingURL
            """)
        var jsonFields: String?

        @Argument(help: "Shortcut: 'today', 'tomorrow', or 'week'")
        var shortcut: String?

        func run() async throws {
            let service = LiveCalendarService()
            try await service.requestAccess()

            let (startDate, endDate) = try resolveRange()

            var events = try await service.events(
                from: startDate,
                to: endDate,
                calendars: calendarNames.isEmpty ? nil : calendarNames
            )

            // Filter past events unless --include-past
            if !includePast && Calendar.current.isDateInToday(startDate) {
                events = events.filter { $0.endDate > Date() }
            }

            if let limit {
                events = Array(events.prefix(limit))
            }

            try output(events)
        }

        private func resolveRange() throws -> (Date, Date) {
            let calendar = Calendar.current

            if let shortcut {
                switch shortcut.lowercased() {
                case "today":
                    let start = calendar.startOfDay(for: Date())
                    let end = calendar.date(byAdding: .day, value: 1, to: start)!
                    return (start, end)
                case "tomorrow":
                    let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
                    let end = calendar.date(byAdding: .day, value: 1, to: start)!
                    return (start, end)
                case "week":
                    let start = calendar.startOfDay(for: Date())
                    let end = calendar.date(byAdding: .day, value: 7, to: start)!
                    return (start, end)
                default:
                    throw MacKitError.invalidDateFormat(shortcut)
                }
            }

            let start: Date
            if let from {
                start = try DateParsing.parse(from)
            } else {
                start = calendar.startOfDay(for: Date())
            }

            let end: Date
            if let to {
                end = try DateParsing.parse(to)
            } else {
                end = calendar.date(byAdding: .day, value: 1, to: start)!
            }

            return (start, end)
        }

        private func output(_ events: [CalendarEvent]) throws {
            if let jsonFields {
                let fields = jsonFields.split(separator: ",").map(String.init)
                let result = try FieldSelection.select(fields: fields, from: events)
                print(result)
            } else {
                switch globals.effectiveFormat {
                case .json:
                    print(try OutputRenderer.renderJSON(events))
                case .text:
                    if events.isEmpty {
                        print("No events")
                    } else {
                        print(OutputRenderer.renderText(events, emptyMessage: "No events"))
                        let totalMinutes = events.reduce(0) { sum, e in
                            sum + Int(e.endDate.timeIntervalSince(e.startDate) / 60)
                        }
                        print("\n\(events.count) event\(events.count == 1 ? "" : "s"), \(DurationFormatter.format(minutes: totalMinutes)) of meetings")
                    }
                case .table:
                    print(OutputRenderer.renderTable(events, emptyMessage: "No events"))
                }
            }
        }
    }

    struct NextEvent: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "next",
            abstract: "Show the next upcoming event",
            discussion: """
                Returns the next event that hasn't ended yet. Extracts meeting URLs \
                from Zoom, Google Meet, Teams, Webex, and Around links.

                EXAMPLES:
                  mackit cal next                         # Full event details
                  mackit cal next --url                   # Just the meeting URL
                  open $(mackit cal next --url)           # Open next meeting
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Flag(name: .long, help: "Print only the meeting URL (Zoom, Meet, Teams, Webex, Around)")
        var url: Bool = false

        func run() async throws {
            let service = LiveCalendarService()
            try await service.requestAccess()

            guard let event = try await service.nextEvent() else {
                print("No upcoming events")
                throw ExitCode.failure
            }

            if url {
                if let meetingURL = event.meetingURL {
                    print(meetingURL)
                } else {
                    FileHandle.standardError.write(Data("No meeting URL found for: \(event.title)\n".utf8))
                    throw ExitCode.failure
                }
                return
            }

            switch globals.effectiveFormat {
            case .json:
                print(try OutputRenderer.renderJSON(event))
            case .text, .table:
                print(OutputRenderer.renderText(event))
            }
        }
    }

    struct FreeSlots: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "free",
            abstract: "Show free time slots",
            discussion: """
                Calculates gaps between events during working hours (9 AM - 5 PM). \
                Past slots are excluded.

                EXAMPLES:
                  mackit cal free                         # Free slots today
                  mackit cal free --date tomorrow         # Free slots tomorrow
                  mackit cal free --duration 30m          # Only slots >= 30 min
                  mackit cal free --duration 1h           # Only slots >= 1 hour
                """
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Date to check: YYYY-MM-DD, 'today', 'tomorrow', day name (default: today)")
        var date: String?

        @Option(name: .long, help: "Minimum slot duration: 30m, 1h, 90m (default: show all)")
        var duration: String?

        func run() async throws {
            let service = LiveCalendarService()
            try await service.requestAccess()

            let calendar = Calendar.current
            let targetDate: Date
            if let date {
                targetDate = try DateParsing.parse(date)
            } else {
                targetDate = Date()
            }

            let dayStart = calendar.startOfDay(for: targetDate)
            // Working hours: 9 AM - 5 PM
            let rangeStart = max(
                calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart)!,
                Date() // Don't show past slots
            )
            let rangeEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: dayStart)!

            guard rangeStart < rangeEnd else {
                print("No working hours remaining today")
                return
            }

            let events = try await service.events(from: dayStart, to: rangeEnd, calendars: nil)
                .filter { !$0.isAllDay }
                .sorted { $0.startDate < $1.startDate }

            let slots = calculateFreeSlots(events: events, rangeStart: rangeStart, rangeEnd: rangeEnd)

            let minMinutes = parseDuration(duration)
            let filteredSlots = slots.filter { $0.duration >= minMinutes }

            if globals.effectiveFormat == .json {
                let jsonSlots = filteredSlots.map { [
                    "start": ISO8601DateFormatter().string(from: $0.start),
                    "end": ISO8601DateFormatter().string(from: $0.end),
                    "duration": DurationFormatter.format(minutes: $0.duration),
                ] }
                print(try OutputRenderer.renderJSON(jsonSlots))
            } else {
                if filteredSlots.isEmpty {
                    print("No free slots\(minMinutes > 0 ? " >= \(DurationFormatter.format(minutes: minMinutes))" : "")")
                } else {
                    let isToday = calendar.isDateInToday(targetDate)
                    print("Free slots \(isToday ? "today (remaining)" : targetDate.formatted(date: .abbreviated, time: .omitted)):")
                    for slot in filteredSlots {
                        let startStr = slot.start.formatted(date: .omitted, time: .shortened)
                        let endStr = slot.end.formatted(date: .omitted, time: .shortened)
                        print("  \(startStr) – \(endStr)   \(DurationFormatter.format(minutes: slot.duration))")
                    }
                    let totalMinutes = filteredSlots.reduce(0) { $0 + $1.duration }
                    print("\nTotal: \(DurationFormatter.format(minutes: totalMinutes)) free")
                }
            }
        }

        struct FreeSlot {
            let start: Date
            let end: Date
            var duration: Int { Int(end.timeIntervalSince(start) / 60) }
        }

        func calculateFreeSlots(events: [CalendarEvent], rangeStart: Date, rangeEnd: Date) -> [FreeSlot] {
            var slots: [FreeSlot] = []
            var cursor = rangeStart

            for event in events {
                let eventStart = max(event.startDate, rangeStart)
                let eventEnd = min(event.endDate, rangeEnd)

                if eventStart > cursor {
                    slots.append(FreeSlot(start: cursor, end: eventStart))
                }
                cursor = max(cursor, eventEnd)
            }

            if cursor < rangeEnd {
                slots.append(FreeSlot(start: cursor, end: rangeEnd))
            }

            return slots
        }

        func parseDuration(_ input: String?) -> Int {
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

    struct ListCalendars: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "calendars",
            abstract: "List all calendars"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveCalendarService()
            try await service.requestAccess()

            let calendars = try await service.calendars()

            switch globals.effectiveFormat {
            case .json:
                print(try OutputRenderer.renderJSON(calendars))
            case .text:
                print(OutputRenderer.renderText(calendars, emptyMessage: "No calendars"))
            case .table:
                print(OutputRenderer.renderTable(calendars, emptyMessage: "No calendars"))
            }
        }
    }
}
