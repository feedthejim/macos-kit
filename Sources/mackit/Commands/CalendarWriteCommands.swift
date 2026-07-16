import ArgumentParser
import MacKitCore
import Foundation

private func parseMutationScope(_ value: String) throws -> EventMutationScope {
    switch value.lowercased() {
    case "this", "this-event": return .thisEvent
    case "future", "future-events": return .futureEvents
    default: throw ValidationError("--scope must be 'this' or 'future'")
    }
}

extension CalendarCommand {
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a calendar event",
            discussion: """
                Creates an event on the specified calendar. Use --dry-run to preview \
                without creating. When --all-day is used, --from and --to are ignored.

                TIME FORMATS: 3pm, 9:30am, 14:30, 12pm (noon), 12am (midnight)
                DATE FORMATS: YYYY-MM-DD, 'today', 'tomorrow', day names, 'next monday'

                EXAMPLES:
                  mackit cal create "Coffee" --date tomorrow --from 3pm --to 3:30pm
                  mackit cal create "Review" --date friday --from 2pm --to 3pm -c Work
                  mackit cal create "Offsite" --date 2026-03-20 --all-day
                  mackit cal create "Test" --date tomorrow --from 1pm --to 2pm --dry-run
                """
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Event title") var title: String
        @Option(name: .long, help: "Date: YYYY-MM-DD, 'today', 'tomorrow', day name (default: today)") var date: String = "today"
        @Option(name: .long, help: "Start time: 3pm, 9:30am, 14:30 (required unless --all-day)") var from: String?
        @Option(name: .long, help: "End time (same formats as --from)") var to: String?
        @Option(name: [.short, .customLong("calendar")], help: "Calendar name or ID (default: system default calendar)") var calendarName: String?
        @Option(name: .long, help: "Event location") var location: String?
        @Option(name: .long, help: "Event notes") var notes: String?
        @Flag(name: .customLong("all-day"), help: "Create as all-day event (ignores --from/--to)") var allDay: Bool = false
        @Flag(name: .customLong("dry-run"), help: "Preview the event without creating it") var dryRun: Bool = false

