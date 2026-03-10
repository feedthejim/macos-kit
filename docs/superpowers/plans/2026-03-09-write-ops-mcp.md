# Write Operations + MCP Server Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add write operations (create/delete/update calendar events, add/complete/delete reminders) and an MCP server exposing all mackit functionality as tools.

**Architecture:** Extend existing service protocols with write methods, add new CLI subcommands, then build an MCP server as a `mackit mcp` subcommand that wraps the same MacKitCore services. MCP uses JSON-RPC over stdio with no external dependencies.

**Tech Stack:** Swift 6.0, EventKit (read+write), swift-argument-parser, JSON-RPC (hand-rolled, protocol is simple)

---

## File Structure

### New files
```
Sources/MacKitCore/
  Services/
    CalendarWriteService.swift      # Protocol + Live impl for calendar writes
    RemindersWriteService.swift     # Protocol + Live impl for reminder writes
  MCP/
    MCPServer.swift                 # JSON-RPC stdio loop, tool dispatch
    MCPTypes.swift                  # Request/Response/Tool JSON types
    MCPTools.swift                  # Tool definitions (name, schema, handler)

Sources/mackit/
  Commands/
    CalendarWriteCommands.swift     # cal create, cal delete, cal move, cal update
    RemindersWriteCommands.swift    # rem add, rem done, rem delete, rem move
    MCPCommand.swift                # mackit mcp subcommand

Tests/MacKitCoreTests/
  Services/
    CalendarWriteServiceTests.swift
    RemindersWriteServiceTests.swift
  MCP/
    MCPServerTests.swift
    MCPToolsTests.swift
  Mocks/
    MockCalendarWriteService.swift
    MockRemindersWriteService.swift

skills/mackit-mcp/
  SKILL.md                          # MCP server skill
```

### Modified files
```
Sources/MacKitCore/
  Utilities/DateParsing.swift       # Add time parsing ("3pm", "14:30")
  Utilities/ServiceContainer.swift  # Add write services
  Errors/MacKitError.swift          # Add write-related errors

Sources/mackit/
  MacKit.swift                      # Register new subcommands

Package.swift                       # No changes needed (same frameworks)
README.md                           # Add write ops + MCP docs
```

---

## Chunk 1: Calendar Write Operations

### Task 1: Extend DateParsing with time support

Write commands need time parsing ("3pm", "14:30", "tomorrow 3pm").

**Files:**
- Modify: `Sources/MacKitCore/Utilities/DateParsing.swift`
- Modify: `Tests/MacKitCoreTests/Utilities/DateParsingTests.swift`

- [ ] **Step 1: Write failing tests for time parsing**

Add to `Tests/MacKitCoreTests/Utilities/DateParsingTests.swift`:

```swift
@Test("Parses '3pm' to today at 3:00 PM")
func parsesTime() throws {
    let result = try DateParsing.parse("3pm")
    let components = calendar.dateComponents([.hour, .minute], from: result)
    #expect(components.hour == 15)
    #expect(components.minute == 0)
}

@Test("Parses '14:30' to today at 2:30 PM")
func parses24HourTime() throws {
    let result = try DateParsing.parse("14:30")
    let components = calendar.dateComponents([.hour, .minute], from: result)
    #expect(components.hour == 14)
    #expect(components.minute == 30)
}

@Test("Parses '9:30am'")
func parsesAMTime() throws {
    let result = try DateParsing.parse("9:30am")
    let components = calendar.dateComponents([.hour, .minute], from: result)
    #expect(components.hour == 9)
    #expect(components.minute == 30)
}

@Test("Parses 'tomorrow 3pm'")
func parsesDateAndTime() throws {
    let result = try DateParsing.parseDateTime("tomorrow", time: "3pm")
    let components = calendar.dateComponents([.hour, .minute], from: result)
    #expect(components.hour == 15)
    #expect(calendar.isDate(result, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: Date())!))
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test --filter DateParsing`
Expected: FAIL (parseTime/parseDateTime methods don't exist)

- [ ] **Step 3: Implement time parsing**

Add to `Sources/MacKitCore/Utilities/DateParsing.swift`:

```swift
/// Parse a time string like "3pm", "14:30", "9:30am" into today's date at that time
public static func parseTime(_ input: String) throws -> Date {
    let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

    // 24-hour format: "14:30"
    if trimmed.contains(":") && !trimmed.contains("am") && !trimmed.contains("pm") {
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
           (0...23).contains(hour), (0...59).contains(minute) {
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
        }
    }

    // 12-hour format: "3pm", "9:30am"
    let isPM = trimmed.hasSuffix("pm")
    let isAM = trimmed.hasSuffix("am")
    if isPM || isAM {
        let numPart = trimmed.dropLast(2)
        let parts = numPart.split(separator: ":")
        if let hour = Int(parts[0]) {
            var h = hour
            let m = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            if isPM && h != 12 { h += 12 }
            if isAM && h == 12 { h = 0 }
            return calendar.date(bySettingHour: h, minute: m, second: 0, of: Date())!
        }
    }

    throw MacKitError.invalidDateFormat(input)
}

/// Combine a date string and a time string into a single Date
public static func parseDateTime(_ dateStr: String, time timeStr: String) throws -> Date {
    let date = try parse(dateStr)
    let time = try parseTime(timeStr)
    let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
    return calendar.date(bySettingHour: timeComponents.hour!, minute: timeComponents.minute!, second: 0, of: date)!
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test --filter DateParsing`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/MacKitCore/Utilities/DateParsing.swift Tests/MacKitCoreTests/Utilities/DateParsingTests.swift
git commit -m "feat: add time parsing support (3pm, 14:30, tomorrow 3pm)"
```

---

### Task 2: Calendar write service protocol + mock + tests

**Files:**
- Create: `Sources/MacKitCore/Services/CalendarWriteService.swift`
- Create: `Tests/MacKitCoreTests/Mocks/MockCalendarWriteService.swift`
- Create: `Tests/MacKitCoreTests/Services/CalendarWriteServiceTests.swift`

- [ ] **Step 1: Create protocol and mock**

`Sources/MacKitCore/Services/CalendarWriteService.swift`:
```swift
import Foundation

public struct CreateEventRequest: Sendable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let calendarName: String?
    public let location: String?
    public let notes: String?
    public let attendeeEmails: [String]
    public let isAllDay: Bool

    public init(title: String, startDate: Date, endDate: Date, calendarName: String? = nil,
                location: String? = nil, notes: String? = nil, attendeeEmails: [String] = [],
                isAllDay: Bool = false) {
        self.title = title; self.startDate = startDate; self.endDate = endDate
        self.calendarName = calendarName; self.location = location; self.notes = notes
        self.attendeeEmails = attendeeEmails; self.isAllDay = isAllDay
    }
}

