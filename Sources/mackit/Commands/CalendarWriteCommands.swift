import ArgumentParser
import MacKitCore
import Foundation

extension CalendarCommand {
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create", abstract: "Create a calendar event")

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Event title") var title: String
        @Option(name: .long, help: "Date (today, tomorrow, monday, YYYY-MM-DD)") var date: String = "today"
        @Option(name: .long, help: "Start time (3pm, 14:30)") var from: String
        @Option(name: .long, help: "End time") var to: String
        @Option(name: [.short, .customLong("calendar")], help: "Calendar name") var calendarName: String?
        @Option(name: .long, help: "Location") var location: String?
        @Option(name: .long, help: "Notes") var notes: String?
        @Flag(name: .customLong("all-day"), help: "Create all-day event") var allDay: Bool = false
        @Flag(name: .customLong("dry-run"), help: "Preview without creating") var dryRun: Bool = false

        func run() async throws {
            let startDate = try DateParsing.parseDateTime(date, time: allDay ? "9am" : from)
            let endDate = try DateParsing.parseDateTime(date, time: allDay ? "5pm" : to)

            if dryRun {
                let preview = CalendarEvent(id: "(preview)", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: allDay, location: location,
                    calendarName: calendarName ?? "(default)")
                FileHandle.standardError.write(Data("Dry run — would create:\n".utf8))
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
            commandName: "delete", abstract: "Delete a calendar event")

        @Argument(help: "Event ID") var eventId: String
        @Flag(name: .long, help: "Skip confirmation") var yes: Bool = false
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
            commandName: "move", abstract: "Reschedule a calendar event")

        @Argument(help: "Event ID") var eventId: String
        @Option(name: .long, help: "New date") var date: String?
        @Option(name: .long, help: "New start time") var from: String?
        @Option(name: .long, help: "New end time") var to: String?
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
            commandName: "update", abstract: "Update a calendar event")

        @Argument(help: "Event ID") var eventId: String
        @Option(name: .long, help: "New title") var title: String?
        @Option(name: .long, help: "New notes") var notes: String?
        @Option(name: .long, help: "New location") var location: String?
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
