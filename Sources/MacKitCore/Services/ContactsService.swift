import Foundation

public protocol ContactsServiceProtocol: Sendable {
    func requestAccess() async throws
    func search(query: String, limit: Int?) async throws -> [Contact]
    func upcomingBirthdays(withinDays: Int) async throws -> [Contact]
    func groups() async throws -> [ContactGroup]
}
