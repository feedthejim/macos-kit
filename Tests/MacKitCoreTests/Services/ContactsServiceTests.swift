import Testing
import Foundation
@testable import MacKitCore

@Suite("ContactsService")
struct ContactsServiceTests {
    private func contact(
        given: String,
        family: String,
        emails: [String] = [],
        phones: [String] = [],
        org: String? = nil,
        birthday: String? = nil
    ) -> Contact {
        Contact(
            id: UUID().uuidString,
            givenName: given,
            familyName: family,
            organizationName: org,
            emailAddresses: emails,
            phoneNumbers: phones,
            birthday: birthday
        )
    }

    // MARK: - search

    @Test("Search by first name case-insensitive")
    func searchByFirstName() async throws {
        let mock = MockContactsService()
        mock.mockContacts = [
            contact(given: "John", family: "Appleseed"),
            contact(given: "Johnny", family: "Cash"),
            contact(given: "Jane", family: "Doe"),
        ]

        let results = try await mock.search(query: "john", limit: nil)
        #expect(results.count == 2)
    }

    @Test("Search by email")
    func searchByEmail() async throws {
        let mock = MockContactsService()
        mock.mockContacts = [
            contact(given: "John", family: "Doe", emails: ["john@example.com"]),
            contact(given: "Jane", family: "Doe", emails: ["jane@example.com"]),
        ]

        let results = try await mock.search(query: "john@", limit: nil)
        #expect(results.count == 1)
        #expect(results[0].givenName == "John")
    }

    @Test("Search by phone number")
    func searchByPhone() async throws {
        let mock = MockContactsService()
        mock.mockContacts = [
            contact(given: "John", family: "Doe", phones: ["555-123-4567"]),
            contact(given: "Jane", family: "Doe", phones: ["555-987-6543"]),
        ]

        let results = try await mock.search(query: "555-123", limit: nil)
        #expect(results.count == 1)
    }

    @Test("Search with no matches returns empty")
    func searchNoMatches() async throws {
        let mock = MockContactsService()
        mock.mockContacts = [contact(given: "John", family: "Doe")]

        let results = try await mock.search(query: "zzz", limit: nil)
        #expect(results.isEmpty)
    }

    @Test("Search respects limit")
    func searchWithLimit() async throws {
        let mock = MockContactsService()
        mock.mockContacts = [
            contact(given: "John", family: "A"),
            contact(given: "John", family: "B"),
            contact(given: "John", family: "C"),
        ]

        let results = try await mock.search(query: "john", limit: 2)
        #expect(results.count == 2)
    }

    // MARK: - Permission handling

    @Test("Permission denied throws correct error")
    func permissionDenied() async {
        let mock = MockContactsService()
        mock.shouldDenyPermission = true

        await #expect(throws: MacKitError.self) {
            try await mock.search(query: "test", limit: nil)
        }
    }

    // MARK: - Contact model

    @Test("Full name combines given and family")
    func fullName() {
        let c = contact(given: "John", family: "Doe")
        #expect(c.fullName == "John Doe")
    }

    @Test("Full name handles empty family name")
    func fullNameNoFamily() {
        let c = contact(given: "Madonna", family: "")
        #expect(c.fullName == "Madonna")
    }
}
