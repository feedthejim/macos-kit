import Testing
import Foundation
@testable import MacKitCore

@Suite("MCPTools")
struct MCPToolsTests {

    // MARK: - Tool Count

    @Test("all 29 tools are defined")
    func allToolsCount() {
        #expect(MCPTools.allTools.count == 29)
    }

    // MARK: - Tool Metadata Validation

    @Test("every tool has a non-empty name")
    func allToolsHaveNames() {
        for tool in MCPTools.allTools {
            #expect(!tool.name.isEmpty, "Tool should have a non-empty name")
        }
    }

    @Test("every tool has a non-empty description")
    func allToolsHaveDescriptions() {
        for tool in MCPTools.allTools {
            #expect(!tool.description.isEmpty, "Tool '\(tool.name)' should have a non-empty description")
        }
    }

    @Test("tool names are unique")
    func toolNamesAreUnique() {
        let names = MCPTools.allTools.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "Tool names should be unique, found duplicates: \(names.filter { name in names.filter { $0 == name }.count > 1 })")
    }

    // MARK: - Schema Validation

    @Test("every tool has inputSchema with type object")
    func allToolsHaveObjectSchema() {
        for tool in MCPTools.allTools {
            let schemaType = tool.inputSchema["type"] as? String
            #expect(schemaType == "object", "Tool '\(tool.name)' inputSchema should have type 'object', got '\(schemaType ?? "nil")'")
        }
    }

    @Test("every tool has properties in inputSchema")
    func allToolsHaveProperties() {
        for tool in MCPTools.allTools {
            let properties = tool.inputSchema["properties"]
            #expect(properties != nil, "Tool '\(tool.name)' inputSchema should have 'properties' key")
        }
    }

    @Test("required fields are a subset of properties for each tool")
    func requiredFieldsAreSubsetOfProperties() {
        for tool in MCPTools.allTools {
            let properties = tool.inputSchema["properties"] as? [String: Any] ?? [:]
            let required = tool.inputSchema["required"] as? [String] ?? []
            let propertyNames = Set(properties.keys)
            for field in required {
                #expect(propertyNames.contains(field), "Tool '\(tool.name)': required field '\(field)' is not in properties \(Array(propertyNames))")
            }
        }
    }

    // MARK: - Known Tool Required Fields

    @Test("calendar_create requires title, date, startTime, endTime")
    func calendarCreateRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "calendar_create" }
        #expect(tool != nil, "calendar_create tool should exist")
        let required = tool!.inputSchema["required"] as? [String] ?? []
        let expectedRequired: Set<String> = ["title", "date", "startTime", "endTime"]
        #expect(Set(required) == expectedRequired)
    }

    @Test("calendar_delete requires eventId")
    func calendarDeleteRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "calendar_delete" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["eventId"]))
    }

    @Test("calendar_update requires eventId")
    func calendarUpdateRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "calendar_update" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["eventId"]))
    }

    @Test("calendar_move requires eventId")
    func calendarMoveRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "calendar_move" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["eventId"]))
    }

    @Test("reminders_add requires title")
    func remindersAddRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "reminders_add" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["title"]))
    }

    @Test("reminders_delete requires id")
    func remindersDeleteRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "reminders_delete" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["id"]))
    }

    @Test("reminders_move requires title and toList")
    func remindersMoveRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "reminders_move" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["title", "toList"]))
    }

    @Test("contacts_search requires query")
    func contactsSearchRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "contacts_search" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["query"]))
    }

    @Test("notify_send requires title and body")
    func notifySendRequiredFields() {
        let tool = MCPTools.allTools.first { $0.name == "notify_send" }
        #expect(tool != nil)
        let required = tool!.inputSchema["required"] as? [String] ?? []
        #expect(Set(required) == Set(["title", "body"]))
    }

    // MARK: - Tools Without Required Fields

    @Test("read-only tools without required fields have no required key")
    func readOnlyToolsNoRequired() {
        let toolsWithoutRequired = [
            "calendar_list", "calendar_next", "calendar_free", "calendar_calendars",
            "reminders_list", "reminders_overdue", "reminders_lists",
            "reminders_complete", "contacts_birthdays", "focus_status"
        ]
        for name in toolsWithoutRequired {
            let tool = MCPTools.allTools.first { $0.name == name }
            #expect(tool != nil, "Tool '\(name)' should exist")
            let required = tool!.inputSchema["required"] as? [String]
            #expect(required == nil, "Tool '\(name)' should not have required fields, found: \(required ?? [])")
        }
    }

    // MARK: - All Expected Tool Names

    @Test("all expected tool names are present")
    func allExpectedToolNamesPresent() {
        let expectedNames: Set<String> = [
            "calendar_list", "calendar_next", "calendar_free", "calendar_calendars",
            "calendar_create", "calendar_delete", "calendar_update", "calendar_move",
            "reminders_list", "reminders_overdue", "reminders_lists",
            "reminders_add", "reminders_complete", "reminders_delete", "reminders_move",
            "contacts_search", "contacts_birthdays",
            "mail_list", "mail_search", "mail_read", "mail_mailboxes", "mail_accounts",
            "mail_send", "mail_mark_read", "mail_mark_unread", "mail_move", "mail_delete",
            "focus_status", "notify_send"
        ]
        let actualNames = Set(MCPTools.allTools.map(\.name))
        #expect(actualNames == expectedNames)
    }

    // MARK: - Property Type Validation

    @Test("each property in each tool has a type and description")
    func propertiesHaveTypeAndDescription() {
        for tool in MCPTools.allTools {
            let properties = tool.inputSchema["properties"] as? [String: Any] ?? [:]
            for (propName, propValue) in properties {
                let propDict = propValue as? [String: Any]
                #expect(propDict != nil, "Tool '\(tool.name)' property '\(propName)' should be a dictionary")
                #expect(propDict?["type"] as? String != nil, "Tool '\(tool.name)' property '\(propName)' should have a 'type'")
                #expect(propDict?["description"] as? String != nil, "Tool '\(tool.name)' property '\(propName)' should have a 'description'")
            }
        }
    }

    @Test("property types are valid JSON Schema types")
    func propertyTypesAreValid() {
        let validTypes: Set<String> = ["string", "integer", "boolean", "number", "array", "object"]
        for tool in MCPTools.allTools {
            let properties = tool.inputSchema["properties"] as? [String: Any] ?? [:]
            for (propName, propValue) in properties {
                let propDict = propValue as? [String: Any]
                let type = propDict?["type"] as? String ?? ""
                #expect(validTypes.contains(type), "Tool '\(tool.name)' property '\(propName)' has invalid type '\(type)'")
            }
        }
    }

    // MARK: - toDict Validation

    @Test("toDict contains name, description, and inputSchema for every tool")
    func toDictContainsAllFields() {
        for tool in MCPTools.allTools {
            let dict = tool.toDict()
            #expect(dict["name"] as? String == tool.name)
            #expect(dict["description"] as? String == tool.description)
            #expect(dict["inputSchema"] != nil, "Tool '\(tool.name)' toDict should include inputSchema")
        }
    }
}
