import Foundation
@testable import MacKitCore

final class MockContactsService: ContactsServiceProtocol, @unchecked Sendable {
    var mockContacts: [Contact] = []
    var mockGroups: [ContactGroup] = []
    var shouldDenyPermission = false

    func requestAccess() async throws {
        if shouldDenyPermission {
            throw MacKitError.permissionDenied(.contacts)
        }
    }

    func search(query: String, limit: Int?) async throws -> [Contact] {
        try await requestAccess()
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

    func upcomingBirthdays(withinDays days: Int) async throws -> [Contact] {
        try await requestAccess()
        return mockContacts.filter { $0.birthday != nil }
    }

    func groups() async throws -> [ContactGroup] {
        try await requestAccess()
        return mockGroups
    }
}
