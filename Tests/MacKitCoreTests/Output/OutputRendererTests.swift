import Testing
import Foundation
@testable import MacKitCore

// Test model for renderer tests
struct TestItem: Codable, Sendable, TextRepresentable, TableRepresentable, FieldSelectable {
    static let availableFields = ["name", "value"]

    let name: String
    let value: Int

    var textSummary: String { "\(name): \(value)" }
    var textDetail: String { "Name: \(name)\nValue: \(value)" }

    static var tableHeaders: [String] { ["Name", "Value"] }
    var tableRow: [String] { [name, "\(value)"] }
}

@Suite("OutputRenderer")
struct OutputRendererTests {
    // MARK: - JSON

    @Test("JSON renders valid JSON array")
    func jsonArray() throws {
        let items = [TestItem(name: "a", value: 1), TestItem(name: "b", value: 2)]
        let result = try OutputRenderer.renderJSON(items)
        // Should be parseable JSON
        let data = result.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        let array = try #require(parsed as? [[String: Any]])
        #expect(array.count == 2)
    }

    @Test("JSON renders single item as object")
    func jsonSingle() throws {
        let item = TestItem(name: "a", value: 1)
        let result = try OutputRenderer.renderJSON(item)
        let data = result.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        let dict = try #require(parsed as? [String: Any])
        #expect(dict["name"] as? String == "a")
    }

    @Test("JSON renders empty array")
    func jsonEmptyArray() throws {
        let items: [TestItem] = []
        let result = try OutputRenderer.renderJSON(items)
        #expect(result == "[\n\n]")
    }

    @Test("JSON is pretty-printed with sorted keys")
    func jsonPrettyPrinted() throws {
        let item = TestItem(name: "b", value: 1)
        let result = try OutputRenderer.renderJSON(item)
        // "name" should appear before "value" (sorted keys)
        let nameIndex = result.range(of: "\"name\"")!.lowerBound
        let valueIndex = result.range(of: "\"value\"")!.lowerBound
        #expect(nameIndex < valueIndex)
    }

    // MARK: - Text

    @Test("Text renders summaries for array")
    func textArray() {
        let items = [TestItem(name: "a", value: 1), TestItem(name: "b", value: 2)]
        let result = OutputRenderer.renderText(items)
        #expect(result.contains("a: 1"))
        #expect(result.contains("b: 2"))
    }

    @Test("Text renders detail for single item")
    func textSingle() {
        let item = TestItem(name: "a", value: 1)
        let result = OutputRenderer.renderText(item)
        #expect(result.contains("Name: a"))
        #expect(result.contains("Value: 1"))
    }

    @Test("Text renders empty message for empty array")
    func textEmpty() {
        let items: [TestItem] = []
        let result = OutputRenderer.renderText(items, emptyMessage: "(no items)")
        #expect(result == "(no items)")
    }

    // MARK: - Table

    @Test("Table renders header, separator, and rows")
    func tableBasic() {
        let items = [
            TestItem(name: "alpha", value: 1),
            TestItem(name: "beta", value: 2),
            TestItem(name: "gamma", value: 3),
        ]
        let result = OutputRenderer.renderTable(items)
        let lines = result.split(separator: "\n")
        #expect(lines.count == 5) // header + separator + 3 rows
        #expect(lines[0].contains("Name"))
        #expect(lines[0].contains("Value"))
        #expect(lines[1].contains("─"))
    }

    @Test("Table adapts column widths")
    func tableColumnWidths() {
        let items = [
            TestItem(name: "x", value: 1),
            TestItem(name: "longname", value: 2),
        ]
        let result = OutputRenderer.renderTable(items)
        let lines = result.split(separator: "\n")
        // All rows should have same length (padded)
        let headerLen = lines[0].count
        let row1Len = lines[2].count
        let row2Len = lines[3].count
        #expect(headerLen == row1Len)
        #expect(headerLen == row2Len)
    }

    @Test("Table renders empty message")
    func tableEmpty() {
        let items: [TestItem] = []
        let result = OutputRenderer.renderTable(items, emptyMessage: "(no items)")
        #expect(result == "(no items)")
    }
}

@Suite("FieldSelection")
struct FieldSelectionTests {
    @Test("Selects specific fields from JSON")
    func selectFields() throws {
        let item = TestItem(name: "a", value: 42)
        let result = try FieldSelection.select(fields: ["name"], from: item)
        let data = result.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict.keys.count == 1)
        #expect(dict["name"] as? String == "a")
    }

    @Test("Select multiple fields")
    func selectMultipleFields() throws {
        let item = TestItem(name: "a", value: 42)
        let result = try FieldSelection.select(fields: ["name", "value"], from: item)
        let data = result.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict.keys.count == 2)
    }

    @Test("Select from array")
    func selectFromArray() throws {
        let items = [TestItem(name: "a", value: 1), TestItem(name: "b", value: 2)]
        let result = try FieldSelection.select(fields: ["name"], from: items)
        let data = result.data(using: .utf8)!
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(array.count == 2)
        #expect(array[0].keys.count == 1)
    }

    @Test("Invalid field throws with available fields listed")
    func invalidField() {
        let item = TestItem(name: "a", value: 1)
        #expect(throws: MacKitError.self) {
            try FieldSelection.select(fields: ["foo"], from: item)
        }
    }

    @Test("Empty fields returns all fields")
    func emptyFieldsReturnsAll() throws {
        let item = TestItem(name: "a", value: 42)
        let result = try FieldSelection.select(fields: [], from: item)
        let data = result.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict.keys.count == 2)
    }
}
