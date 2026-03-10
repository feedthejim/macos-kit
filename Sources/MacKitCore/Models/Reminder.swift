import Foundation

public enum ReminderPriority: Int, Codable, Sendable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    public init(fromEKPriority priority: Int) {
        switch priority {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var label: String {
        switch self {
        case .none: "none"
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        }
    }
}

public struct Reminder: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "id", "title", "dueDate", "isCompleted", "completionDate",
        "priority", "listName", "notes",
    ]

    public let id: String
    public let title: String
    public let dueDate: Date?
    public let isCompleted: Bool
    public let completionDate: Date?
    public let priority: ReminderPriority
    public let listName: String
    public let notes: String?

    public init(
        id: String,
        title: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        priority: ReminderPriority = .none,
        listName: String = "",
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.priority = priority
        self.listName = listName
        self.notes = notes
    }
}

extension Reminder: TextRepresentable {
    public var textSummary: String {
        let checkbox = isCompleted ? "☑" : "☐"
        let dueStr: String
        if let dueDate {
            if dueDate < Date() && !isCompleted {
                let days = Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
                dueStr = "  \(days) day\(days == 1 ? "" : "s") overdue"
            } else {
                dueStr = "  due \(RelativeTime.format(dueDate))"
            }
        } else {
            dueStr = ""
        }
        return "  \(checkbox) \(title)\(dueStr)"
    }

    public var textDetail: String {
        var lines = [title]
        lines.append("  List:     \(listName)")
        if let dueDate { lines.append("  Due:      \(dueDate.formatted())") }
        if priority != .none { lines.append("  Priority: \(priority.label)") }
        if isCompleted { lines.append("  Status:   completed") }
        if let notes, !notes.isEmpty { lines.append("  Notes:    \(notes.prefix(200))") }
        return lines.joined(separator: "\n")
    }
}

extension Reminder: TableRepresentable {
    public static var tableHeaders: [String] { ["Status", "Title", "Due", "List", "Priority"] }
    public var tableRow: [String] {
        let status = isCompleted ? "done" : "todo"
        let due = dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "-"
        return [status, title, due, listName, priority.label]
    }
}
