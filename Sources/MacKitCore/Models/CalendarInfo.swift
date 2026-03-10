import Foundation

public struct CalendarInfo: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let source: String
    public let color: String?
    public let isSubscribed: Bool

    public init(
        id: String,
        title: String,
        source: String,
        color: String? = nil,
        isSubscribed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.color = color
        self.isSubscribed = isSubscribed
    }
}

extension CalendarInfo: TextRepresentable {
    public var textSummary: String {
        let colorStr = color.map { "  \($0)" } ?? ""
        return "  \(title.padding(toLength: 16, withPad: " ", startingAt: 0))(\(source))\(colorStr)"
    }

    public var textDetail: String { textSummary }
}

extension CalendarInfo: TableRepresentable {
    public static var tableHeaders: [String] { ["Name", "Source", "Color"] }
    public var tableRow: [String] { [title, source, color ?? "-"] }
}