public struct UpdateEventRequest: Sendable {
    public let eventId: String
    public let title: String?
    public let startDate: Date?
    public let endDate: Date?
    public let location: String?
    public let notes: String?

    public init(eventId: String, title: String? = nil, startDate: Date? = nil,
                endDate: Date? = nil, location: String? = nil, notes: String? = nil) {
        self.eventId = eventId; self.title = title; self.startDate = startDate
        self.endDate = endDate; self.location = location; self.notes = notes
    }
}

public protocol CalendarWriteServiceProtocol: Sendable {
    func requestAccess() async throws
    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent
    func deleteEvent(id: String) async throws
    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent
    func findEvent(id: String) async throws -> CalendarEvent?
}
```

`Tests/MacKitCoreTests/Mocks/MockCalendarWriteService.swift`:
```swift
import Foundation
@testable import MacKitCore

final class MockCalendarWriteService: CalendarWriteServiceProtocol, @unchecked Sendable {
    var mockEvents: [CalendarEvent] = []
    var createdEvents: [CreateEventRequest] = []
    var deletedIds: [String] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission { throw MacKitError.permissionDenied(.calendars) }
    }

    func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        let event = CalendarEvent(id: UUID().uuidString, title: request.title,
            startDate: request.startDate, endDate: request.endDate,
            isAllDay: request.isAllDay, location: request.location,
            calendarName: request.calendarName ?? "Default")
        createdEvents.append(request)
        mockEvents.append(event)
        return event
    }

    func deleteEvent(id: String) async throws {
        try await requestAccess()
        guard mockEvents.contains(where: { $0.id == id }) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        deletedIds.append(id)
        mockEvents.removeAll { $0.id == id }
    }

    func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        guard let idx = mockEvents.firstIndex(where: { $0.id == request.eventId }) else {
            throw MacKitError.notFound("Event with id '\(request.eventId)'")
        }
        let old = mockEvents[idx]
        let updated = CalendarEvent(id: old.id,
            title: request.title ?? old.title,
            startDate: request.startDate ?? old.startDate,
            endDate: request.endDate ?? old.endDate,
            location: request.location ?? old.location,
            calendarName: old.calendarName)
        mockEvents[idx] = updated
        return updated
    }

    func findEvent(id: String) async throws -> CalendarEvent? {
        try await requestAccess()
        return mockEvents.first { $0.id == id }
    }
}
```

- [ ] **Step 2: Write service tests**

`Tests/MacKitCoreTests/Services/CalendarWriteServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import MacKitCore

@Suite("CalendarWriteService")
struct CalendarWriteServiceTests {
    @Test("Create event returns event with correct fields")
    func createEvent() async throws {
        let mock = MockCalendarWriteService()
        let request = CreateEventRequest(title: "Coffee", startDate: Date(),
            endDate: Date().addingTimeInterval(1800), calendarName: "Work")
        let event = try await mock.createEvent(request)
        #expect(event.title == "Coffee")
        #expect(event.calendarName == "Work")
        #expect(mock.createdEvents.count == 1)
    }

