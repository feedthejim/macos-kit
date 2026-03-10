import Foundation

public final class MCPServer: @unchecked Sendable {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init() {}

    public func run() async throws {
        // Read line by line from stdin
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let request = try JSONRPCRequest(from: data)
                let response = await handleRequest(request)
                let responseData = try response.serialize()
                FileHandle.standardOutput.write(responseData)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                let errResponse = JSONRPCResponse(id: nil, error: .internalError(error.localizedDescription))
                if let data = try? errResponse.serialize() {
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            }
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return JSONRPCResponse(id: request.id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "mackit", "version": "0.1.0"],
            ] as [String: Any])

        case "notifications/initialized":
            // No response needed for notifications, but we still return empty
            return JSONRPCResponse(id: request.id, result: [String: Any]())

        case "tools/list":
            let tools = MCPTools.allTools.map { $0.toDict() }
            return JSONRPCResponse(id: request.id, result: ["tools": tools])

        case "tools/call":
            return await handleToolCall(request)

        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }

    private func handleToolCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params,
              let toolName = params["name"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: .invalidParams)
        }

        let args = params["arguments"]
        let toolArgs: [String: JSONValue]
        if case .object(let obj) = args {
            toolArgs = obj
        } else {
            toolArgs = [:]
        }

        let result: MCPToolResult
        do {
            result = try await dispatchTool(name: toolName, args: toolArgs)
        } catch let error as MacKitError {
            result = MCPToolResult(text: error.errorDescription ?? error.localizedDescription, isError: true)
        } catch {
            result = MCPToolResult(text: error.localizedDescription, isError: true)
        }

        return JSONRPCResponse(id: request.id, result: result.toDict())
    }

    // MARK: - Tool Dispatch

    private func dispatchTool(name: String, args: [String: JSONValue]) async throws -> MCPToolResult {
        switch name {
        // Calendar read
        case "calendar_list": return try await handleCalendarList(args)
        case "calendar_next": return try await handleCalendarNext(args)
        case "calendar_free": return try await handleCalendarFree(args)
        case "calendar_calendars": return try await handleCalendarCalendars(args)
        // Calendar write
        case "calendar_create": return try await handleCalendarCreate(args)
        case "calendar_delete": return try await handleCalendarDelete(args)
        case "calendar_update": return try await handleCalendarUpdate(args)
        case "calendar_move": return try await handleCalendarMove(args)
        // Reminders read
        case "reminders_list": return try await handleRemindersList(args)
        case "reminders_overdue": return try await handleRemindersOverdue(args)
        case "reminders_lists": return try await handleRemindersLists(args)
        // Reminders write
        case "reminders_add": return try await handleRemindersAdd(args)
        case "reminders_complete": return try await handleRemindersComplete(args)
        case "reminders_delete": return try await handleRemindersDelete(args)
        case "reminders_move": return try await handleRemindersMove(args)
        // Contacts
        case "contacts_search": return try await handleContactsSearch(args)
        case "contacts_birthdays": return try await handleContactsBirthdays(args)
        // System
        case "focus_status": return handleFocusStatus(args)
        case "notify_send": return try await handleNotifySend(args)
        default:
            return MCPToolResult(text: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - Calendar Read Handlers

    private func handleCalendarList(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveCalendarService()
        try await service.requestAccess()

        let calendar = Calendar.current
        let fromStr = args["from"]?.stringValue ?? "today"
        let startDate = try DateParsing.parse(fromStr)
        let endDate: Date
        if let toStr = args["to"]?.stringValue {
            endDate = try DateParsing.parse(toStr)
        } else {
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        }

        let calFilter = args["calendar"]?.stringValue.map { [$0] }
        var events = try await service.events(from: startDate, to: endDate, calendars: calFilter)

        let includePast = args["includePast"]?.boolValue ?? false
        if !includePast && calendar.isDateInToday(startDate) {
            events = events.filter { $0.endDate > Date() }
        }

        if let limit = args["limit"]?.intValue {
            events = Array(events.prefix(limit))
        }

        return MCPToolResult(text: try jsonString(events))
    }

    private func handleCalendarNext(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveCalendarService()
        try await service.requestAccess()
        guard let event = try await service.nextEvent() else {
            return MCPToolResult(text: "No upcoming events")
        }
        return MCPToolResult(text: try jsonString(event))
    }

    private func handleCalendarFree(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveCalendarService()
        try await service.requestAccess()

        let cal = Calendar.current
        let dateStr = args["date"]?.stringValue ?? "today"
        let targetDate = try DateParsing.parse(dateStr)
        let dayStart = cal.startOfDay(for: targetDate)
        let rangeStart = max(cal.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart)!, Date())
        let rangeEnd = cal.date(bySettingHour: 17, minute: 0, second: 0, of: dayStart)!

        guard rangeStart < rangeEnd else {
            return MCPToolResult(text: "No working hours remaining")
        }

        let events = try await service.events(from: dayStart, to: rangeEnd, calendars: nil)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        let minDuration = args["minDuration"]?.intValue ?? 0
        var slots: [[String: Any]] = []
        var cursor = rangeStart

        for event in events {
            let eventStart = max(event.startDate, rangeStart)
            let eventEnd = min(event.endDate, rangeEnd)
            if eventStart > cursor {
                let duration = Int(eventStart.timeIntervalSince(cursor) / 60)
                if duration >= minDuration {
                    slots.append([
                        "start": ISO8601DateFormatter().string(from: cursor),
                        "end": ISO8601DateFormatter().string(from: eventStart),
                        "durationMinutes": duration,
                        "duration": DurationFormatter.format(minutes: duration),
                    ])
                }
            }
            cursor = max(cursor, eventEnd)
        }
        if cursor < rangeEnd {
            let duration = Int(rangeEnd.timeIntervalSince(cursor) / 60)
            if duration >= minDuration {
                slots.append([
                    "start": ISO8601DateFormatter().string(from: cursor),
                    "end": ISO8601DateFormatter().string(from: rangeEnd),
                    "durationMinutes": duration,
                    "duration": DurationFormatter.format(minutes: duration),
                ])
            }
        }

        let data = try JSONSerialization.data(withJSONObject: slots, options: [.sortedKeys])
        return MCPToolResult(text: String(data: data, encoding: .utf8)!)
    }

    private func handleCalendarCalendars(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveCalendarService()
        try await service.requestAccess()
        let calendars = try await service.calendars()
        return MCPToolResult(text: try jsonString(calendars))
    }

    // MARK: - Calendar Write Handlers

    private func handleCalendarCreate(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveCalendarWriteService()
        guard let title = args["title"]?.stringValue,
              let dateStr = args["date"]?.stringValue,
              let startTimeStr = args["startTime"]?.stringValue,
              let endTimeStr = args["endTime"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title, date, startTime, endTime", isError: true)
        }

        let allDay = args["allDay"]?.boolValue ?? false
        let startDate = try DateParsing.parseDateTime(dateStr, time: allDay ? "9am" : startTimeStr)
        let endDate = try DateParsing.parseDateTime(dateStr, time: allDay ? "5pm" : endTimeStr)

        let request = CreateEventRequest(
            title: title, startDate: startDate, endDate: endDate,
            calendarName: args["calendar"]?.stringValue,
            location: args["location"]?.stringValue,
            notes: args["notes"]?.stringValue,
            isAllDay: allDay
        )

        let event = try await service.createEvent(request)
        return MCPToolResult(text: try jsonString(event))
    }

    private func handleCalendarDelete(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let eventId = args["eventId"]?.stringValue else {
            return MCPToolResult(text: "Missing required: eventId", isError: true)
        }
        let service = LiveCalendarWriteService()
        try await service.deleteEvent(id: eventId)
        return MCPToolResult(text: "{\"deleted\": true, \"eventId\": \"\(eventId)\"}")
    }

    private func handleCalendarUpdate(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let eventId = args["eventId"]?.stringValue else {
            return MCPToolResult(text: "Missing required: eventId", isError: true)
        }
        let service = LiveCalendarWriteService()
        let request = UpdateEventRequest(
            eventId: eventId,
            title: args["title"]?.stringValue,
            location: args["location"]?.stringValue,
            notes: args["notes"]?.stringValue
        )
        let event = try await service.updateEvent(request)
        return MCPToolResult(text: try jsonString(event))
    }

    private func handleCalendarMove(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let eventId = args["eventId"]?.stringValue else {
            return MCPToolResult(text: "Missing required: eventId", isError: true)
        }

        let service = LiveCalendarWriteService()
        let existing = try await service.findEvent(id: eventId)

        var newStart = existing.startDate
        var newEnd = existing.endDate
        let duration = existing.endDate.timeIntervalSince(existing.startDate)

        if let dateStr = args["date"]?.stringValue {
            let baseDate = try DateParsing.parse(dateStr)
            let startComponents = Calendar.current.dateComponents([.hour, .minute], from: newStart)
            newStart = Calendar.current.date(bySettingHour: startComponents.hour!,
                minute: startComponents.minute!, second: 0, of: baseDate)!
            newEnd = newStart.addingTimeInterval(duration)
        }
        if let startTimeStr = args["startTime"]?.stringValue {
            let time = try DateParsing.parseTime(startTimeStr)
            let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
            newStart = Calendar.current.date(bySettingHour: tc.hour!, minute: tc.minute!, second: 0, of: newStart)!
            newEnd = newStart.addingTimeInterval(duration)
        }
        if let endTimeStr = args["endTime"]?.stringValue {
            let time = try DateParsing.parseTime(endTimeStr)
            let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
            newEnd = Calendar.current.date(bySettingHour: tc.hour!, minute: tc.minute!, second: 0, of: newStart)!
        }

        let updated = try await service.updateEvent(
            UpdateEventRequest(eventId: eventId, startDate: newStart, endDate: newEnd))
        return MCPToolResult(text: try jsonString(updated))
    }

    // MARK: - Reminders Read Handlers

    private func handleRemindersList(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveRemindersService()
        try await service.requestAccess()
        let dueBefore: Date? = try args["due"]?.stringValue.map { try DateParsing.parse($0) }
        let reminders = try await service.reminders(
            inList: args["list"]?.stringValue,
            includeCompleted: args["includeCompleted"]?.boolValue ?? false,
            dueBefore: dueBefore
        )
        let limited = args["limit"]?.intValue.map { Array(reminders.prefix($0)) } ?? reminders
        return MCPToolResult(text: try jsonString(limited))
    }

    private func handleRemindersOverdue(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveRemindersService()
        try await service.requestAccess()
        let reminders = try await service.overdueReminders()
        return MCPToolResult(text: try jsonString(reminders))
    }

    private func handleRemindersLists(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveRemindersService()
        try await service.requestAccess()
        let lists = try await service.lists()
        return MCPToolResult(text: try jsonString(lists))
    }

    // MARK: - Reminders Write Handlers

    private func handleRemindersAdd(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let title = args["title"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title", isError: true)
        }
        let service = LiveRemindersWriteService()
        let dueDate: Date? = try args["due"]?.stringValue.map { try DateParsing.parse($0) }
        let priority: ReminderPriority = switch args["priority"]?.stringValue {
        case "high": .high; case "medium": .medium; case "low": .low
        default: .none
        }
        let reminder = try await service.addReminder(
            title: title, listName: args["list"]?.stringValue,
            dueDate: dueDate, priority: priority, notes: args["notes"]?.stringValue
        )
        return MCPToolResult(text: try jsonString(reminder))
    }

    private func handleRemindersComplete(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveRemindersWriteService()
        if let id = args["id"]?.stringValue {
            let reminder = try await service.completeReminderById(id: id)
            return MCPToolResult(text: try jsonString(reminder))
        } else if let title = args["title"]?.stringValue {
            let reminder = try await service.completeReminder(titleMatch: title)
            return MCPToolResult(text: try jsonString(reminder))
        }
        return MCPToolResult(text: "Provide either 'title' or 'id'", isError: true)
    }

    private func handleRemindersDelete(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let id = args["id"]?.stringValue else {
            return MCPToolResult(text: "Missing required: id", isError: true)
        }
        let service = LiveRemindersWriteService()
        try await service.deleteReminder(id: id)
        return MCPToolResult(text: "{\"deleted\": true, \"id\": \"\(id)\"}")
    }

    private func handleRemindersMove(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let title = args["title"]?.stringValue, let toList = args["toList"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title, toList", isError: true)
        }
        let service = LiveRemindersWriteService()
        let reminder = try await service.moveReminder(titleMatch: title, toList: toList)
        return MCPToolResult(text: try jsonString(reminder))
    }

    // MARK: - Contacts Handlers

    private func handleContactsSearch(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let query = args["query"]?.stringValue else {
            return MCPToolResult(text: "Missing required: query", isError: true)
        }
        let service = LiveContactsService()
        try await service.requestAccess()
        let contacts = try await service.search(query: query, limit: args["limit"]?.intValue)
        return MCPToolResult(text: try jsonString(contacts))
    }

    private func handleContactsBirthdays(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = LiveContactsService()
        try await service.requestAccess()
        let contacts = try await service.upcomingBirthdays(withinDays: args["days"]?.intValue ?? 30)
        return MCPToolResult(text: try jsonString(contacts))
    }

    // MARK: - System Handlers

    private func handleFocusStatus(_ args: [String: JSONValue]) -> MCPToolResult {
        let status = FocusService.currentStatus()
        let json = try? jsonString(status)
        return MCPToolResult(text: json ?? "{\"isEnabled\": false}")
    }

    private func handleNotifySend(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let title = args["title"]?.stringValue, let body = args["body"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title, body", isError: true)
        }
        try await NotificationService.send(
            title: title, body: body,
            subtitle: args["subtitle"]?.stringValue,
            soundName: args["sound"]?.stringValue
        )
        return MCPToolResult(text: "{\"sent\": true}")
    }

    // MARK: - Helpers

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
