import Testing
import Foundation
@testable import MacKitCore

@Suite("Contact Model")
struct ContactTests {
    // MARK: - Codable round-trip

    @Test("Encodes and decodes without data loss")
    func codableRoundTrip() throws {
        let original = Contact(
            id: "contact-1",
            givenName: "John",
            familyName: "Appleseed",
            organizationName: "Apple Inc.",
            emailAddresses: ["john@apple.com", "john@gmail.com"],
            phoneNumbers: ["+1-555-123-4567"],
            birthday: "Mar 15"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Contact.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - fullName

    @Test("Full name combines given and family")
    func fullName() {
        let c = Contact(id: "1", givenName: "John", familyName: "Doe")
        #expect(c.fullName == "John Doe")
    }

    @Test("Full name with empty given")
    func fullNameEmptyGiven() {
        let c = Contact(id: "1", givenName: "", familyName: "Doe")
        #expect(c.fullName == "Doe")
    }

    @Test("Full name with empty family")
    func fullNameEmptyFamily() {
        let c = Contact(id: "1", givenName: "Madonna", familyName: "")
        #expect(c.fullName == "Madonna")
    }

    // MARK: - TextRepresentable

    @Test("Text summary shows name and email")
    func textSummary() {
        let c = Contact(
            id: "1",
            givenName: "John",
            familyName: "Doe",
            emailAddresses: ["john@example.com"]
        )
        #expect(c.textSummary.contains("John Doe"))
        #expect(c.textSummary.contains("john@example.com"))
    }

    @Test("Text summary shows phone")
    func textSummaryPhone() {
        let c = Contact(
            id: "1",
            givenName: "Jane",
            familyName: "Doe",
            phoneNumbers: ["555-1234"]
        )
        #expect(c.textSummary.contains("555-1234"))
    }

    @Test("Text summary shows organization")
    func textSummaryOrg() {
        let c = Contact(
            id: "1",
            givenName: "John",
            familyName: "Doe",
            organizationName: "Acme Corp"
        )
        #expect(c.textSummary.contains("Acme Corp"))
    }

    // MARK: - TableRepresentable

    @Test("Table headers match row count")
    func tableStructure() {
        let c = Contact(id: "1", givenName: "John", familyName: "Doe")
        #expect(Contact.tableHeaders.count == c.tableRow.count)
    }

    // MARK: - FieldSelectable

    @Test("Available fields includes all properties")
    func availableFields() {
        let fields = Contact.availableFields
        #expect(fields.contains("givenName"))
        #expect(fields.contains("familyName"))
        #expect(fields.contains("emailAddresses"))
        #expect(fields.contains("phoneNumbers"))
        #expect(fields.contains("organizationName"))
        #expect(fields.contains("birthday"))
    }
}
