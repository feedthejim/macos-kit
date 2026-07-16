import Contacts
import Foundation

public final class LiveContactsService: ContactsServiceProtocol, @unchecked Sendable {
    private static let permissionTimeoutSeconds = 30
    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private let store = CNContactStore()

    public init() {}

    public func requestAccess() async throws {
        let granted = try await withAsyncTimeout(
            seconds: Self.permissionTimeoutSeconds,
            timeoutError: permissionTimeoutError(.contacts)
        ) { [self] in
            try await store.requestAccess(for: .contacts)
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

    public func search(query: String, limit: Int?, fields: Set<String>?) async throws -> [Contact] {
        if let limit, limit <= 0 { return [] }
        let keysToFetch = contactKeys(for: fields)

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let cnContacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

        var results = cnContacts.map { mapContact($0) }

        if let limit {
            results = Array(results.prefix(limit))
        }

        return results
    }

    public func upcomingBirthdays(withinDays days: Int, fields: Set<String>?) async throws -> [Contact] {
        guard days >= 0 else { return [] }
        var requestedFields = fields ?? Set(Contact.availableFields)
        requestedFields.formUnion(["givenName", "familyName", "birthday"])
        let keysToFetch = contactKeys(for: requestedFields)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: days, to: today)!

        // Fetch all contacts with birthdays
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [Contact] = []

        try store.enumerateContacts(with: request) { cnContact, _ in
            guard let birthday = cnContact.birthday else { return }

            // Check if birthday falls within range (month/day comparison)
            var nextBirthday = birthday
            nextBirthday.year = calendar.component(.year, from: today)

            if let candidate = calendar.date(from: nextBirthday), candidate < today {
                nextBirthday.year = (nextBirthday.year ?? 0) + 1
            }

            if let bdayDate = calendar.date(from: nextBirthday),
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
        if cnContact.isKeyAvailable(CNContactBirthdayKey), let bday = cnContact.birthday {
            if let date = Calendar.current.date(from: bday) {
                birthday = Self.birthdayFormatter.string(from: date)
            } else {
                birthday = nil
            }
        } else {
            birthday = nil
        }

        return Contact(
            id: cnContact.identifier,
            givenName: cnContact.isKeyAvailable(CNContactGivenNameKey) ? cnContact.givenName : "",
            familyName: cnContact.isKeyAvailable(CNContactFamilyNameKey) ? cnContact.familyName : "",
            organizationName: organizationName(for: cnContact),
            emailAddresses: cnContact.isKeyAvailable(CNContactEmailAddressesKey)
                ? cnContact.emailAddresses.map { $0.value as String } : [],
            phoneNumbers: cnContact.isKeyAvailable(CNContactPhoneNumbersKey)
                ? cnContact.phoneNumbers.map { $0.value.stringValue } : [],
            birthday: birthday,
            note: nil // Note requires special entitlement
        )
    }

    private func contactKeys(for fields: Set<String>?) -> [CNKeyDescriptor] {
        let fields = fields ?? Set(Contact.availableFields)
        var keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor]
        if fields.contains("givenName") { keys.append(CNContactGivenNameKey as CNKeyDescriptor) }
        if fields.contains("familyName") { keys.append(CNContactFamilyNameKey as CNKeyDescriptor) }
        if fields.contains("organizationName") { keys.append(CNContactOrganizationNameKey as CNKeyDescriptor) }
        if fields.contains("emailAddresses") { keys.append(CNContactEmailAddressesKey as CNKeyDescriptor) }
        if fields.contains("phoneNumbers") { keys.append(CNContactPhoneNumbersKey as CNKeyDescriptor) }
        if fields.contains("birthday") { keys.append(CNContactBirthdayKey as CNKeyDescriptor) }
        return keys
    }

    private func organizationName(for contact: CNContact) -> String? {
        guard contact.isKeyAvailable(CNContactOrganizationNameKey),
              !contact.organizationName.isEmpty else { return nil }
        return contact.organizationName
    }
}