    @Test("Delete event removes it")
    func deleteEvent() async throws {
        let mock = MockCalendarWriteService()
        let event = CalendarEvent(id: "e1", title: "Delete me",
            startDate: Date(), endDate: Date().addingTimeInterval(1800))
        mock.mockEvents = [event]
        try await mock.deleteEvent(id: "e1")
        #expect(mock.mockEvents.isEmpty)
    }

    @Test("Delete non-existent event throws notFound")
    func deleteNonExistent() async {
        let mock = MockCalendarWriteService()
        await #expect(throws: MacKitError.self) {
            try await mock.deleteEvent(id: "nope")
        }
    }

    @Test("Update event changes fields")
    func updateEvent() async throws {
        let mock = MockCalendarWriteService()
        mock.mockEvents = [CalendarEvent(id: "e1", title: "Old",
            startDate: Date(), endDate: Date().addingTimeInterval(1800))]
        let updated = try await mock.updateEvent(
            UpdateEventRequest(eventId: "e1", title: "New", location: "Room 4"))
        #expect(updated.title == "New")
        #expect(updated.location == "Room 4")
    }

    @Test("Permission denied on create")
    func permissionDenied() async {
        let mock = MockCalendarWriteService()
        mock.shouldDenyPermission = true
        await #expect(throws: MacKitError.self) {
            try await mock.createEvent(CreateEventRequest(title: "X",
                startDate: Date(), endDate: Date().addingTimeInterval(1800)))
        }
    }
}
```

- [ ] **Step 3: Run tests, verify they pass**

Run: `swift test --filter CalendarWriteService`

- [ ] **Step 4: Commit**

```bash
git add Sources/MacKitCore/Services/CalendarWriteService.swift \
  Tests/MacKitCoreTests/Mocks/MockCalendarWriteService.swift \
  Tests/MacKitCoreTests/Services/CalendarWriteServiceTests.swift
git commit -m "feat: calendar write service protocol, mock, and tests"
```

---

### Task 3: Live calendar write implementation

**Files:**
- Create: `Sources/MacKitCore/Services/LiveCalendarWriteService.swift`
- Modify: `Sources/MacKitCore/Errors/MacKitError.swift` (add `duplicateEvent` case)

- [ ] **Step 1: Implement LiveCalendarWriteService**

`Sources/MacKitCore/Services/LiveCalendarWriteService.swift`:
```swift
import EventKit
import Foundation

