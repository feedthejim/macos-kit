import Foundation

public enum MeetingURLExtractor: Sendable {
    // Patterns for known meeting services
    private static let patterns: [String] = [
        #"https?://[\w.-]*zoom\.us/[^\s]+"#,
        #"https?://meet\.google\.com/[^\s]+"#,
        #"https?://teams\.microsoft\.com/[^\s]+"#,
        #"https?://[\w.-]*webex\.com/[^\s]+"#,
        #"https?://app\.around\.co/[^\s]+"#,
        #"https?://[\w.-]*whereby\.com/[^\s]+"#,
        #"https?://[\w.-]*gather\.town/[^\s]+"#,
    ]

    /// Extract a meeting URL from a single text field
    public static func extract(from text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range) {
                    let matchRange = Range(match.range, in: text)!
                    return String(text[matchRange])
                }
            }
        }

        return nil
    }

    /// Extract meeting URL checking location first, then notes, then url field
    public static func extract(fromLocation location: String?, notes: String?, url: String?) -> String? {
        extract(from: location) ?? extract(from: notes) ?? extract(from: url)
    }
}
