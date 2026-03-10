import Foundation

public final class ServiceContainer: @unchecked Sendable {
    public static let shared = ServiceContainer()

    public var calendarService: (any CalendarServiceProtocol)?
    public var remindersService: (any RemindersServiceProtocol)?
    public var contactsService: (any ContactsServiceProtocol)?

    private init() {}

    public static func configure(_ block: (ServiceContainer) -> Void) {
        block(shared)
    }
}
