import Foundation

public enum PermissionDomain: String, Sendable {
    case calendars
    case reminders
    case contacts
    case notifications
    case mail

    public var displayName: String {
        switch self {
        case .calendars: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .notifications: "Notifications"
        case .mail: "Mail"
        }
    }

    public var settingsPath: String {
        switch self {
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .notifications: "Notifications"
        case .mail: "Automation"
        }
    }
}

public enum MacKitError: LocalizedError, Sendable, Equatable {
    case permissionDenied(PermissionDomain)
    case permissionNotDetermined(PermissionDomain)
    case notFound(String)
    case noData(String)
    case invalidDateFormat(String)
    case invalidField(name: String, available: [String])
    case invalidJQExpression(String)
    case appNotRunning(String)
    case systemError(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let domain):
            return """
                Access denied: \(domain.displayName) permission is required.
                Grant access in: System Settings > Privacy & Security > \(domain.settingsPath)
                """
        case .permissionNotDetermined(let domain):
            return """
                \(domain.displayName) access has not been granted yet.
                A permission dialog should appear. If it doesn't, grant access in:
                System Settings > Privacy & Security > \(domain.settingsPath)
                """
        case .notFound(let what):
            return "Not found: \(what)"
        case .noData(let what):
            return "No data available: \(what)"
        case .invalidDateFormat(let input):
            return "Invalid date: '\(input)'. Use ISO 8601 (YYYY-MM-DD) or natural dates (today, tomorrow, monday)"
        case .invalidField(let name, let available):
            return "Unknown field '\(name)'. Available fields: \(available.joined(separator: ", "))"
        case .invalidJQExpression(let expr):
            return "Invalid jq expression: '\(expr)'"
        case .appNotRunning(let app):
            return "\(app) is not running and could not be launched. Open \(app) and try again."
        case .systemError(let msg):
            return msg
        }
    }
}
