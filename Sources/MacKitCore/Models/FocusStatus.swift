import Foundation

public struct FocusStatus: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let mode: String?

    public init(isEnabled: Bool, mode: String? = nil) {
        self.isEnabled = isEnabled
        self.mode = mode
    }
}

extension FocusStatus: TextRepresentable {
    public var textSummary: String {
        if isEnabled {
            return "\u{1F507} \(mode ?? "Do Not Disturb") (on)"
        }
        return "Focus: off"
    }
    public var textDetail: String { textSummary }
}
