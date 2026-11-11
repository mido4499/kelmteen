//
//  AppModel.swift
//  HabibyHakalemak
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

/// App-wide state. Everything is in memory for now; a backend will replace the sample data.
@Observable
final class AppModel {
    static let maxNoteLength = 120

    var currentUser: Person?
    // Keep the widget up to date whenever notes or the friends they come from change.
    var friends: [Person] = [] {
        didSet { WidgetSync.publish(notes: notes, friends: friends, currentUser: currentUser) }
    }
    var notes: [Note] = [] {
        didSet { WidgetSync.publish(notes: notes, friends: friends, currentUser: currentUser) }
    }
    var notificationsEnabled = true

    // UI state shared across tabs.
    var selectedTab: AppTab = .write
    var selectedRecipientID: Person.ID?

    var isSignedIn: Bool { currentUser != nil }

    // MARK: Account

    /// Creates the account with a randomly assigned color. The backend will own this assignment
    /// later so the color is the same on every friend's phone.
    func signUp(name: String, phone: String, color: PaletteColor = .random()) {
        currentUser = Person(name: name, phone: phone, color: color)
        loadSampleData()
        selectedTab = .write
    }

    func signOut() {
        currentUser = nil
        friends = []
        notes = []
        selectedRecipientID = nil
        selectedTab = .write
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

    /// Adds a friend. Their color comes from their own account; until there's a backend
    /// it's assigned at random here.
    func addFriend(name: String, phone: String) {
        friends.append(Person(name: name, phone: phone, color: .random()))
    }

    func remove(_ friend: Person) {
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
        model.signUp(name: "Ahmed Shaheen", phone: "+20 100 123 4567", color: .bubblegum)
        return model
    }
}
