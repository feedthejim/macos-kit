import Foundation

public enum MCPTools: Sendable {
    // MARK: - Tool Definitions

    public static let allTools: [MCPToolDefinition] = [
        // Calendar read
        MCPToolDefinition(
            name: "calendar_list",
            description: "List calendar events within a date range. Returns compact events (title, time, calendar, meetingURL). Use 'fields' to request additional data like notes or organizer.",
            inputSchema: schema(properties: [
                "from": prop(.string, "Start date: ISO 8601 (YYYY-MM-DD), 'today', 'tomorrow', day name"),
                "to": prop(.string, "End date (same formats)"),
                "calendar": prop(.string, "Filter by calendar name"),
                "limit": prop(.integer, "Max events to return"),
                "includePast": prop(.boolean, "Include past events today (default: false)"),
                "fields": prop(.string, "Comma-separated extra fields: notes, organizer, calendarColor, url, status. Default returns compact view."),
            ])
        ),
        MCPToolDefinition(
            name: "calendar_next",
            description: "Get the next upcoming calendar event. Returns compact view. Use 'fields' to request additional data.",
            inputSchema: schema(properties: [
                "fields": prop(.string, "Comma-separated extra fields: notes, organizer, calendarColor, url, status"),
            ])
        ),
        MCPToolDefinition(
            name: "calendar_free",
            description: "Find free time slots in the calendar. Returns available slots with duration. Useful for scheduling.",
            inputSchema: schema(properties: [
                "date": prop(.string, "Date to check (default: today)"),
                "minDuration": prop(.integer, "Minimum slot duration in minutes (default: 0)"),
            ])
        ),
        MCPToolDefinition(
            name: "calendar_calendars",
            description: "List all available calendars with their names, sources, and colors.",
            inputSchema: schema(properties: [:])
        ),
        // Calendar write
        MCPToolDefinition(
            name: "calendar_create",
            description: "Create a new calendar event. Returns the created event with its ID.",
            inputSchema: schema(
                properties: [
                    "title": prop(.string, "Event title"),
                    "date": prop(.string, "Date: ISO 8601 (YYYY-MM-DD), 'today', 'tomorrow', day name"),
                    "startTime": prop(.string, "Start time: '3pm', '14:30', '9:30am'"),
                    "endTime": prop(.string, "End time (same formats)"),
                    "calendar": prop(.string, "Calendar name (uses default if omitted)"),
                    "location": prop(.string, "Event location"),
                    "notes": prop(.string, "Event notes"),
                    "allDay": prop(.boolean, "Create as all-day event"),
                ],
                required: ["title", "date", "startTime", "endTime"]
            )
        ),
        MCPToolDefinition(
            name: "calendar_delete",
            description: "Delete a calendar event by its ID. Returns confirmation of deletion.",
            inputSchema: schema(properties: ["eventId": prop(.string, "Event ID to delete")], required: ["eventId"])
        ),
        MCPToolDefinition(
            name: "calendar_update",
            description: "Update fields on an existing calendar event. Only specified fields are changed.",
            inputSchema: schema(
                properties: [
                    "eventId": prop(.string, "Event ID to update"),
                    "title": prop(.string, "New title"),
                    "notes": prop(.string, "New notes"),
                    "location": prop(.string, "New location"),
                ],
                required: ["eventId"]
            )
        ),
        MCPToolDefinition(
            name: "calendar_move",
            description: "Reschedule a calendar event to a new date/time. Preserves duration unless new end time specified.",
            inputSchema: schema(
                properties: [
                    "eventId": prop(.string, "Event ID to move"),
                    "date": prop(.string, "New date"),
                    "startTime": prop(.string, "New start time"),
                    "endTime": prop(.string, "New end time (optional, preserves duration)"),
                ],
                required: ["eventId"]
            )
        ),
        // Reminders read
        MCPToolDefinition(
            name: "reminders_list",
            description: "List reminders. Defaults to incomplete reminders across all lists.",
            inputSchema: schema(properties: [
                "list": prop(.string, "Filter by list name"),
                "includeCompleted": prop(.boolean, "Include completed reminders"),
                "due": prop(.string, "Filter by due date: 'today', 'tomorrow', ISO date"),
                "limit": prop(.integer, "Max reminders"),
            ])
        ),
        MCPToolDefinition(
            name: "reminders_overdue",
            description: "Get all overdue (past due, incomplete) reminders.",
            inputSchema: schema(properties: [:])
        ),
        MCPToolDefinition(
            name: "reminders_lists",
            description: "List all reminder lists with incomplete item counts.",
            inputSchema: schema(properties: [:])
        ),
        // Reminders write
        MCPToolDefinition(
            name: "reminders_add",
            description: "Create a new reminder. Returns the created reminder.",
            inputSchema: schema(
                properties: [
                    "title": prop(.string, "Reminder title"),
                    "list": prop(.string, "List name (uses default if omitted)"),
                    "due": prop(.string, "Due date: 'today', 'tomorrow', ISO date"),
                    "priority": prop(.string, "Priority: 'high', 'medium', 'low'"),
                    "notes": prop(.string, "Notes"),
                ],
                required: ["title"]
            )
        ),
        MCPToolDefinition(
            name: "reminders_complete",
            description: "Mark a reminder as complete. Can match by title substring (case-insensitive) or by ID.",
            inputSchema: schema(properties: [
                "title": prop(.string, "Title substring to match (fuzzy)"),
                "id": prop(.string, "Reminder ID (exact match, alternative to title)"),
            ])
        ),
        MCPToolDefinition(
            name: "reminders_delete",
            description: "Delete a reminder by its ID.",
            inputSchema: schema(properties: ["id": prop(.string, "Reminder ID")], required: ["id"])
        ),
        MCPToolDefinition(
            name: "reminders_move",
            description: "Move a reminder to a different list. Matches by title substring.",
            inputSchema: schema(
                properties: [
                    "title": prop(.string, "Title substring to match"),
                    "toList": prop(.string, "Target list name"),
                ],
                required: ["title", "toList"]
            )
        ),
        // Contacts
        MCPToolDefinition(
            name: "contacts_search",
            description: "Search contacts by name, email, or phone number. Returns full contact details.",
            inputSchema: schema(properties: [
                "query": prop(.string, "Search query"),
                "limit": prop(.integer, "Max results"),
            ], required: ["query"])
        ),
        MCPToolDefinition(
            name: "contacts_birthdays",
            description: "Get contacts with upcoming birthdays.",
            inputSchema: schema(properties: [
                "days": prop(.integer, "Days ahead to search (default: 30)"),
            ])
        ),
        // System
        MCPToolDefinition(
            name: "focus_status",
            description: "Check if macOS Focus/Do Not Disturb mode is currently enabled.",
            inputSchema: schema(properties: [:])
        ),
        MCPToolDefinition(
            name: "notify_send",
            description: "Send a macOS notification to the user.",
            inputSchema: schema(
                properties: [
                    "title": prop(.string, "Notification title"),
                    "body": prop(.string, "Notification body"),
                    "subtitle": prop(.string, "Notification subtitle"),
                    "sound": prop(.string, "Sound name: 'default', 'Ping', etc."),
                ],
                required: ["title", "body"]
            )
        ),
    ]

    // MARK: - Schema Helpers

    private enum SchemaType: String {
        case string, integer, boolean
    }

    private static func prop(_ type: SchemaType, _ description: String) -> [String: Any] {
        ["type": type.rawValue, "description": description]
    }

    private static func schema(properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
        var s: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty { s["required"] = required }
        return s
    }
}