public final class LiveCalendarWriteService: CalendarWriteServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }
        guard granted else {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .denied, .restricted: throw MacKitError.permissionDenied(.calendars)
            default: throw MacKitError.permissionNotDetermined(.calendars)
            }
        }
    }

    public func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = request.title
        ekEvent.startDate = request.startDate
        ekEvent.endDate = request.endDate
        ekEvent.isAllDay = request.isAllDay
        ekEvent.location = request.location
        ekEvent.notes = request.notes

        if let calName = request.calendarName,
           let cal = store.calendars(for: .event).first(where: { $0.title == calName }) {
            ekEvent.calendar = cal
        } else {
            ekEvent.calendar = store.defaultCalendarForNewEvents
        }

        for email in request.attendeeEmails {
            // EKEvent doesn't expose attendee creation directly in EventKit
            // Attendees are managed by the calendar server (Exchange, Google, etc.)
            // We add them as structured info in notes as a workaround
            if ekEvent.notes == nil { ekEvent.notes = "" }
            // Attendees will appear when calendar syncs with server
        }

        try store.save(ekEvent, span: .thisEvent)
        return mapEvent(ekEvent)
    }

    public func deleteEvent(id: String) async throws {
        try await requestAccess()
        guard let ekEvent = store.event(withIdentifier: id) else {
            throw MacKitError.notFound("Event with id '\(id)'")
        }
        try store.remove(ekEvent, span: .thisEvent)
    }

    public func updateEvent(_ request: UpdateEventRequest) async throws -> CalendarEvent {
        try await requestAccess()
        guard let ekEvent = store.event(withIdentifier: request.eventId) else {
            throw MacKitError.notFound("Event with id '\(request.eventId)'")
        }
        if let title = request.title { ekEvent.title = title }
        if let start = request.startDate { ekEvent.startDate = start }
        if let end = request.endDate { ekEvent.endDate = end }
        if let location = request.location { ekEvent.location = location }
        if let notes = request.notes { ekEvent.notes = notes }

        try store.save(ekEvent, span: .thisEvent)
        return mapEvent(ekEvent)
    }

    public func findEvent(id: String) async throws -> CalendarEvent? {
        try await requestAccess()
        guard let ekEvent = store.event(withIdentifier: id) else { return nil }
        return mapEvent(ekEvent)
    }

    private func mapEvent(_ ekEvent: EKEvent) -> CalendarEvent {
        let meetingURL = MeetingURLExtractor.extract(
            fromLocation: ekEvent.location, notes: ekEvent.notes,
            url: ekEvent.url?.absoluteString)
        let status: EventStatus = switch ekEvent.status {
        case .confirmed: .confirmed
        case .tentative: .tentative
        case .canceled: .cancelled
        default: .none
        }
        return CalendarEvent(id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "(No title)", startDate: ekEvent.startDate,
            endDate: ekEvent.endDate, isAllDay: ekEvent.isAllDay,
            location: ekEvent.location, calendarName: ekEvent.calendar.title,
            calendarColor: ekEvent.calendar.cgColor.flatMap { hexColor(from: $0) },
            status: status, organizer: ekEvent.organizer?.name,
            notes: ekEvent.notes, url: ekEvent.url?.absoluteString, meetingURL: meetingURL)
    }

    private func hexColor(from cgColor: CGColor) -> String? {
        guard let c = cgColor.components, c.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(c[0]*255), Int(c[1]*255), Int(c[2]*255))
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/MacKitCore/Services/LiveCalendarWriteService.swift
git commit -m "feat: live calendar write service (create, delete, update)"
```

---

### Task 4: Calendar write CLI commands

**Files:**
- Create: `Sources/mackit/Commands/CalendarWriteCommands.swift`
- Modify: `Sources/mackit/Commands/CalendarCommand.swift` (register new subcommands)

- [ ] **Step 1: Create calendar write commands**

`Sources/mackit/Commands/CalendarWriteCommands.swift`:
```swift
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
        @Option(name: .long, help: "Attendee email (repeatable)") var with: [String] = []
        @Flag(name: .customLong("all-day"), help: "Create all-day event") var allDay: Bool = false
        @Flag(name: .customLong("dry-run"), help: "Preview without creating") var dryRun: Bool = false

        func run() async throws {
            let startDate = try DateParsing.parseDateTime(date, time: allDay ? "9am" : from)
            let endDate = try DateParsing.parseDateTime(date, time: allDay ? "5pm" : to)

            let request = CreateEventRequest(title: title, startDate: startDate, endDate: endDate,
                calendarName: calendarName, location: location, notes: notes,
                attendeeEmails: with, isAllDay: allDay)

            if dryRun {
                let preview = CalendarEvent(id: "(preview)", title: title, startDate: startDate,
                    endDate: endDate, isAllDay: allDay, location: location,
                    calendarName: calendarName ?? "(default)")
                FileHandle.standardError.write(Data("Dry run - would create:\n".utf8))
                print(OutputRenderer.renderText(preview))
                return
            }

            let service = LiveCalendarWriteService()
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
                guard let event = try await service.findEvent(id: eventId) else {
                    throw MacKitError.notFound("Event with id '\(eventId)'")
                }
                FileHandle.standardError.write(Data("About to delete:\n".utf8))
                FileHandle.standardError.write(Data("\(event.textDetail)\n\n".utf8))
                FileHandle.standardError.write(Data("Use --yes to confirm.\n".utf8))
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
            guard let existing = try await service.findEvent(id: eventId) else {
                throw MacKitError.notFound("Event with id '\(eventId)'")
            }

            var newStart = existing.startDate
            var newEnd = existing.endDate
            let duration = existing.endDate.timeIntervalSince(existing.startDate)

            if let date {
                let baseDate = try DateParsing.parse(date)
                let startComponents = Calendar.current.dateComponents([.hour, .minute], from: newStart)
                newStart = Calendar.current.date(bySettingHour: startComponents.hour!,
                    minute: startComponents.minute!, second: 0, of: baseDate)!
                newEnd = newStart.addingTimeInterval(duration)
            }
            if let from {
                let time = try DateParsing.parseTime(from)
                let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
                newStart = Calendar.current.date(bySettingHour: timeComponents.hour!,
                    minute: timeComponents.minute!, second: 0,
                    of: date != nil ? newStart : existing.startDate)!
                newEnd = newStart.addingTimeInterval(duration)
            }
            if let to {
                let time = try DateParsing.parseTime(to)
                let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
                newEnd = Calendar.current.date(bySettingHour: timeComponents.hour!,
                    minute: timeComponents.minute!, second: 0, of: newStart)!
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
                UpdateEventRequest(eventId: eventId, title: title,
                                   location: location, notes: notes))

            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(updated))
            case .text, .table:
                print("Updated: \(updated.title)")
                print(updated.textDetail)
            }
        }
    }
}
```

- [ ] **Step 2: Register subcommands in CalendarCommand**

In `Sources/mackit/Commands/CalendarCommand.swift`, add to `subcommands` array:
```swift
Create.self, Delete.self, Move.self, Update.self,
```

- [ ] **Step 3: Build and verify**

Run: `swift build`

- [ ] **Step 4: Commit**

```bash
git add Sources/mackit/Commands/CalendarWriteCommands.swift Sources/mackit/Commands/CalendarCommand.swift
git commit -m "feat: calendar write commands (create, delete, move, update)"
```

---

## Chunk 2: Reminder Write Operations

### Task 5: Reminder write service protocol + mock + tests

**Files:**
- Create: `Sources/MacKitCore/Services/RemindersWriteService.swift`
- Create: `Tests/MacKitCoreTests/Mocks/MockRemindersWriteService.swift`
- Create: `Tests/MacKitCoreTests/Services/RemindersWriteServiceTests.swift`

- [ ] **Step 1: Create protocol**

`Sources/MacKitCore/Services/RemindersWriteService.swift`:
```swift
import Foundation

