import Testing
import Foundation
@testable import MacKitCore

@Suite("MacKitError")
struct MacKitErrorTests {
    @Test("Permission denied for calendars mentions System Settings")
    func calendarPermissionDenied() {
        let error = MacKitError.permissionDenied(.calendars)
        let desc = error.errorDescription!
        #expect(desc.contains("Calendar"))
        #expect(desc.contains("System Settings"))
        #expect(desc.contains("Privacy & Security"))
    }

    @Test("Permission denied for contacts mentions Contacts")
    func contactsPermissionDenied() {
        let error = MacKitError.permissionDenied(.contacts)
        let desc = error.errorDescription!
        #expect(desc.contains("Contacts"))
        #expect(desc.contains("System Settings"))
    }

    @Test("Permission denied for reminders mentions Reminders")
    func remindersPermissionDenied() {
        let error = MacKitError.permissionDenied(.reminders)
        let desc = error.errorDescription!
        #expect(desc.contains("Reminders"))
    }

    @Test("Invalid date format shows the input")
    func invalidDateFormat() {
        let error = MacKitError.invalidDateFormat("garbage")
        let desc = error.errorDescription!
        #expect(desc.contains("garbage"))
        #expect(desc.contains("YYYY-MM-DD"))
    }

    @Test("Invalid field shows available fields")
    func invalidField() {
        let error = MacKitError.invalidField(name: "foo", available: ["name", "value"])
        let desc = error.errorDescription!
        #expect(desc.contains("foo"))
        #expect(desc.contains("name"))
        #expect(desc.contains("value"))
    }
}
