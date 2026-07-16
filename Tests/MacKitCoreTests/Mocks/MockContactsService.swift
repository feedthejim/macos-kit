import Foundation
@testable import MacKitCore

final class MockContactsService: ContactsServiceProtocol, @unchecked Sendable {
    var mockContacts: [Contact] = []
    var mockGroups: [ContactGroup] = []
    var shouldDenyPermission = false
    var lastRequestedFields: Set<String>?

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.contacts)
        }
    }

    func search(query: String, limit: Int?, fields: Set<String>?) async throws -> [Contact] {
        try await requestAccess()
        lastRequestedFields = fields
        let lowerQuery = query.lowercased()
        var results = mockContacts.filter {
            $0.givenName.lowercased().contains(lowerQuery)
            || $0.familyName.lowercased().contains(lowerQuery)
            || $0.emailAddresses.contains { $0.lowercased().contains(lowerQuery) }
            || $0.phoneNumbers.contains { $0.contains(lowerQuery) }
        }
        if let limit { results = Array(results.prefix(limit)) }
        return results
    }

    func upcomingBirthdays(withinDays days: Int, fields: Set<String>?) async throws -> [Contact] {
        try await requestAccess()
        lastRequestedFields = fields
        return mockContacts.filter { $0.birthday != nil }
    }

    func groups() async throws -> [ContactGroup] {
        try await requestAccess()
        return mockGroups
    }
}
