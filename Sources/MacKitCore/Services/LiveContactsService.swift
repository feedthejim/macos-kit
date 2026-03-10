import Contacts
import Foundation

public final class LiveContactsService: ContactsServiceProtocol, @unchecked Sendable {
    private let store = CNContactStore()

    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestAccess(for: .contacts)
        } else {
            granted = try await store.requestAccess(for: .contacts)
        }

        guard granted else {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            switch status {
            case .denied, .restricted:
                throw MacKitError.permissionDenied(.contacts)
            default:
                throw MacKitError.permissionNotDetermined(.contacts)
            }
        }
    }

    public func search(query: String, limit: Int?) async throws -> [Contact] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let cnContacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

        var results = cnContacts.map { mapContact($0) }

        if let limit {
            results = Array(results.prefix(limit))
        }

        return results
    }

    public func upcomingBirthdays(withinDays days: Int) async throws -> [Contact] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: days, to: today)!

        // Fetch all contacts with birthdays
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [Contact] = []

        try store.enumerateContacts(with: request) { cnContact, _ in
            guard let birthday = cnContact.birthday else { return }

            // Check if birthday falls within range (month/day comparison)
            var thisYearBirthday = birthday
            thisYearBirthday.year = calendar.component(.year, from: today)

            if let bdayDate = calendar.date(from: thisYearBirthday),
               bdayDate >= today && bdayDate <= endDate
            {
                contacts.append(mapContact(cnContact))
            }
        }

        return contacts.sorted { ($0.birthday ?? "") < ($1.birthday ?? "") }
    }

    public func groups() async throws -> [ContactGroup] {
        let cnGroups = try store.groups(matching: nil)
        return cnGroups.map { group in
            let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
            let count = (try? store.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).count) ?? 0
            return ContactGroup(id: group.identifier, name: group.name, memberCount: count)
        }
    }

    private func mapContact(_ cnContact: CNContact) -> Contact {
        let birthday: String?
        if let bday = cnContact.birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            if let date = Calendar.current.date(from: bday) {
                birthday = formatter.string(from: date)
            } else {
                birthday = nil
            }
        } else {
            birthday = nil
        }

        return Contact(
            id: cnContact.identifier,
            givenName: cnContact.givenName,
            familyName: cnContact.familyName,
            organizationName: cnContact.organizationName.isEmpty ? nil : cnContact.organizationName,
            emailAddresses: cnContact.emailAddresses.map { $0.value as String },
            phoneNumbers: cnContact.phoneNumbers.map { $0.value.stringValue },
            birthday: birthday,
            note: nil // Note requires special entitlement
        )
    }
}
