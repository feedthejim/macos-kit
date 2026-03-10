import Foundation

public enum OutputRenderer: Sendable {
    // MARK: - JSON

    public static func renderJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Text

    public static func renderText<T: TextRepresentable>(_ items: [T], emptyMessage: String = "(no results)") -> String {
        if items.isEmpty { return emptyMessage }
        return items.map(\.textSummary).joined(separator: "\n")
    }

    public static func renderText<T: TextRepresentable>(_ item: T) -> String {
        item.textDetail
    }

    // MARK: - Table

    public static func renderTable<T: TableRepresentable>(_ items: [T], emptyMessage: String = "(no results)") -> String {
        guard !items.isEmpty else { return emptyMessage }

        let headers = T.tableHeaders
        let rows = items.map(\.tableRow)

        // Calculate column widths
        var widths = headers.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }

        // Build table
        var lines: [String] = []

        let headerLine = headers.enumerated().map { i, h in
            h.padding(toLength: widths[i], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        lines.append(headerLine)

        let separator = widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ")
        lines.append(separator)

        for row in rows {
            let line = row.enumerated().map { i, cell in
                let width = i < widths.count ? widths[i] : cell.count
                return cell.padding(toLength: width, withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}