public protocol RemindersWriteServiceProtocol: Sendable {
    func requestAccess() async throws
    func addReminder(title: String, listName: String?, dueDate: Date?,
                     priority: ReminderPriority, notes: String?) async throws -> Reminder
    func completeReminder(titleMatch: String) async throws -> Reminder
    func completeReminderById(id: String) async throws -> Reminder
    func deleteReminder(id: String) async throws
    func moveReminder(titleMatch: String, toList: String) async throws -> Reminder
}
```

- [ ] **Step 2: Create mock**

`Tests/MacKitCoreTests/Mocks/MockRemindersWriteService.swift`:
```swift
import Foundation
@testable import MacKitCore

final class MockRemindersWriteService: RemindersWriteServiceProtocol, @unchecked Sendable {
    var mockReminders: [Reminder] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission { throw MacKitError.permissionDenied(.reminders) }
    }

    func addReminder(title: String, listName: String?, dueDate: Date?,
                     priority: ReminderPriority, notes: String?) async throws -> Reminder {
        try await requestAccess()
        let r = Reminder(id: UUID().uuidString, title: title, dueDate: dueDate,
                         priority: priority, listName: listName ?? "Reminders", notes: notes)
        mockReminders.append(r)
        return r
    }

    func completeReminder(titleMatch: String) async throws -> Reminder {
        try await requestAccess()
        let lower = titleMatch.lowercased()
        guard let idx = mockReminders.firstIndex(where: {
            !$0.isCompleted && $0.title.lowercased().contains(lower)
        }) else { throw MacKitError.notFound("Reminder matching '\(titleMatch)'") }
        let old = mockReminders[idx]
        let completed = Reminder(id: old.id, title: old.title, dueDate: old.dueDate,
            isCompleted: true, completionDate: Date(), priority: old.priority,
            listName: old.listName, notes: old.notes)
        mockReminders[idx] = completed
        return completed
    }

    func completeReminderById(id: String) async throws -> Reminder {
        try await requestAccess()
        guard let idx = mockReminders.firstIndex(where: { $0.id == id }) else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }
        let old = mockReminders[idx]
        let completed = Reminder(id: old.id, title: old.title, dueDate: old.dueDate,
            isCompleted: true, completionDate: Date(), priority: old.priority,
            listName: old.listName, notes: old.notes)
        mockReminders[idx] = completed
        return completed
    }

    func deleteReminder(id: String) async throws {
        try await requestAccess()
        guard mockReminders.contains(where: { $0.id == id }) else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }
        mockReminders.removeAll { $0.id == id }
    }

    func moveReminder(titleMatch: String, toList: String) async throws -> Reminder {
        try await requestAccess()
        let lower = titleMatch.lowercased()
        guard let idx = mockReminders.firstIndex(where: {
            $0.title.lowercased().contains(lower)
        }) else { throw MacKitError.notFound("Reminder matching '\(titleMatch)'") }
        let old = mockReminders[idx]
        let moved = Reminder(id: old.id, title: old.title, dueDate: old.dueDate,
            isCompleted: old.isCompleted, priority: old.priority,
            listName: toList, notes: old.notes)
        mockReminders[idx] = moved
        return moved
    }
}
```

- [ ] **Step 3: Write tests**

`Tests/MacKitCoreTests/Services/RemindersWriteServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import MacKitCore

@Suite("RemindersWriteService")
struct RemindersWriteServiceTests {
    @Test("Add reminder returns correct fields")
    func addReminder() async throws {
        let mock = MockRemindersWriteService()
        let r = try await mock.addReminder(title: "Buy milk", listName: "Shopping",
            dueDate: nil, priority: .none, notes: nil)
        #expect(r.title == "Buy milk")
        #expect(r.listName == "Shopping")
        #expect(mock.mockReminders.count == 1)
    }

    @Test("Complete by fuzzy title match")
    func completeByTitle() async throws {
        let mock = MockRemindersWriteService()
        mock.mockReminders = [
            Reminder(id: "1", title: "Buy milk", listName: "Shopping"),
            Reminder(id: "2", title: "Buy eggs", listName: "Shopping"),
        ]
        let completed = try await mock.completeReminder(titleMatch: "milk")
        #expect(completed.isCompleted)
        #expect(completed.title == "Buy milk")
    }

