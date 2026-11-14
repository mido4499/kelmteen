//
//  AppModel.swift
//  Kelmteen
//

import SwiftUI
import Observation

/// Every account is assigned one of these at random on sign-up. It's that person's color
/// everywhere: their account page, avatar, chat pill on friends' phones, and their notes.
enum PaletteColor: String, CaseIterable, Identifiable, Hashable {
    case sky, bubblegum, sunshine

    var id: Self { self }

    var color: Color {
        switch self {
        case .sky: Color.sky
        case .bubblegum: Color.bubblegum
        case .sunshine: Color.sunshine
        }
    }

    static func random() -> PaletteColor {
        allCases.randomElement() ?? .sky
    }
}

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    var phone: String
    var color: PaletteColor
    var photoData: Data?

    init(id: UUID = UUID(), name: String, phone: String, color: PaletteColor, photoData: Data? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.color = color
        self.photoData = photoData
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct Note: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let senderID: Person.ID
    let recipientID: Person.ID
    let sentAt: Date

    /// Notes live on the widget for a day.
    var expiresAt: Date { sentAt.addingTimeInterval(24 * 60 * 60) }
    var isExpired: Bool { expiresAt < .now }

    var timeLeftDescription: String {
        let hours = Int(expiresAt.timeIntervalSinceNow / 3600)
        switch hours {
        case ..<1: return "Less than an hour left"
        case 1: return "1 hour left"
        default: return "\(hours) hours left"
        }
    }
}

enum AppTab: Hashable {
    case write, friends, account
}

/// App-wide state. The account and friends come from the backend; notes are still local
/// until their endpoints are connected.
@Observable
final class AppModel {
    static let maxNoteLength = 120

    private let api = KelmteenAPI()

    var currentUser: Person?
    // Keep the widget up to date whenever notes or the friends they come from change.
    var friends: [Person] = [] {
        didSet { WidgetSync.publish(notes: notes, friends: friends, currentUser: currentUser) }
    }
    var notes: [Note] = [] {
        didSet { WidgetSync.publish(notes: notes, friends: friends, currentUser: currentUser) }
    }
    var notificationsEnabled = true

    /// False until the saved session has been checked at launch, so returning users don't
    /// see a flash of the sign-up screen.
    var hasRestoredSession = false

    // UI state shared across tabs.
    var selectedTab: AppTab = .write
    var selectedRecipientID: Person.ID?

    var isSignedIn: Bool { currentUser != nil }

    // MARK: Account

    func restoreSession() async {
        defer { hasRestoredSession = true }
        if let profile = try? await api.restoreProfile() {
            signIn(as: profile)
        }
    }

    /// Texts a verification code to an E.164 phone number.
    func sendCode(to phone: String) async throws {
        try await api.sendCode(to: phone)
    }

    /// Verifies the code. Returning users are signed in right away and this returns true;
    /// it returns false when a new user still needs to choose a name.
    func verify(code: String, phone: String) async throws -> Bool {
        guard let profile = try await api.verify(code: code, phone: phone) else { return false }
        signIn(as: profile)
        return true
    }

    /// Finishes sign-up for a verified user.
    func createProfile(name: String) async throws {
        signIn(as: try await api.createProfile(name: name))
    }

    private func signIn(as profile: Person) {
        currentUser = profile
        selectedTab = .write
        Task { await refreshFriends() }
    }

    func signOut() {
        currentUser = nil
        friends = []
        notes = []
        selectedRecipientID = nil
        selectedTab = .write
        Task { await api.signOut() }
    }

    func updateCurrentUser(_ update: (inout Person) -> Void) {
        guard var user = currentUser else { return }
        update(&user)
        currentUser = user
    }

    // MARK: Friends

    func friend(id: Person.ID) -> Person? {
        friends.first { $0.id == id }
    }

    func refreshFriends() async {
        guard isSignedIn, let fetched = try? await api.fetchFriends() else { return }
        friends = fetched
    }

