import Foundation

public struct ReminderList: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let count: Int
    public let color: String?

    public init(id: String, title: String, count: Int = 0, color: String? = nil) {
        self.id = id
        self.title = title
        self.count = count
        self.color = color
    }
}

extension ReminderList: TextRepresentable {
    public var textSummary: String {
        "  \(title.padding(toLength: 16, withPad: " ", startingAt: 0))\(count) item\(count == 1 ? "" : "s")"
    }
    public var textDetail: String { textSummary }
}

extension ReminderList: TableRepresentable {
    public static var tableHeaders: [String] { ["List", "Items"] }
    public var tableRow: [String] { [title, "\(count)"] }
}
