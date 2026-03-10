import Foundation

public struct Contact: Codable, Sendable, Equatable, FieldSelectable {
    public static let availableFields = [
        "id", "givenName", "familyName", "organizationName",
        "emailAddresses", "phoneNumbers", "birthday", "note",
    ]

    public let id: String
    public let givenName: String
    public let familyName: String
    public let organizationName: String?
    public let emailAddresses: [String]
    public let phoneNumbers: [String]
    public let birthday: String? // Formatted date string for Codable simplicity
    public let note: String?

    public init(
        id: String,
        givenName: String,
        familyName: String,
        organizationName: String? = nil,
        emailAddresses: [String] = [],
        phoneNumbers: [String] = [],
        birthday: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.organizationName = organizationName
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
        self.birthday = birthday
        self.note = note
    }

    public var fullName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension Contact: TextRepresentable {
    public var textSummary: String {
        var lines = [fullName]
        for email in emailAddresses {
            lines.append("  Email:  \(email)")
        }
        for phone in phoneNumbers {
            lines.append("  Phone:  \(phone)")
        }
        if let org = organizationName, !org.isEmpty {
            lines.append("  Org:    \(org)")
        }
        return lines.joined(separator: "\n")
    }

    public var textDetail: String {
        var lines = [fullName]
        if let org = organizationName, !org.isEmpty {
            lines.append("  Organization:  \(org)")
        }
        for email in emailAddresses {
            lines.append("  Email:         \(email)")
        }
        for phone in phoneNumbers {
            lines.append("  Phone:         \(phone)")
        }
        if let birthday {
            lines.append("  Birthday:      \(birthday)")
        }
        if let note, !note.isEmpty {
            lines.append("  Note:          \(note.prefix(200))")
        }
        return lines.joined(separator: "\n")
    }
}

extension Contact: TableRepresentable {
    public static var tableHeaders: [String] { ["Name", "Email", "Phone", "Organization"] }
    public var tableRow: [String] {
        [
            fullName,
            emailAddresses.first ?? "-",
            phoneNumbers.first ?? "-",
            organizationName ?? "-",
        ]
    }
}

public struct ContactGroup: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let memberCount: Int

    public init(id: String, name: String, memberCount: Int = 0) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
    }
}