    /// Reads the address book and marks which contacts are on Kelmteen. Contacts on the app
    /// come first, then everyone else, each group in address book order.
    func loadContacts() async throws -> [ContactEntry] {
        let deviceContacts = try await DeviceContacts.load()

        // Only hashes leave the phone.
        var phoneForHash: [String: String] = [:]
        for contact in deviceContacts {
            for phone in contact.phones {
                phoneForHash[PhoneNumber.hash(phone)] = phone
            }
        }
        let matches = try await api.matchContacts(phoneHashes: Array(phoneForHash.keys))

        let entries = deviceContacts.map { contact in
            let match = contact.phones.lazy
                .compactMap { phone in matches[PhoneNumber.hash(phone)].map { (phone, $0) } }
                .first
            return ContactEntry(
                id: contact.id,
                name: contact.name,
                invitePhone: match?.0 ?? contact.phones[0],
                user: match?.1
            )
        }
        return entries.filter { $0.user != nil } + entries.filter { $0.user == nil }
    }

    /// A WhatsApp link that opens a chat with the contact, prefilled with the user's invite link.
    func whatsAppInvite(for contact: ContactEntry) async throws -> URL {
        let inviteLink = try await api.createInvite(phone: contact.invitePhone)
        let message = "Add me on Kelmteen so we can send each other little notes 💌 \(inviteLink.absoluteString)"
        // wa.me wants the number without the leading "+".
        var components = URLComponents(string: "https://wa.me/\(contact.invitePhone.dropFirst())")
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    func remove(_ friend: Person) {
        Task { try? await api.removeFriend(id: friend.id) }
        friends.removeAll { $0.id == friend.id }
        notes.removeAll { $0.senderID == friend.id || $0.recipientID == friend.id }
        if selectedRecipientID == friend.id {
            selectedRecipientID = nil
        }
    }

    // MARK: Notes

    /// Whether a friend has a live note on the current user's widget. Received notes are only
    /// ever shown on the widget, so the app just hints that one exists.
    func hasNote(from friend: Person) -> Bool {
        notes.contains { $0.senderID == friend.id && !$0.isExpired }
    }

    /// The most recent unexpired note the current user sent to a friend.
    func latestNote(to friend: Person) -> Note? {
        guard let currentUser else { return nil }
        return notes
            .filter { $0.senderID == currentUser.id && $0.recipientID == friend.id && !$0.isExpired }
            .max { $0.sentAt < $1.sentAt }
    }

    @discardableResult
    func send(_ text: String, to friend: Person) -> Note? {
        guard let currentUser else { return nil }
        let note = Note(text: text, senderID: currentUser.id, recipientID: friend.id, sentAt: .now)
        notes.append(note)
        return note
    }

    /// Jumps to the Write tab with the given friend preselected.
    func startNote(to friend: Person) {
        selectedRecipientID = friend.id
        selectedTab = .write
    }

    // MARK: Sample data

    private func loadSampleData() {
        let ahmed = Person(name: "Ahmed Wael", phone: "+20 100 000 0001", color: .sky)
        let lily = Person(name: "Lily Light", phone: "+20 100 000 0002", color: .bubblegum)
        let maya = Person(name: "Maya Adam", phone: "+20 100 000 0003", color: .sunshine)
        friends = [ahmed, lily, maya]

        if let currentUser {
            notes = [
                Note(text: "Miss you!", senderID: ahmed.id, recipientID: currentUser.id,
                     sentAt: .now.addingTimeInterval(-2 * 60 * 60)),
                Note(text: "Good luck on your exams! You've got this.", senderID: maya.id,
                     recipientID: currentUser.id, sentAt: .now.addingTimeInterval(-6 * 60)),
                Note(text: "Coffee later?", senderID: currentUser.id, recipientID: ahmed.id,
                     sentAt: .now.addingTimeInterval(-6 * 60 * 60))
            ]
        }
    }

    static var preview: AppModel {
        let model = AppModel()
        model.hasRestoredSession = true
        model.currentUser = Person(name: "Ahmed Shaheen", phone: "+201001234567", color: .bubblegum)
        model.loadSampleData()
        return model
    }
}