        func run() async throws {
            if !allDay && (from == nil || to == nil) {
                throw ValidationError("--from and --to are required (unless --all-day is used)")
            }
            let startDate: Date
            let endDate: Date
            if allDay {
                startDate = Calendar.current.startOfDay(for: try DateParsing.parse(date))
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
            } else {
                startDate = try DateParsing.parseDateTime(date, time: from!)
                endDate = try DateParsing.parseDateTime(date, time: to!)
                guard endDate > startDate else {
                    throw ValidationError("--to must be after --from")
                }
            }

            if dryRun {
                let preview = CalendarEvent(id: "(preview)", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: allDay, location: location,
                    calendarName: calendarName ?? "(default)")
                FileHandle.standardError.write(Data("Dry run - would create:\n".utf8))
                print(OutputRenderer.renderText(preview))
                return
            }

            let service = LiveCalendarWriteService()
            let request = CreateEventRequest(title: title, startDate: startDate, endDate: endDate,
                calendarName: calendarName, location: location, notes: notes, isAllDay: allDay)
            let event = try await service.createEvent(request)

            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(event))
            case .text, .table:
                print("Created: \(event.title)")
                print(event.textDetail)
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a calendar event",
            discussion: """
                Without --yes, shows the event details and exits without deleting. \
                Get event IDs from 'mackit cal --json id,title'.

                EXAMPLES:
                  mackit cal delete EVENT_ID              # Preview what will be deleted
                  mackit cal delete EVENT_ID --yes        # Actually delete
                """
        )

        @Argument(help: "Event ID (get from 'mackit cal --json id,title')") var eventId: String
        @Flag(name: .long, help: "Skip confirmation and delete immediately") var yes: Bool = false
        @Option(name: .long, help: "Recurring event scope: this or future (default: this)") var scope: String = "this"
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveCalendarWriteService()

            if !yes {
                let event = try await service.findEvent(id: eventId)
                FileHandle.standardError.write(Data("About to delete:\n\(event.textDetail)\n\nUse --yes to confirm.\n".utf8))
                throw ExitCode.failure
            }

            try await service.deleteEvent(id: eventId, scope: parseMutationScope(scope))
            FileHandle.standardError.write(Data("Deleted.\n".utf8))
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Reschedule a calendar event",
            discussion: """
                Changes the date and/or time of an event. Duration is preserved \
                unless a new --to time is specified. At least one of --date, --from, \
                or --to must be provided.

                EXAMPLES:
                  mackit cal move EVENT_ID --date friday           # Same time, different day
                  mackit cal move EVENT_ID --from 3pm              # Same day, different time
                  mackit cal move EVENT_ID --date monday --from 10am --to 11am
                """
        )

        @Argument(help: "Event ID (get from 'mackit cal --json id,title')") var eventId: String
        @Option(name: .long, help: "New date: YYYY-MM-DD, 'today', 'tomorrow', day name") var date: String?
        @Option(name: .long, help: "New start time: 3pm, 14:30 (preserves duration unless --to set)") var from: String?
        @Option(name: .long, help: "New end time (overrides preserved duration)") var to: String?
        @Option(name: .long, help: "Recurring event scope: this or future (default: this)") var scope: String = "this"
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            guard date != nil || from != nil || to != nil else {
                throw ValidationError("At least one of --date, --from, or --to is required")
            }
            let service = LiveCalendarWriteService()
            let existing = try await service.findEvent(id: eventId)

            if existing.isAllDay && (from != nil || to != nil) {
                throw ValidationError("All-day events can only be moved with --date")
            }

            var newStart = existing.startDate
            var newEnd = existing.endDate
            let duration = existing.endDate.timeIntervalSince(existing.startDate)

            if let date {
                let baseDate = try DateParsing.parse(date)
                if existing.isAllDay {
                    let oldStart = Calendar.current.startOfDay(for: existing.startDate)
                    let oldEnd = Calendar.current.startOfDay(for: existing.endDate)
                    let dayCount = max(
                        1,
                        Calendar.current.dateComponents([.day], from: oldStart, to: oldEnd).day ?? 1
                    )
                    newStart = Calendar.current.startOfDay(for: baseDate)
                    guard let movedEnd = Calendar.current.date(
                        byAdding: .day, value: dayCount, to: newStart
                    ) else {
                        throw ValidationError("The requested all-day range does not exist")
                    }
                    newEnd = movedEnd
                } else {
                    let sc = Calendar.current.dateComponents([.hour, .minute], from: newStart)
                    guard let hour = sc.hour, let minute = sc.minute,
                          let movedStart = Calendar.current.date(
                            bySettingHour: hour, minute: minute, second: 0, of: baseDate
                          ) else {
                        throw ValidationError("The requested date/time does not exist in the current time zone")
                    }
                    newStart = movedStart
                    newEnd = newStart.addingTimeInterval(duration)
                }
            }
            if let from {
                let time = try DateParsing.parseTime(from)
                let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
                guard let hour = tc.hour, let minute = tc.minute,
                      let movedStart = Calendar.current.date(
                        bySettingHour: hour, minute: minute, second: 0, of: newStart
                      ) else {
                    throw ValidationError("The requested start time does not exist in the current time zone")
                }
                newStart = movedStart
                newEnd = newStart.addingTimeInterval(duration)
            }
            if let to {
                let time = try DateParsing.parseTime(to)
                let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
                guard let hour = tc.hour, let minute = tc.minute,
                      let movedEnd = Calendar.current.date(
                        bySettingHour: hour, minute: minute, second: 0, of: newStart
                      ) else {
                    throw ValidationError("The requested end time does not exist in the current time zone")
                }
                newEnd = movedEnd
            }

            guard newEnd > newStart else {
                throw ValidationError("The event end time must be after its start time")
            }

            let updated = try await service.updateEvent(
                UpdateEventRequest(
                    eventId: eventId, startDate: newStart, endDate: newEnd,
                    scope: parseMutationScope(scope)
                ))

            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(updated))
            case .text, .table:
                print("Moved: \(updated.title)")
                print(updated.textDetail)
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update a calendar event",
            discussion: """
                Only the specified fields are changed; others remain unchanged.

                EXAMPLES:
                  mackit cal update EVENT_ID --notes "Updated agenda"
                  mackit cal update EVENT_ID --title "New Title" --location "Room 5"
                  mackit cal update EVENT_ID --clear-location
                  mackit cal update EVENT_ID --timed --from 9am --to 10am
                """
        )

        @Argument(help: "Event ID (get from 'mackit cal --json id,title')") var eventId: String
        @Option(name: .long, help: "New event title") var title: String?
        @Option(name: .long, help: "New event notes") var notes: String?
        @Option(name: .long, help: "New event location") var location: String?
        @Flag(name: .customLong("clear-location"), help: "Remove the event location") var clearLocation = false
        @Flag(name: .customLong("clear-notes"), help: "Remove the event notes") var clearNotes = false
        @Option(name: .customLong("calendar"), help: "Move to a writable calendar name or ID") var calendarName: String?
        @Flag(name: .customLong("all-day"), help: "Convert the event to an all-day event") var allDay = false
        @Flag(name: .customLong("timed"), help: "Convert an all-day event to a timed event (requires --from and --to)") var timed = false
        @Option(name: .long, help: "Date used with --timed (default: existing event date)") var date: String?
        @Option(name: .long, help: "Start time used with --timed") var from: String?
        @Option(name: .long, help: "End time used with --timed") var to: String?
        @Option(name: .long, help: "Recurring event scope: this or future (default: this)") var scope: String = "this"
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            guard title != nil || notes != nil || location != nil || clearLocation || clearNotes
                    || calendarName != nil || allDay || timed else {
                throw ValidationError("Specify at least one field to update")
            }
            guard !(allDay && timed) else {
                throw ValidationError("Use either --all-day or --timed, not both")
            }
            guard timed || (date == nil && from == nil && to == nil) else {
                throw ValidationError("--date, --from, and --to are only valid with --timed")
            }
            guard !timed || (from != nil && to != nil) else {
                throw ValidationError("--timed requires --from and --to")
            }
            guard !(location != nil && clearLocation) else {
                throw ValidationError("Use either --location or --clear-location, not both")
            }
            guard !(notes != nil && clearNotes) else {
                throw ValidationError("Use either --notes or --clear-notes, not both")
            }
            let service = LiveCalendarWriteService()
            var startDate: Date?
            var endDate: Date?
            if timed, let from, let to {
                let existing = try await service.findEvent(id: eventId)
                let eventDate = try date.map { try DateParsing.parse($0) } ?? existing.startDate
                let newStart = try DateParsing.parseDateTime(
                    eventDate.formatted(.iso8601.year().month().day()), time: from
                )
                let newEnd = try DateParsing.parseDateTime(
                    eventDate.formatted(.iso8601.year().month().day()), time: to
                )
                guard newEnd > newStart else {
                    throw ValidationError("--to must be after --from")
                }
                startDate = newStart
                endDate = newEnd
            }
            let updated = try await service.updateEvent(
                UpdateEventRequest(
                    eventId: eventId, title: title, startDate: startDate, endDate: endDate,
                    location: location, notes: notes,
                    clearLocation: clearLocation, clearNotes: clearNotes,
                    calendarName: calendarName, isAllDay: allDay ? true : (timed ? false : nil),
                    scope: parseMutationScope(scope)
                ))

            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(updated))
            case .text, .table:
                print("Updated: \(updated.title)")
                print(updated.textDetail)
            }
        }
    }
}