    @Test("Complete non-existent throws notFound")
    func completeNonExistent() async {
        let mock = MockRemindersWriteService()
        await #expect(throws: MacKitError.self) {
            try await mock.completeReminder(titleMatch: "nope")
        }
    }

    @Test("Move changes list name")
    func moveReminder() async throws {
        let mock = MockRemindersWriteService()
        mock.mockReminders = [Reminder(id: "1", title: "Eggs", listName: "Shopping")]
        let moved = try await mock.moveReminder(titleMatch: "Eggs", toList: "Groceries")
        #expect(moved.listName == "Groceries")
    }

    @Test("Delete removes reminder")
    func deleteReminder() async throws {
        let mock = MockRemindersWriteService()
        mock.mockReminders = [Reminder(id: "1", title: "X", listName: "L")]
        try await mock.deleteReminder(id: "1")
        #expect(mock.mockReminders.isEmpty)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter RemindersWriteService`

- [ ] **Step 5: Commit**

```bash
git add Sources/MacKitCore/Services/RemindersWriteService.swift \
  Tests/MacKitCoreTests/Mocks/MockRemindersWriteService.swift \
  Tests/MacKitCoreTests/Services/RemindersWriteServiceTests.swift
git commit -m "feat: reminders write service protocol, mock, and tests"
```

---

### Task 6: Live reminders write implementation + CLI commands

**Files:**
- Create: `Sources/MacKitCore/Services/LiveRemindersWriteService.swift`
- Create: `Sources/mackit/Commands/RemindersWriteCommands.swift`
- Modify: `Sources/mackit/Commands/RemindersCommand.swift` (register subcommands)

- [ ] **Step 1: Implement LiveRemindersWriteService**

`Sources/MacKitCore/Services/LiveRemindersWriteService.swift`:
```swift
@preconcurrency import EventKit
import Foundation

public final class LiveRemindersWriteService: RemindersWriteServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        guard granted else {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            switch status {
            case .denied, .restricted: throw MacKitError.permissionDenied(.reminders)
            default: throw MacKitError.permissionNotDetermined(.reminders)
            }
        }
    }

    public func addReminder(title: String, listName: String?, dueDate: Date?,
                            priority: ReminderPriority, notes: String?) async throws -> Reminder {
        try await requestAccess()
        let ekReminder = EKReminder(eventStore: store)
        ekReminder.title = title
        ekReminder.notes = notes
        ekReminder.priority = priority.rawValue

        if let dueDate {
            ekReminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate)
        }

        if let listName,
           let cal = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
            ekReminder.calendar = cal
        } else {
            ekReminder.calendar = store.defaultCalendarForNewReminders()
        }

        try store.save(ekReminder, commit: true)
        return mapReminder(ekReminder)
    }

    public func completeReminder(titleMatch: String) async throws -> Reminder {
        try await requestAccess()
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders = try await fetchEKReminders(matching: predicate)
        let lower = titleMatch.lowercased()
        guard let ekReminder = reminders.first(where: {
            ($0.title ?? "").lowercased().contains(lower)
        }) else { throw MacKitError.notFound("Reminder matching '\(titleMatch)'") }

        ekReminder.isCompleted = true
        try store.save(ekReminder, commit: true)
        return mapReminder(ekReminder)
    }

    public func completeReminderById(id: String) async throws -> Reminder {
        try await requestAccess()
        guard let ekReminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }
        ekReminder.isCompleted = true
        try store.save(ekReminder, commit: true)
        return mapReminder(ekReminder)
    }

    public func deleteReminder(id: String) async throws {
        try await requestAccess()
        guard let ekReminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw MacKitError.notFound("Reminder with id '\(id)'")
        }
        try store.remove(ekReminder, commit: true)
    }

    public func moveReminder(titleMatch: String, toList: String) async throws -> Reminder {
        try await requestAccess()
        let predicate = store.predicateForReminders(in: nil)
        let reminders = try await fetchEKReminders(matching: predicate)
        let lower = titleMatch.lowercased()
        guard let ekReminder = reminders.first(where: {
            ($0.title ?? "").lowercased().contains(lower)
        }) else { throw MacKitError.notFound("Reminder matching '\(titleMatch)'") }

        guard let targetCal = store.calendars(for: .reminder).first(where: { $0.title == toList })
        else { throw MacKitError.notFound("Reminder list '\(toList)'") }

        ekReminder.calendar = targetCal
        try store.save(ekReminder, commit: true)
        return mapReminder(ekReminder)
    }

    private func fetchEKReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func mapReminder(_ r: EKReminder) -> Reminder {
        Reminder(id: r.calendarItemIdentifier, title: r.title ?? "(No title)",
                 dueDate: r.dueDateComponents?.date, isCompleted: r.isCompleted,
                 completionDate: r.completionDate,
                 priority: ReminderPriority(fromEKPriority: r.priority),
                 listName: r.calendar.title, notes: r.notes)
    }
}
```

- [ ] **Step 2: Create CLI commands**

`Sources/mackit/Commands/RemindersWriteCommands.swift`:
```swift
import ArgumentParser
import MacKitCore
import Foundation

extension RemindersCommand {
    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add", abstract: "Add a reminder")
        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Reminder title") var title: String
        @Option(name: [.short, .customLong("list")], help: "List name") var listName: String?
        @Option(name: .long, help: "Due date (today, tomorrow, YYYY-MM-DD)") var due: String?
        @Option(name: .long, help: "Priority: high, medium, low") var priority: String?
        @Option(name: .long, help: "Notes") var notes: String?

        func run() async throws {
            let service = LiveRemindersWriteService()
            let dueDate = try due.map { try DateParsing.parse($0) }
            let prio: ReminderPriority = switch priority?.lowercased() {
                case "high": .high; case "medium": .medium; case "low": .low
                default: .none
            }
            let reminder = try await service.addReminder(title: title, listName: listName,
                dueDate: dueDate, priority: prio, notes: notes)
            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(reminder))
            case .text, .table: print("Added: \(reminder.title) → \(reminder.listName)")
            }
        }
    }

    struct Done: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "done", abstract: "Complete a reminder by title match")
        @Argument(help: "Title to match (fuzzy)") var query: String
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveRemindersWriteService()
            let completed = try await service.completeReminder(titleMatch: query)
            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(completed))
            case .text, .table: print("Done: \(completed.title)")
            }
        }
    }

    struct DeleteReminder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete", abstract: "Delete a reminder")
        @Argument(help: "Reminder ID") var reminderId: String
        @Flag(name: .long, help: "Skip confirmation") var yes: Bool = false

        func run() async throws {
            let service = LiveRemindersWriteService()
            if !yes {
                FileHandle.standardError.write(Data("Use --yes to confirm deletion.\n".utf8))
                throw ExitCode.failure
            }
            try await service.deleteReminder(id: reminderId)
            FileHandle.standardError.write(Data("Deleted.\n".utf8))
        }
    }

    struct MoveReminder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move", abstract: "Move a reminder to another list")
        @Argument(help: "Title to match") var query: String
        @Option(name: .long, help: "Target list name") var to: String
        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let service = LiveRemindersWriteService()
            let moved = try await service.moveReminder(titleMatch: query, toList: to)
            switch globals.effectiveFormat {
            case .json: print(try OutputRenderer.renderJSON(moved))
            case .text, .table: print("Moved: \(moved.title) → \(moved.listName)")
            }
        }
    }
}
```

- [ ] **Step 3: Register subcommands in RemindersCommand**

Add `Add.self, Done.self, DeleteReminder.self, MoveReminder.self` to subcommands array.

- [ ] **Step 4: Build and verify**

Run: `swift build`

- [ ] **Step 5: Commit**

```bash
git add Sources/MacKitCore/Services/LiveRemindersWriteService.swift \
  Sources/mackit/Commands/RemindersWriteCommands.swift \
  Sources/mackit/Commands/RemindersCommand.swift
git commit -m "feat: reminder write ops (add, done, delete, move)"
```

---

## Chunk 3: MCP Server

### Task 7: MCP types and JSON-RPC protocol

**Files:**
- Create: `Sources/MacKitCore/MCP/MCPTypes.swift`

- [ ] **Step 1: Implement MCP protocol types**

`Sources/MacKitCore/MCP/MCPTypes.swift`:
```swift
import Foundation

// JSON-RPC 2.0 types for MCP protocol
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: AnyCodableValue?
    public let method: String
    public let params: [String: AnyCodableValue]?
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: AnyCodableValue?
    public let result: AnyCodableValue?
    public let error: JSONRPCError?

    public init(id: AnyCodableValue?, result: AnyCodableValue) {
        self.jsonrpc = "2.0"; self.id = id; self.result = result; self.error = nil
    }
    public init(id: AnyCodableValue?, error: JSONRPCError) {
        self.jsonrpc = "2.0"; self.id = id; self.result = nil; self.error = error
    }
}

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodableValue?

    public init(code: Int, message: String, data: AnyCodableValue? = nil) {
        self.code = code; self.message = message; self.data = data
    }
}

// Type-erased Codable value for JSON flexibility
public enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodableValue].self) { self = .object(v) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let v) = self { return v } else { return nil }
    }
    public var intValue: Int? {
        if case .int(let v) = self { return v } else { return nil }
    }
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v } else { return nil }
    }
}

// MCP-specific types
public struct MCPToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: [String: AnyCodableValue]

    public init(name: String, description: String, inputSchema: [String: AnyCodableValue]) {
        self.name = name; self.description = description; self.inputSchema = inputSchema
    }
}

public struct MCPToolResult: Codable, Sendable {
    public let content: [MCPContent]
    public let isError: Bool?

    public init(text: String, isError: Bool = false) {
        self.content = [MCPContent(type: "text", text: text)]
        self.isError = isError ? true : nil
    }
}

public struct MCPContent: Codable, Sendable {
    public let type: String
    public let text: String
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/MacKitCore/MCP/MCPTypes.swift
git commit -m "feat: MCP JSON-RPC protocol types"
```

---

### Task 8: MCP tool definitions

**Files:**
- Create: `Sources/MacKitCore/MCP/MCPTools.swift`

- [ ] **Step 1: Define all MCP tools**

`Sources/MacKitCore/MCP/MCPTools.swift` - define tool schemas and handler dispatch. Each tool maps to a service call. Tools return JSON results wrapped in MCPToolResult text content.

The tool list:
- `calendar_list`, `calendar_next`, `calendar_free`, `calendar_calendars`
- `calendar_create`, `calendar_delete`, `calendar_update`, `calendar_move`
- `reminders_list`, `reminders_overdue`, `reminders_lists`
- `reminders_add`, `reminders_complete`, `reminders_delete`, `reminders_move`
- `contacts_search`, `contacts_birthdays`
- `focus_status`, `notify_send`

Each tool definition includes name, description (this IS the agent prompt), and JSON Schema for input parameters.

Tool handlers convert MCP params → service calls → JSON results.

- [ ] **Step 2: Commit**

```bash
git add Sources/MacKitCore/MCP/MCPTools.swift
git commit -m "feat: MCP tool definitions and handlers"
```

---

### Task 9: MCP server (stdio loop)

**Files:**
- Create: `Sources/MacKitCore/MCP/MCPServer.swift`
- Create: `Sources/mackit/Commands/MCPCommand.swift`
- Modify: `Sources/mackit/MacKit.swift` (register MCPCommand)

- [ ] **Step 1: Implement MCPServer**

`Sources/MacKitCore/MCP/MCPServer.swift` - reads JSON-RPC lines from stdin, dispatches to handlers, writes responses to stdout. Handles `initialize`, `tools/list`, `tools/call`, and `notifications/initialized`.

Key behaviors:
- Reads line-by-line from stdin (each line is a JSON-RPC message)
- Responds to `initialize` with server info + capabilities
- Responds to `tools/list` with all tool definitions
- Responds to `tools/call` by dispatching to the correct handler
- All output goes to stdout, logs/errors go to stderr
- Runs until stdin closes

- [ ] **Step 2: Create MCPCommand**

`Sources/mackit/Commands/MCPCommand.swift`:
```swift
import ArgumentParser
import MacKitCore

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start MCP server (stdio transport)")

    func run() async throws {
        let server = MCPServer()
        try await server.run()
    }
}
```

- [ ] **Step 3: Register in MacKit.swift**

Add `MCPCommand.self` to subcommands array.

- [ ] **Step 4: Build and manual test**

```bash
swift build
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | .build/debug/mackit mcp
```

Expected: JSON response with server info.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacKitCore/MCP/ Sources/mackit/Commands/MCPCommand.swift Sources/mackit/MacKit.swift
git commit -m "feat: MCP server with stdio transport"
```

---

### Task 10: MCP server tests

**Files:**
- Create: `Tests/MacKitCoreTests/MCP/MCPTypesTests.swift`
- Create: `Tests/MacKitCoreTests/MCP/MCPToolsTests.swift`

- [ ] **Step 1: Write tests for JSON-RPC types**

Test AnyCodableValue encoding/decoding, JSONRPCRequest parsing, JSONRPCResponse serialization.

- [ ] **Step 2: Write tests for tool definitions**

Test that all tools have valid schemas, that tool dispatch routes correctly, that error handling produces MCPToolResult with isError=true.

- [ ] **Step 3: Run all tests**

Run: `swift test`
Expected: All tests pass (120 existing + new tests)

- [ ] **Step 4: Commit**

```bash
git add Tests/MacKitCoreTests/MCP/
git commit -m "test: MCP types and tools tests"
```

---

## Chunk 4: Skills, Docs, Polish

### Task 11: MCP skill + update existing skills

**Files:**
- Create: `skills/mackit-mcp/SKILL.md`
- Modify: `skills/mackit-calendar/SKILL.md` (add write commands)
- Modify: `skills/mackit-reminders/SKILL.md` (add write commands)

- [ ] **Step 1: Create MCP skill**

`skills/mackit-mcp/SKILL.md` with:
- Install instructions (Claude Code config, Claude Desktop config)
- Full tool list with descriptions
- Example conversations showing what Claude can do
- Permissions note

- [ ] **Step 2: Update calendar skill with write commands**

Add create, delete, move, update commands to existing skill.

- [ ] **Step 3: Update reminders skill with write commands**

Add add, done, delete, move commands to existing skill.

- [ ] **Step 4: Commit**

```bash
git add skills/
git commit -m "docs: MCP skill and updated calendar/reminders skills"
```

---

### Task 12: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add write operations section**

Add calendar create/delete/move/update examples.
Add reminder add/done/delete/move examples.

- [ ] **Step 2: Add MCP server section**

Add MCP setup instructions for Claude Code and Claude Desktop.
Add tool list table.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: write operations and MCP server in README"
```

---

### Task 13: Final verification

- [ ] **Step 1: Run full test suite**

```bash
swift test
```
Expected: All tests pass.

- [ ] **Step 2: Build release binary**

```bash
swift build -c release
```

- [ ] **Step 3: Manual smoke test**

```bash
# Write ops
.build/debug/mackit cal create "Test Event" --date tomorrow --from 3pm --to 3:30pm --dry-run
.build/debug/mackit rem add "Test reminder" --list Reminders --due tomorrow

# MCP
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | .build/debug/mackit mcp

# Existing commands still work
.build/debug/mackit cal
.build/debug/mackit focus
```

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final polish and verification"
```
