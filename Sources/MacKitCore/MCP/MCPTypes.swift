import Foundation

// MARK: - JSON-RPC 2.0

public struct JSONRPCRequest: Sendable {
    public let jsonrpc: String
    public let id: JSONValue?
    public let method: String
    public let params: [String: JSONValue]?

    public init(from data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        self.jsonrpc = json["jsonrpc"] as? String ?? "2.0"
        self.id = (json["id"]).map { JSONValue(from: $0) }
        self.method = json["method"] as? String ?? ""
        if let p = json["params"] as? [String: Any] {
            self.params = p.mapValues { JSONValue(from: $0) }
        } else {
            self.params = nil
        }
    }
}

public struct JSONRPCResponse: @unchecked Sendable {
    public let id: JSONValue?
    public let result: Any?
    public let error: JSONRPCError?

    public init(id: JSONValue?, result: Any) {
        self.id = id; self.result = result; self.error = nil
    }
    public init(id: JSONValue?, error: JSONRPCError) {
        self.id = id; self.result = nil; self.error = error
    }

    public func serialize() throws -> Data {
        var dict: [String: Any] = ["jsonrpc": "2.0"]
        dict["id"] = id?.toAny() ?? NSNull()
        if let error {
            dict["error"] = ["code": error.code, "message": error.message]
        } else if let result {
            dict["result"] = result
        } else {
            dict["result"] = [String: Any]()
        }
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }
}

public struct JSONRPCError: Sendable {
    public let code: Int
    public let message: String

    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static func internalError(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: msg)
    }
}

// MARK: - Type-erased JSON value

public enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .int(i)
        case let d as Double: self = .double(d)
        case let a as [Any]: self = .array(a.map { JSONValue(from: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSONValue(from: $0) })
        default: self = .null
        }
    }

    public func toAny() -> Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        case .null: return NSNull()
        }
    }

    public var stringValue: String? {
        if case .string(let v) = self { return v } else { return nil }
    }
    public var intValue: Int? {
        if case .int(let v) = self { return v } else { return nil }
    }
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v } else { return nil }
    }
    public var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v } else { return nil }
    }
}

// MARK: - MCP-specific types

public struct MCPToolDefinition: @unchecked Sendable {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]

    public init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name; self.description = description; self.inputSchema = inputSchema
    }

    public func toDict() -> [String: Any] {
        ["name": name, "description": description, "inputSchema": inputSchema]
    }
}

public struct MCPToolResult: Sendable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text; self.isError = isError
    }

    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "content": [["type": "text", "text": text]]
        ]
        if isError { dict["isError"] = true }
        return dict
    }
}
