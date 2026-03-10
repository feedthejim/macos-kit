import Foundation

/// Types that support field selection for JSON output.
/// Provides a static list of valid field names (including optional fields that may be nil).
public protocol FieldSelectable {
    static var availableFields: [String] { get }
}

public enum FieldSelection: Sendable {
    /// Select specific fields from a FieldSelectable value, validating against known fields.
    public static func select<T: Encodable & FieldSelectable>(fields: [String], from value: T) throws -> String {
        if !fields.isEmpty {
            try validateFields(fields, available: T.availableFields)
        }
        return try selectFromEncoded(fields: fields, value: value)
    }

    /// Select specific fields from an array of FieldSelectable values.
    public static func select<T: Encodable & FieldSelectable>(fields: [String], from values: [T]) throws -> String {
        if !fields.isEmpty {
            try validateFields(fields, available: T.availableFields)
        }
        return try selectFromEncoded(fields: fields, value: values)
    }

    /// Select specific fields from any Encodable (validates against encoded keys).
    public static func select<T: Encodable>(fields: [String], from value: T) throws -> String {
        try selectFromEncoded(fields: fields, value: value)
    }

    // MARK: - Private

    private static func validateFields(_ fields: [String], available: [String]) throws {
        for field in fields {
            if !available.contains(field) {
                throw MacKitError.invalidField(name: field, available: available.sorted())
            }
        }
    }

    private static func selectFromEncoded<T: Encodable>(fields: [String], value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)

        if let array = json as? [[String: Any]] {
            let filtered = array.map { filterDict($0, fields: fields) }
            return try serialize(filtered)
        } else if let dict = json as? [String: Any] {
            let filtered = filterDict(dict, fields: fields)
            return try serialize(filtered)
        }

        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func filterDict(_ dict: [String: Any], fields: [String]) -> [String: Any] {
        guard !fields.isEmpty else { return dict }
        return dict.filter { fields.contains($0.key) }
    }

    private static func serialize(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
