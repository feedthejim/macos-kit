import Foundation

public protocol ContactsServiceProtocol: Sendable {
    func requestAccess() async throws
    func search(query: String, limit: Int?, fields: Set<String>?) async throws -> [Contact]
    func upcomingBirthdays(withinDays: Int, fields: Set<String>?) async throws -> [Contact]
    func groups() async throws -> [ContactGroup]
}

public extension ContactsServiceProtocol {
    func search(query: String, limit: Int?) async throws -> [Contact] {
        try await search(query: query, limit: limit, fields: nil)
    }

    func upcomingBirthdays(withinDays: Int) async throws -> [Contact] {
        try await upcomingBirthdays(withinDays: withinDays, fields: nil)
    }
}
