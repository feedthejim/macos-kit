import ArgumentParser
import MacKitCore
import Foundation

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
        @Option(name: .long, help: "Start time: 3pm, 9:30am, 14:30 (required unless --all-day)") var from: String
        @Option(name: .long, help: "End time (same formats as --from)") var to: String
        @Option(name: [.short, .customLong("calendar")], help: "Calendar name (default: system default calendar)") var calendarName: String?
        @Option(name: .long, help: "Event location") var location: String?
        @Option(name: .long, help: "Event notes") var notes: String?
        @Flag(name: .customLong("all-day"), help: "Create as all-day event (ignores --from/--to)") var allDay: Bool = false
        @Flag(name: .customLong("dry-run"), help: "Preview the event without creating it") var dryRun: Bool = false

        func run() async throws {
            let startDate = try DateParsing.parseDateTime(date, time: allDay ? "9am" : from)
            let endDate = try DateParsing.parseDateTime(date, time: allDay ? "5pm" : to)

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
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveCalendarWriteService()

            if !yes {
                let event = try await service.findEvent(id: eventId)
                FileHandle.standardError.write(Data("About to delete:\n\(event.textDetail)\n\nUse --yes to confirm.\n".utf8))
                throw ExitCode.failure
            }

            try await service.deleteEvent(id: eventId)
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
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveCalendarWriteService()
            let existing = try await service.findEvent(id: eventId)

            var newStart = existing.startDate
            var newEnd = existing.endDate
            let duration = existing.endDate.timeIntervalSince(existing.startDate)

            if let date {
                let baseDate = try DateParsing.parse(date)
                let sc = Calendar.current.dateComponents([.hour, .minute], from: newStart)
                newStart = Calendar.current.date(bySettingHour: sc.hour!, minute: sc.minute!, second: 0, of: baseDate)!
                newEnd = newStart.addingTimeInterval(duration)
            }
            if let from {
                let time = try DateParsing.parseTime(from)
                let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
                newStart = Calendar.current.date(bySettingHour: tc.hour!, minute: tc.minute!, second: 0, of: newStart)!
                newEnd = newStart.addingTimeInterval(duration)
            }
            if let to {
                let time = try DateParsing.parseTime(to)
                let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
                newEnd = Calendar.current.date(bySettingHour: tc.hour!, minute: tc.minute!, second: 0, of: newStart)!
            }

            let updated = try await service.updateEvent(
                UpdateEventRequest(eventId: eventId, startDate: newStart, endDate: newEnd))

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
                """
        )

        @Argument(help: "Event ID (get from 'mackit cal --json id,title')") var eventId: String
        @Option(name: .long, help: "New event title") var title: String?
        @Option(name: .long, help: "New event notes") var notes: String?
        @Option(name: .long, help: "New event location") var location: String?
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveCalendarWriteService()
            let updated = try await service.updateEvent(
                UpdateEventRequest(eventId: eventId, title: title, location: location, notes: notes))

            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(updated))
            case .text, .table:
                print("Updated: \(updated.title)")
                print(updated.textDetail)
            }
        }
    }
}
