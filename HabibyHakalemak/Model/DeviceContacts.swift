//
//  DeviceContacts.swift
//  Kelmteen
//

import Contacts

/// Someone from the user's address book, and their Kelmteen account if they have one.
struct ContactEntry: Identifiable, Hashable {
    let id: String
    let name: String
    /// The number to invite: the one linked to their account if they have one, else their first.
    let invitePhone: String
    let user: Person?
}

/// A contact as read from the address book, before matching.
nonisolated struct DeviceContact: Sendable {
    let id: String
    let name: String
    /// Distinct numbers in E.164 format.
    let phones: [String]
}

nonisolated enum DeviceContacts {
    static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    static func requestAccess() async -> CNAuthorizationStatus {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return authorizationStatus
    }

    /// Reads every contact that has at least one phone number. Runs off the main actor because
    /// enumerating a large address book blocks.
    @concurrent static func load() async throws -> [DeviceContact] {
        let request = CNContactFetchRequest(keysToFetch: [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ])
        request.sortOrder = .userDefault

        var contacts: [DeviceContact] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            var phones: [String] = []
            for number in contact.phoneNumbers {
                if let phone = PhoneNumber.e164(from: number.value.stringValue), !phones.contains(phone) {
                    phones.append(phone)
                }
            }
            guard let firstPhone = phones.first else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? firstPhone
            contacts.append(DeviceContact(id: contact.identifier, name: name, phones: phones))
        }
        return contacts
    }
}
