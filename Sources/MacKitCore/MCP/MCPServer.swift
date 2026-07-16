import Foundation

public final class MCPServer: @unchecked Sendable {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // Reuse service instances across tool calls
    private let calendarService = LiveCalendarService()
    private let calendarWriteService = LiveCalendarWriteService()
    private let remindersService = LiveRemindersService()
    private let remindersWriteService = LiveRemindersWriteService()
    private let contactsService = LiveContactsService()
    private let mailService = LiveMailService()

    public init() {}

    public func run() async throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            do {
                let request = try JSONRPCRequest(from: data)

                // Notifications (no id) get no response per JSON-RPC spec
                if request.method.hasPrefix("notifications/") {
                    continue
                }

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
                "serverInfo": ["name": "mackit", "version": MacKitVersion.current],
            ] as [String: Any])

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
        // Mail read
        case "mail_list": return try await handleMailList(args)
        case "mail_search": return try await handleMailSearch(args)
        case "mail_read": return try await handleMailRead(args)
        case "mail_mailboxes": return try await handleMailMailboxes(args)
        case "mail_accounts": return try await handleMailAccounts(args)
        // Mail write
        case "mail_send": return try await handleMailSend(args)
        case "mail_mark_read": return try await handleMailMarkRead(args)
        case "mail_mark_unread": return try await handleMailMarkUnread(args)
        case "mail_move": return try await handleMailMove(args)
        case "mail_delete": return try await handleMailDelete(args)
        // System
        case "focus_status": return handleFocusStatus(args)
        case "notify_send": return try await handleNotifySend(args)
        default:
            return MCPToolResult(text: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - Calendar Read Handlers

    private func handleCalendarList(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await calendarService.requestAccess()

        let calendar = Calendar.current
        let fromStr = args["from"]?.stringValue ?? "today"
        let startDate = try DateParsing.parse(fromStr)
        let endDate: Date
        if let toStr = args["to"]?.stringValue {
            endDate = try DateParsing.parseRangeEnd(toStr)
        } else {
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        }

        let calFilter = args["calendar"]?.stringValue.map { [$0] }
        let includePast = args["includePast"]?.boolValue ?? false
        let queryStart = !includePast && calendar.isDateInToday(startDate)
            ? max(startDate, Date()) : startDate
        let events = try await calendarService.events(
            from: queryStart,
            to: endDate,
            calendars: calFilter,
            limit: args["limit"]?.intValue
        )

        let extraFields = parseFields(args["fields"]?.stringValue)
        return MCPToolResult(text: try compactEvents(events, extraFields: extraFields))
    }

    private func handleCalendarNext(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await calendarService.requestAccess()
        guard let event = try await calendarService.nextEvent() else {
            return MCPToolResult(text: "No upcoming events")
        }
        let extraFields = parseFields(args["fields"]?.stringValue)
        return MCPToolResult(text: try compactEvent(event, extraFields: extraFields))
    }

    private func handleCalendarFree(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await calendarService.requestAccess()

        let cal = Calendar.current
        let dateStr = args["date"]?.stringValue ?? "today"
        let targetDate = try DateParsing.parse(dateStr)
        let dayStart = cal.startOfDay(for: targetDate)
        guard dayStart >= cal.startOfDay(for: Date()) else {
            throw MacKitError.systemError("Free-slot dates cannot be in the past.")
        }

        let workStart = try timeOnDate(args["workStart"]?.stringValue ?? "9am", date: dayStart)
        let rangeEnd = try timeOnDate(args["workEnd"]?.stringValue ?? "5pm", date: dayStart)
        guard rangeEnd > workStart else {
            throw MacKitError.systemError("workEnd must be after workStart.")
        }
        let rangeStart = cal.isDateInToday(dayStart) ? max(workStart, Date()) : workStart

        guard rangeStart < rangeEnd else {
            return MCPToolResult(text: "No working hours remaining")
        }

        let calendarFilter = args["calendar"]?.stringValue.map { [$0] }
        let events = try await calendarService.events(
            from: rangeStart, to: rangeEnd, calendars: calendarFilter
        )
        let minDuration = args["minDuration"]?.intValue ?? 0
        let bufferMinutes = args["bufferMinutes"]?.intValue ?? 0
        guard minDuration >= 0, bufferMinutes >= 0 else {
            throw MacKitError.systemError("Durations and buffers cannot be negative.")
        }
        let slots = FreeSlotCalculator.calculate(
            events: events, rangeStart: rangeStart, rangeEnd: rangeEnd,
            minDurationMinutes: minDuration, bufferMinutes: bufferMinutes
        )

        let jsonSlots = slots.map { [
            "start": ISO8601DateFormatter().string(from: $0.start),
            "end": ISO8601DateFormatter().string(from: $0.end),
            "durationMinutes": $0.durationMinutes,
            "duration": DurationFormatter.format(minutes: $0.durationMinutes),
        ] as [String: Any] }

        let data = try JSONSerialization.data(withJSONObject: jsonSlots, options: [.sortedKeys])
        return MCPToolResult(text: String(data: data, encoding: .utf8)!)
    }

    private func handleCalendarCalendars(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await calendarService.requestAccess()
        let calendars = try await calendarService.calendars()
        return MCPToolResult(text: try jsonString(calendars))
    }

    // MARK: - Calendar Write Handlers

    private func handleCalendarCreate(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let service = calendarWriteService
        guard let title = args["title"]?.stringValue,
              let dateStr = args["date"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title, date", isError: true)
        }

        let allDay = args["allDay"]?.boolValue ?? false
        let startDate: Date
        let endDate: Date
        if allDay {
            startDate = Calendar.current.startOfDay(for: try DateParsing.parse(dateStr))
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        } else {
            guard let startTime = args["startTime"]?.stringValue,
                  let endTime = args["endTime"]?.stringValue else {
                return MCPToolResult(
                    text: "startTime and endTime are required unless allDay is true",
                    isError: true
                )
            }
            startDate = try DateParsing.parseDateTime(dateStr, time: startTime)
            endDate = try DateParsing.parseDateTime(dateStr, time: endTime)
            guard endDate > startDate else {
                throw MacKitError.systemError("Event end time must be after its start time.")
            }
        }

        let request = CreateEventRequest(
            title: title, startDate: startDate, endDate: endDate,
            calendarName: args["calendar"]?.stringValue,
            location: args["location"]?.stringValue,
            notes: args["notes"]?.stringValue,
            isAllDay: allDay
        )

        let event = try await service.createEvent(request)
        return MCPToolResult(text: try compactEvent(event))
    }

    private func handleCalendarDelete(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let eventId = args["eventId"]?.stringValue else {
            return MCPToolResult(text: "Missing required: eventId", isError: true)
        }
        let service = calendarWriteService
        try await service.deleteEvent(id: eventId, scope: try mutationScope(args["scope"]?.stringValue))
        return MCPToolResult(text: "{\"deleted\": true, \"eventId\": \"\(eventId)\"}")
    }

    private func handleCalendarUpdate(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let eventId = args["eventId"]?.stringValue else {
            return MCPToolResult(text: "Missing required: eventId", isError: true)
        }
        let service = calendarWriteService
        let hasUpdate = args["title"] != nil || args["location"] != nil || args["notes"] != nil
            || args["clearLocation"]?.boolValue == true || args["clearNotes"]?.boolValue == true
            || args["calendar"] != nil || args["allDay"] != nil
        guard hasUpdate else {
            return MCPToolResult(text: "Specify at least one field to update", isError: true)
        }
        var startDate: Date?
        var endDate: Date?
        if args["allDay"]?.boolValue == false {
            guard let startTime = args["startTime"]?.stringValue,
                  let endTime = args["endTime"]?.stringValue else {
                return MCPToolResult(
                    text: "Converting to a timed event requires startTime and endTime",
                    isError: true
                )
            }
            let existing = try await service.findEvent(id: eventId)
            let eventDate = try args["date"]?.stringValue.map { try DateParsing.parse($0) }
                ?? existing.startDate
            let newStart = try timeOnDate(startTime, date: eventDate)
            let newEnd = try timeOnDate(endTime, date: eventDate)
            guard newEnd > newStart else {
                throw MacKitError.systemError("endTime must be after startTime.")
            }
            startDate = newStart
            endDate = newEnd
        } else if args["date"] != nil || args["startTime"] != nil || args["endTime"] != nil {
            return MCPToolResult(
                text: "date, startTime, and endTime are only valid when allDay is false",
                isError: true
            )
        }
        let request = UpdateEventRequest(
            eventId: eventId,
            title: args["title"]?.stringValue,
            startDate: startDate,
            endDate: endDate,
            location: args["location"]?.stringValue,
            notes: args["notes"]?.stringValue,
            clearLocation: args["clearLocation"]?.boolValue ?? false,
            clearNotes: args["clearNotes"]?.boolValue ?? false,
            calendarName: args["calendar"]?.stringValue,
            isAllDay: args["allDay"]?.boolValue,
            scope: try mutationScope(args["scope"]?.stringValue)
        )
        let event = try await service.updateEvent(request)
        return MCPToolResult(text: try compactEvent(event))
    }

    private func handleCalendarMove(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let eventId = args["eventId"]?.stringValue else {
            return MCPToolResult(text: "Missing required: eventId", isError: true)
        }
        guard args["date"] != nil || args["startTime"] != nil || args["endTime"] != nil else {
            return MCPToolResult(text: "Specify date, startTime, or endTime", isError: true)
        }

        let service = calendarWriteService
        let existing = try await service.findEvent(id: eventId)

        var newStart = existing.startDate
        var newEnd = existing.endDate
        let duration = existing.endDate.timeIntervalSince(existing.startDate)

        if existing.isAllDay && (args["startTime"] != nil || args["endTime"] != nil) {
            throw MacKitError.systemError("All-day events can only be moved by date.")
        }

        if let dateStr = args["date"]?.stringValue {
            let baseDate = try DateParsing.parse(dateStr)
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
                    throw MacKitError.systemError("The requested all-day range does not exist.")
                }
                newEnd = movedEnd
            } else {
                let startComponents = Calendar.current.dateComponents([.hour, .minute], from: newStart)
                guard let hour = startComponents.hour, let minute = startComponents.minute,
                      let moved = Calendar.current.date(
                        bySettingHour: hour, minute: minute, second: 0, of: baseDate
                      ) else {
                    throw MacKitError.systemError("The requested date/time does not exist.")
                }
                newStart = moved
                newEnd = newStart.addingTimeInterval(duration)
            }
        }
        if let startTimeStr = args["startTime"]?.stringValue {
            let time = try DateParsing.parseTime(startTimeStr)
            let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
            guard let hour = tc.hour, let minute = tc.minute,
                  let moved = Calendar.current.date(
                    bySettingHour: hour, minute: minute, second: 0, of: newStart
                  ) else {
                throw MacKitError.systemError("The requested start time does not exist.")
            }
            newStart = moved
            newEnd = newStart.addingTimeInterval(duration)
        }
        if let endTimeStr = args["endTime"]?.stringValue {
            let time = try DateParsing.parseTime(endTimeStr)
            let tc = Calendar.current.dateComponents([.hour, .minute], from: time)
            guard let hour = tc.hour, let minute = tc.minute,
                  let moved = Calendar.current.date(
                    bySettingHour: hour, minute: minute, second: 0, of: newStart
                  ) else {
                throw MacKitError.systemError("The requested end time does not exist.")
            }
            newEnd = moved
        }

        guard newEnd > newStart else {
            throw MacKitError.systemError("Event end time must be after its start time.")
        }

        let updated = try await service.updateEvent(
            UpdateEventRequest(
                eventId: eventId, startDate: newStart, endDate: newEnd,
                scope: try mutationScope(args["scope"]?.stringValue)
            ))
        return MCPToolResult(text: try compactEvent(updated))
    }

    private func mutationScope(_ value: String?) throws -> EventMutationScope {
        switch value?.lowercased() ?? "this" {
        case "this", "this-event": return .thisEvent
        case "future", "future-events": return .futureEvents
        default: throw MacKitError.systemError("scope must be 'this' or 'future'.")
        }
    }

    private func timeOnDate(_ value: String, date: Date) throws -> Date {
        let time = try DateParsing.parseTime(value)
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute,
              let result = Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: date
              ) else {
            throw MacKitError.systemError("Time '\(value)' does not exist on the requested date.")
        }
        return result
    }

    // MARK: - Reminders Read Handlers

    private func handleRemindersList(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await remindersService.requestAccess()
        let dueBefore: Date? = try args["due"]?.stringValue.map { try DateParsing.parse($0) }
        let reminders = try await remindersService.reminders(
            inList: args["list"]?.stringValue,
            includeCompleted: args["includeCompleted"]?.boolValue ?? false,
            dueBefore: dueBefore,
            limit: args["limit"]?.intValue
        )
        return MCPToolResult(text: try jsonString(reminders))
    }

    private func handleRemindersOverdue(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await remindersService.requestAccess()
        let reminders = try await remindersService.overdueReminders()
        return MCPToolResult(text: try jsonString(reminders))
    }

    private func handleRemindersLists(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await remindersService.requestAccess()
        let lists = try await remindersService.lists()
        return MCPToolResult(text: try jsonString(lists))
    }

    // MARK: - Reminders Write Handlers

    private func handleRemindersAdd(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let title = args["title"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title", isError: true)
        }
        let service = remindersWriteService
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
        let service = remindersWriteService
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
        let service = remindersWriteService
        try await service.deleteReminder(id: id)
        return MCPToolResult(text: "{\"deleted\": true, \"id\": \"\(id)\"}")
    }

    private func handleRemindersMove(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let title = args["title"]?.stringValue, let toList = args["toList"]?.stringValue else {
            return MCPToolResult(text: "Missing required: title, toList", isError: true)
        }
        let service = remindersWriteService
        let reminder = try await service.moveReminder(titleMatch: title, toList: toList)
        return MCPToolResult(text: try jsonString(reminder))
    }

    // MARK: - Contacts Handlers

    private func handleContactsSearch(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let query = args["query"]?.stringValue else {
            return MCPToolResult(text: "Missing required: query", isError: true)
        }
        try await contactsService.requestAccess()
        let contacts = try await contactsService.search(query: query, limit: args["limit"]?.intValue)
        return MCPToolResult(text: try jsonString(contacts))
    }

    private func handleContactsBirthdays(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await contactsService.requestAccess()
        let contacts = try await contactsService.upcomingBirthdays(withinDays: args["days"]?.intValue ?? 30)
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

    // MARK: - Mail Read Handlers

    private func handleMailList(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let extraFields = parseFields(args["fields"]?.stringValue)
        let page = try await mailService.queryMessages(try mailQuery(args, search: nil, fields: extraFields))
        return MCPToolResult(text: try compactMailPage(page, extraFields: extraFields))
    }

    private func handleMailSearch(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let query = args["query"]?.stringValue else {
            return MCPToolResult(text: "Missing required: query", isError: true)
        }
        let extraFields = parseFields(args["fields"]?.stringValue)
        let page = try await mailService.queryMessages(try mailQuery(args, search: query, fields: extraFields))
        return MCPToolResult(text: try compactMailPage(page, extraFields: extraFields))
    }

    private func mailQuery(
        _ args: [String: JSONValue], search: String?, fields: Set<String>
    ) throws -> MailQuery {
        let limit = args["limit"]?.intValue ?? 25
        let offset = args["offset"]?.intValue ?? 0
        guard (1...200).contains(limit), offset >= 0 else {
            throw MacKitError.systemError("limit must be 1...200 and offset cannot be negative.")
        }
        return MailQuery(
            search: search,
            mailbox: args["mailbox"]?.stringValue,
            account: args["account"]?.stringValue,
            sender: args["sender"]?.stringValue,
            receivedAfter: try args["from"]?.stringValue.map { try DateParsing.parse($0) },
            receivedBefore: try args["to"]?.stringValue.map { try DateParsing.parseRangeEnd($0) },
            unreadOnly: args["unreadOnly"]?.boolValue ?? false,
            limit: limit,
            offset: offset,
            includeDetails: !MailMessage.detailFields.isDisjoint(with: fields),
            requestedFields: fields
        )
    }

    private func handleMailRead(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let id = args["id"]?.stringValue,
              let mailbox = args["mailbox"]?.stringValue,
              let account = args["account"]?.stringValue else {
            return MCPToolResult(text: "Missing required: id, mailbox, account", isError: true)
        }
        let message = try await mailService.getMessage(id: id, mailbox: mailbox, account: account)
        return MCPToolResult(text: try jsonString(message))
    }

    private func handleMailMailboxes(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let mailboxes = try await mailService.mailboxes(account: args["account"]?.stringValue)
        return MCPToolResult(text: try jsonString(mailboxes))
    }

    private func handleMailAccounts(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        let accounts = try await mailService.accounts()
        return MCPToolResult(text: try jsonString(accounts))
    }

    // MARK: - Mail Write Handlers

    private func handleMailSend(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let toStr = args["to"]?.stringValue,
              let subject = args["subject"]?.stringValue,
              let body = args["body"]?.stringValue else {
            return MCPToolResult(text: "Missing required: to, subject, body", isError: true)
        }
        let to = toStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let cc = args["cc"]?.stringValue?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let bcc = args["bcc"]?.stringValue?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        try await mailService.sendMessage(to: to, cc: cc, bcc: bcc, subject: subject, body: body, from: args["from"]?.stringValue)
        return MCPToolResult(text: "{\"sent\": true, \"to\": \"\(toStr)\"}")
    }

    private func handleMailMarkRead(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let id = args["id"]?.stringValue,
              let mailbox = args["mailbox"]?.stringValue,
              let account = args["account"]?.stringValue else {
            return MCPToolResult(text: "Missing required: id, mailbox, account", isError: true)
        }
        try await mailService.markRead(id: id, mailbox: mailbox, account: account)
        return MCPToolResult(text: "{\"markedRead\": true, \"id\": \"\(id)\"}")
    }

    private func handleMailMarkUnread(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let id = args["id"]?.stringValue,
              let mailbox = args["mailbox"]?.stringValue,
              let account = args["account"]?.stringValue else {
            return MCPToolResult(text: "Missing required: id, mailbox, account", isError: true)
        }
        try await mailService.markUnread(id: id, mailbox: mailbox, account: account)
        return MCPToolResult(text: "{\"markedUnread\": true, \"id\": \"\(id)\"}")
    }

    private func handleMailMove(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let id = args["id"]?.stringValue,
              let mailbox = args["mailbox"]?.stringValue,
              let toMailbox = args["toMailbox"]?.stringValue,
              let account = args["account"]?.stringValue else {
            return MCPToolResult(text: "Missing required: id, mailbox, toMailbox, account", isError: true)
        }
        try await mailService.moveMessage(id: id, fromMailbox: mailbox, toMailbox: toMailbox, account: account)
        return MCPToolResult(text: "{\"moved\": true, \"id\": \"\(id)\", \"to\": \"\(toMailbox)\"}")
    }

    private func handleMailDelete(_ args: [String: JSONValue]) async throws -> MCPToolResult {
        guard let id = args["id"]?.stringValue,
              let mailbox = args["mailbox"]?.stringValue,
              let account = args["account"]?.stringValue else {
            return MCPToolResult(text: "Missing required: id, mailbox, account", isError: true)
        }
        try await mailService.deleteMessage(id: id, mailbox: mailbox, account: account)
        return MCPToolResult(text: "{\"deleted\": true, \"id\": \"\(id)\"}")
    }

    // MARK: - Compact MCP Serialization
    // MCP responses should be concise to avoid wasting agent context.
    // Full notes, HTML content, and calendar colors are stripped.

    private func compactEvents(_ events: [CalendarEvent], extraFields: Set<String> = []) throws -> String {
        let isoFormatter = ISO8601DateFormatter()
        let compact = events.map { e -> [String: Any?] in
            var dict: [String: Any?] = [
                "id": e.id,
                "title": e.title,
                "start": isoFormatter.string(from: e.startDate),
                "end": isoFormatter.string(from: e.endDate),
                "allDay": e.isAllDay ? true : nil,
                "calendar": e.calendarName,
                "location": e.location.flatMap { loc in
                    loc.contains("zoom.us") || loc.contains("teams.microsoft") ? nil : loc
                },
                "meetingURL": e.meetingURL,
                "status": e.status.rawValue,
                "availability": e.availability.rawValue,
                "recurring": e.isRecurring ? true : nil,
            ]
            // Extra fields, only included when requested
            if extraFields.contains("notes") { dict["notes"] = e.notes }
            if extraFields.contains("organizer") { dict["organizer"] = e.organizer }
            if extraFields.contains("calendarColor") { dict["calendarColor"] = e.calendarColor }
            if extraFields.contains("url") { dict["url"] = e.url }
            if extraFields.contains("calendarId") { dict["calendarId"] = e.calendarId }
            if extraFields.contains("attendees") {
                dict["attendees"] = e.attendees.map { attendee in
                    var value: [String: Any] = [
                        "status": attendee.status.rawValue,
                        "isCurrentUser": attendee.isCurrentUser,
                    ]
                    if let name = attendee.name { value["name"] = name }
                    if let email = attendee.email { value["email"] = email }
                    return value
                }
            }
            return dict
        }.map { dict in dict.compactMapValues { $0 } }
        let data = try JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func compactEvent(_ event: CalendarEvent, extraFields: Set<String> = []) throws -> String {
        try compactEvents([event], extraFields: extraFields)
            .replacingOccurrences(of: "^\\[|\\]$", with: "", options: .regularExpression)
    }

    private func parseFields(_ input: String?) -> Set<String> {
        guard let input else { return [] }
        return Set(input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private func compactMessages(_ messages: [MailMessage], extraFields: Set<String> = []) throws -> String {
        let isoFormatter = ISO8601DateFormatter()
        let compact = messages.map { m -> [String: Any?] in
            var dict: [String: Any?] = [
                "id": m.id,
                "subject": m.subject,
                "sender": m.sender,
                "date": isoFormatter.string(from: m.dateReceived),
                "mailbox": m.mailbox,
                "account": m.account,
            ]
            if !m.isRead { dict["unread"] = true }
            if extraFields.contains("toRecipients") { dict["toRecipients"] = m.toRecipients }
            if extraFields.contains("ccRecipients") { dict["ccRecipients"] = m.ccRecipients }
            if extraFields.contains("summary") { dict["summary"] = m.summary }
            if extraFields.contains("messageId") { dict["messageId"] = m.messageId }
            if extraFields.contains("replyTo") { dict["replyTo"] = m.replyTo }
            if extraFields.contains("messageSize") { dict["messageSize"] = m.messageSize }
            if extraFields.contains("attachments") { dict["attachments"] = m.attachments.map { attachment in
                var value: [String: Any] = [
                    "id": attachment.id,
                    "name": attachment.name,
                    "sizeBytes": attachment.sizeBytes,
                    "downloaded": attachment.isDownloaded,
                ]
                if let mimeType = attachment.mimeType { value["mimeType"] = mimeType }
                return value
            } }
            dict["threadId"] = m.threadId
            if m.attachmentCount > 0 { dict["attachmentCount"] = m.attachmentCount }
            return dict
        }.map { dict in dict.compactMapValues { $0 } }
        let data = try JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func compactMailPage(_ page: MailPage, extraFields: Set<String>) throws -> String {
        let messagesData = Data(try compactMessages(page.messages, extraFields: extraFields).utf8)
        let messages = try JSONSerialization.jsonObject(with: messagesData)
        var value: [String: Any] = [
            "messages": messages,
            "offset": page.offset,
            "partial": page.isPartial,
        ]
        if let nextOffset = page.nextOffset { value["nextOffset"] = nextOffset }
        if !page.warnings.isEmpty { value["warnings"] = page.warnings }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
