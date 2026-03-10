import Testing
import Foundation
@testable import MacKitCore

@Suite("MCPTypes")
struct MCPTypesTests {

    // MARK: - JSONRPCRequest Parsing

    @Suite("JSONRPCRequest")
    struct JSONRPCRequestTests {

        @Test("parses valid JSON-RPC request with all fields")
        func parseValidRequest() throws {
            let json = """
            {"jsonrpc":"2.0","id":42,"method":"tools/list","params":{"cursor":"abc"}}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.jsonrpc == "2.0")
            #expect(request.id?.intValue == 42)
            #expect(request.method == "tools/list")
            #expect(request.params?["cursor"]?.stringValue == "abc")
        }

        @Test("parses request with string id")
        func parseStringId() throws {
            let json = """
            {"jsonrpc":"2.0","id":"req-42","method":"initialize"}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.id?.stringValue == "req-42")
            #expect(request.method == "initialize")
        }

        @Test("parses request without params")
        func parseNoParams() throws {
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"tools/list"}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.params == nil)
        }

        @Test("defaults method to empty string when missing")
        func parseMissingMethod() throws {
            let json = """
            {"jsonrpc":"2.0","id":1}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.method == "")
        }

        @Test("defaults jsonrpc to 2.0 when missing")
        func parseMissingJsonrpc() throws {
            let json = """
            {"id":1,"method":"test"}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.jsonrpc == "2.0")
        }

        @Test("id is nil for notification (no id field)")
        func parseNotification() throws {
            let json = """
            {"jsonrpc":"2.0","method":"notifications/initialized"}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.id == nil)
            #expect(request.method == "notifications/initialized")
        }

        @Test("throws on invalid JSON data")
        func parseInvalidJSON() throws {
            let data = Data("not json at all".utf8)
            #expect(throws: (any Error).self) {
                try JSONRPCRequest(from: data)
            }
        }

        @Test("parses nested params with object arguments")
        func parseNestedParams() throws {
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"calendar_list","arguments":{"from":"today","limit":5}}}
            """
            let request = try JSONRPCRequest(from: Data(json.utf8))
            #expect(request.params?["name"]?.stringValue == "calendar_list")

            if case .object(let args) = request.params?["arguments"] {
                #expect(args["from"]?.stringValue == "today")
                #expect(args["limit"]?.intValue == 5)
            } else {
                Issue.record("Expected arguments to be an object")
            }
        }
    }

    // MARK: - JSONRPCResponse Serialization

    @Suite("JSONRPCResponse")
    struct JSONRPCResponseTests {

        @Test("serializes result response")
        func serializeResultResponse() throws {
            let response = JSONRPCResponse(id: .int(1), result: ["tools": []] as [String: Any])
            let data = try response.serialize()
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            #expect(json["jsonrpc"] as? String == "2.0")
            #expect(json["id"] as? Int == 1)
            #expect(json["result"] != nil)
            #expect(json["error"] == nil)
        }

        @Test("serializes error response")
        func serializeErrorResponse() throws {
            let response = JSONRPCResponse(id: .int(1), error: .methodNotFound)
            let data = try response.serialize()
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            #expect(json["jsonrpc"] as? String == "2.0")
            #expect(json["id"] as? Int == 1)
            let error = json["error"] as? [String: Any]
            #expect(error?["code"] as? Int == -32601)
            #expect(error?["message"] as? String == "Method not found")
            #expect(json["result"] == nil)
        }

        @Test("serializes with null id")
        func serializeNullId() throws {
            let response = JSONRPCResponse(id: nil, error: .internalError("boom"))
            let data = try response.serialize()
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            #expect(json["id"] is NSNull)
            let error = json["error"] as? [String: Any]
            #expect(error?["code"] as? Int == -32603)
            #expect(error?["message"] as? String == "boom")
        }

        @Test("serializes with string id")
        func serializeStringId() throws {
            let response = JSONRPCResponse(id: .string("req-7"), result: ["ok": true] as [String: Any])
            let data = try response.serialize()
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            #expect(json["id"] as? String == "req-7")
        }

        @Test("serializes empty result when result is nil and no error")
        func serializeNilResultNoError() throws {
            // Construct via the result init with an empty dict to simulate nil result path
            let response = JSONRPCResponse(id: .int(1), result: [String: Any]())
            let data = try response.serialize()
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

            #expect(json["result"] != nil)
        }
    }

    // MARK: - JSONValue Round-Trip

    @Suite("JSONValue")
    struct JSONValueTests {

        @Test("string round-trip")
        func stringRoundTrip() {
            let value = JSONValue(from: "hello" as Any)
            #expect(value.stringValue == "hello")
            #expect(value.toAny() as? String == "hello")
        }

        @Test("int round-trip")
        func intRoundTrip() {
            let value = JSONValue(from: 42 as Any)
            #expect(value.intValue == 42)
            #expect(value.toAny() as? Int == 42)
        }

        @Test("double round-trip")
        func doubleRoundTrip() {
            let value = JSONValue(from: 3.14 as Any)
            if case .double(let v) = value {
                #expect(abs(v - 3.14) < 0.001)
            } else {
                Issue.record("Expected .double variant")
            }
            #expect(value.toAny() as? Double == 3.14)
        }

        @Test("bool round-trip")
        func boolRoundTrip() {
            let value = JSONValue(from: true as Any)
            #expect(value.boolValue == true)
            #expect(value.toAny() as? Bool == true)
        }

        @Test("array round-trip")
        func arrayRoundTrip() {
            let value = JSONValue(from: ["a", "b"] as Any)
            #expect(value.arrayValue?.count == 2)
            #expect(value.arrayValue?[0].stringValue == "a")
            #expect(value.arrayValue?[1].stringValue == "b")
            let anyArray = value.toAny() as? [Any]
            #expect(anyArray?.count == 2)
        }

        @Test("object round-trip")
        func objectRoundTrip() {
            let value = JSONValue(from: ["key": "val"] as Any)
            if case .object(let dict) = value {
                #expect(dict["key"]?.stringValue == "val")
            } else {
                Issue.record("Expected .object variant")
            }
            let anyDict = value.toAny() as? [String: Any]
            #expect(anyDict?["key"] as? String == "val")
        }

        @Test("null round-trip")
        func nullRoundTrip() {
            let value = JSONValue(from: NSNull() as Any)
            if case .null = value {
                // expected
            } else {
                Issue.record("Expected .null variant")
            }
            #expect(value.toAny() is NSNull)
        }

        @Test("unknown type becomes null")
        func unknownTypeBecomesNull() {
            struct Custom {}
            let value = JSONValue(from: Custom() as Any)
            if case .null = value {
                // expected
            } else {
                Issue.record("Expected unknown type to become .null")
            }
        }

        @Test("stringValue returns nil for non-string")
        func stringValueNilForInt() {
            let value = JSONValue.int(42)
            #expect(value.stringValue == nil)
        }

        @Test("intValue returns nil for non-int")
        func intValueNilForString() {
            let value = JSONValue.string("hello")
            #expect(value.intValue == nil)
        }

        @Test("boolValue returns nil for non-bool")
        func boolValueNilForString() {
            let value = JSONValue.string("true")
            #expect(value.boolValue == nil)
        }

        @Test("arrayValue returns nil for non-array")
        func arrayValueNilForString() {
            let value = JSONValue.string("[]")
            #expect(value.arrayValue == nil)
        }
    }

    // MARK: - MCPToolResult

    @Suite("MCPToolResult")
    struct MCPToolResultTests {

        @Test("toDict for success result")
        func successToDict() {
            let result = MCPToolResult(text: "some output")
            let dict = result.toDict()

            let content = dict["content"] as? [[String: String]]
            #expect(content?.count == 1)
            #expect(content?[0]["type"] == "text")
            #expect(content?[0]["text"] == "some output")
            #expect(dict["isError"] == nil)
        }

        @Test("toDict for error result")
        func errorToDict() {
            let result = MCPToolResult(text: "something went wrong", isError: true)
            let dict = result.toDict()

            let content = dict["content"] as? [[String: String]]
            #expect(content?.count == 1)
            #expect(content?[0]["type"] == "text")
            #expect(content?[0]["text"] == "something went wrong")
            #expect(dict["isError"] as? Bool == true)
        }

        @Test("default isError is false")
        func defaultIsError() {
            let result = MCPToolResult(text: "ok")
            #expect(result.isError == false)
        }
    }

    // MARK: - JSONRPCError

    @Suite("JSONRPCError")
    struct JSONRPCErrorTests {

        @Test("methodNotFound has correct code and message")
        func methodNotFound() {
            let err = JSONRPCError.methodNotFound
            #expect(err.code == -32601)
            #expect(err.message == "Method not found")
        }

        @Test("invalidParams has correct code and message")
        func invalidParams() {
            let err = JSONRPCError.invalidParams
            #expect(err.code == -32602)
            #expect(err.message == "Invalid params")
        }

        @Test("internalError has correct code and custom message")
        func internalError() {
            let err = JSONRPCError.internalError("disk full")
            #expect(err.code == -32603)
            #expect(err.message == "disk full")
        }
    }

    // MARK: - MCPToolDefinition

    @Suite("MCPToolDefinition")
    struct MCPToolDefinitionTests {

        @Test("toDict includes all fields")
        func toDict() {
            let tool = MCPToolDefinition(
                name: "test_tool",
                description: "A test tool",
                inputSchema: ["type": "object", "properties": [:]] as [String: Any]
            )
            let dict = tool.toDict()
            #expect(dict["name"] as? String == "test_tool")
            #expect(dict["description"] as? String == "A test tool")
            #expect(dict["inputSchema"] != nil)
        }
    }
}
