//
//  AppModel.swift
//  Kelmteen
//

import SwiftUI
import Observation
import WidgetKit

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
    /// The photo picked on this device (or downloaded for the signed-in user).
    var photoData: Data?
    /// Where the uploaded photo lives in Supabase storage; nil if they never uploaded one.
    var photoPath: String?
    /// Only known for the signed-in user: a moderator suspended the account.
    var isSuspended = false

    init(
        id: UUID = UUID(),
        name: String,
        phone: String,
        color: PaletteColor,
        photoData: Data? = nil,
        photoPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.color = color
        self.photoData = photoData
        self.photoPath = photoPath
    }

    var photoURL: URL? {
        photoPath.map(KelmteenAPI.photoURL(for:))
    }

    var hasPhoto: Bool {
        photoData != nil || photoPath != nil
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            // A zero-width non-joiner keeps Arabic initials as separate letters instead of
            // joining them into one word; it's invisible for Latin initials.
            .joined(separator: "\u{200C}")
    }
}

struct Note: Identifiable, Hashable {
    let id: UUID
    let text: String
    let senderID: Person.ID
    let recipientID: Person.ID
    let sentAt: Date
    /// Notes live on the widget for a day; the server sets the exact time.
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        senderID: Person.ID,
        recipientID: Person.ID,
        sentAt: Date,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.senderID = senderID
        self.recipientID = recipientID
        self.sentAt = sentAt
        self.expiresAt = expiresAt ?? sentAt.addingTimeInterval(24 * 60 * 60)
    }

    var isExpired: Bool { expiresAt < .now }

    var timeLeftDescription: LocalizedStringResource {
        let hours = Int(expiresAt.timeIntervalSinceNow / 3600)
        guard hours >= 1 else { return "Less than an hour left" }
        // The system formatter handles plurals in every language ("18 hours", "١٨ ساعة").
        let duration = Duration.seconds(hours * 3600).formatted(.units(allowed: [.hours], width: .wide))
        return "\(duration) left"
    }
}

/// A friend invite: the sender's permanent invite code and who they are.
/// Why someone is being reported. Raw values match the server's `reports.reason` check.
enum ReportReason: String, CaseIterable, Identifiable {
    case inappropriatePhoto = "inappropriate_photo"
    case harassment
    case spam
    case other

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .inappropriatePhoto: "Inappropriate photo"
        case .harassment: "Harassment or offensive notes"
        case .spam: "Spam or fake account"
        case .other: "Something else"
        }
    }
}

struct Invite: Identifiable, Hashable {
    let code: String
    let inviter: Person
    /// The user blocked the inviter, so the invite can only be accepted after unblocking.
    var isBlockedByMe = false

    var id: String { code }
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

    /// The invite on screen ("Add <name> as your friend?"). Others wait in `queuedInvites`.
    var presentedInvite: Invite?
    private var queuedInvites: [Invite] = []
    /// An invite link opened while signed out, handled right after sign-in.
    private var linkedInviteCode: String?
    /// Set when an opened invite link doesn't exist, or its owner blocked the user. The
    /// message doesn't say which, so being blocked stays private.
    var isShowingUnavailableInvite = false

    /// People the user has blocked, shown in Me → Blocked.
    var blockedUsers: [Person] = []

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
        WidgetSync.prepareWidgetAccess(forUser: profile.id)
        Task { await registerDevice() }
        Task {
            // Friends load first so invites from existing friends can be skipped.
            await refreshFriends()
            await refreshNotes()
            await refreshBlockedUsers()
            await loadInvitesAfterSignIn()
        }
        Task { await loadOwnPhoto() }
    }

    /// Downloads the user's uploaded photo so it shows on Me and in the tab bar, which needs
    /// the image itself rather than a URL.
    private func loadOwnPhoto() async {
        guard let user = currentUser, user.photoData == nil, let url = user.photoURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              currentUser?.id == user.id else { return }
        updateCurrentUser { $0.photoData = data }
    }

    /// Shows the new photo right away, then uploads it so friends see it too. Restores the
    /// previous photo if the upload fails.
    func setProfilePhoto(_ data: Data) async throws {
        guard let jpeg = ProfilePhotoProcessing.avatarJPEG(from: data) else { return }
        let previous = currentUser
        updateCurrentUser { $0.photoData = jpeg }
        do {
            let path = try await api.uploadProfilePhoto(jpeg, replacing: previous?.photoPath)
            updateCurrentUser { $0.photoPath = path }
        } catch {
            updateCurrentUser { $0.photoData = previous?.photoData }
            throw error
        }
    }

    func signOut() {
        currentUser = nil
        friends = []
        notes = []
        selectedRecipientID = nil
        selectedTab = .write
        presentedInvite = nil
        queuedInvites = []
        linkedInviteCode = nil
        blockedUsers = []
        let deviceID = WidgetSync.deviceID
        WidgetSync.clearWidgetAccess()
        Task {
            // Unregister while still signed in, so the server stops pushing to this phone.
            await api.unregisterDevice(id: deviceID)
            await api.signOut()
        }
    }

    /// Permanently deletes the account and everything in it, then returns to sign-up.
    func deleteAccount() async throws {
        try await api.deleteAccount()
        signOut()
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
        let message = String(localized: "Add me on Kelmteen so we can send each other little notes 💌 \(inviteLink.absoluteString)")
        // wa.me wants the number without the leading "+".
        var components = URLComponents(string: "https://wa.me/\(contact.invitePhone.dropFirst())")
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    func remove(_ friend: Person) {
        Task { try? await api.removeFriend(id: friend.id) }
        forget(friend)
    }

    /// Drops a former friend and their notes from this device.
    private func forget(_ friend: Person) {
        friends.removeAll { $0.id == friend.id }
        notes.removeAll { $0.senderID == friend.id || $0.recipientID == friend.id }
        if selectedRecipientID == friend.id {
            selectedRecipientID = nil
        }
    }

    // MARK: Invites

    /// Handles an invite link opened from WhatsApp, Safari or anywhere else.
    func handleInviteLink(_ url: URL) {
        guard let code = KelmteenAPI.inviteCode(from: url) else { return }
        guard isSignedIn else {
            linkedInviteCode = code
            return
        }
        Task { await showLinkedInvite(code: code) }
    }

    private func showLinkedInvite(code: String) async {
        do {
            if let invite = try await api.invite(code: code) {
                present([invite])
            } else {
                isShowingUnavailableInvite = true
            }
        } catch {
            // Network trouble; the link can be opened again later.
        }
    }

    /// Shows the invite from a link opened while signed out, then any invites sent to the
    /// user's number before they had the app.
    private func loadInvitesAfterSignIn() async {
        if let code = linkedInviteCode {
            linkedInviteCode = nil
            await showLinkedInvite(code: code)
        }
        present((try? await api.pendingInvites()) ?? [])
    }

    /// Queues invites for display, skipping the user's own link, existing friends and duplicates.
    private func present(_ invites: [Invite]) {
        for invite in invites {
            let inviterID = invite.inviter.id
            let isDuplicate = presentedInvite?.inviter.id == inviterID
                || queuedInvites.contains { $0.inviter.id == inviterID }
            guard inviterID != currentUser?.id, friend(id: inviterID) == nil, !isDuplicate else { continue }
            queuedInvites.append(invite)
        }
        if presentedInvite == nil, !queuedInvites.isEmpty {
            presentedInvite = queuedInvites.removeFirst()
        }
    }

    func accept(_ invite: Invite) async throws {
        try await api.acceptInvite(code: invite.code)
        await refreshFriends()
        selectedTab = .friends
        showNextInvite()
    }

    func decline(_ invite: Invite) {
        Task { try? await api.dismissInvite(code: invite.code) }
        showNextInvite()
    }

    /// Closes an invite without answering it.
    func close(_ invite: Invite) {
        showNextInvite()
    }

    /// Unblocks the inviter from their invite screen. If that made them friends again the
    /// invite is done; otherwise the screen turns into the regular invite to accept.
    func unblockFromInvite(_ invite: Invite) async throws {
        try await unblock(invite.inviter)
        if friend(id: invite.inviter.id) != nil {
            selectedTab = .friends
            showNextInvite()
        } else {
            presentedInvite?.isBlockedByMe = false
        }
    }

    private func showNextInvite() {
        presentedInvite = queuedInvites.isEmpty ? nil : queuedInvites.removeFirst()
    }

    // MARK: Blocking

    func isBlocked(_ id: Person.ID) -> Bool {
        blockedUsers.contains { $0.id == id }
    }

    func refreshBlockedUsers() async {
        guard isSignedIn, let fetched = try? await api.blockedUsers() else { return }
        blockedUsers = fetched
    }

    /// Blocks someone. They stop being friends (for both people) and can't add the user.
    func block(_ person: Person) async throws {
        try await api.blockUser(id: person.id)
        forget(person)
        if !isBlocked(person.id) {
            blockedUsers.append(person)
        }
        await refreshBlockedUsers()
    }

    /// Unblocks someone; they come back as a friend if they were one when blocked.
    func unblock(_ person: Person) async throws {
        try await api.unblockUser(id: person.id)
        blockedUsers.removeAll { $0.id == person.id }
        await refreshFriends()
    }

    // MARK: Reporting

    /// Sends a report for moderators to review. The reported person isn't told.
    func report(_ person: Person, reason: ReportReason, details: String) async throws {
        try await api.reportUser(id: person.id, reason: reason, details: details)
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

    /// Sends a note through the server, which checks they're still friends.
    func send(_ text: String, to friend: Person) async throws {
        let note = try await api.sendNote(text, to: friend.id)
        notes.append(note)
    }

    /// Loads unexpired notes sent and received. Only notes with current friends are kept, so
    /// notes from someone who was removed or blocked don't come back.
    func refreshNotes() async {
        guard isSignedIn, let fetched = try? await api.fetchNotes() else { return }
        let friendIDs = Set(friends.map(\.id))
        notes = fetched.filter { friendIDs.contains($0.senderID) || friendIDs.contains($0.recipientID) }
    }

    /// Reloads everything that friends can change while the app is in the background.
    func refresh() async {
        await refreshFriends()
        await refreshNotes()
        await registerDevice()
    }

    /// Tells the server about this phone's widget: the secret it reads notes with and the token
    /// for push updates (only available once a widget has been added).
    private func registerDevice() async {
        guard isSignedIn else { return }
        let pushToken = await WidgetCenter.shared.currentPushInfo?.token
            .map { String(format: "%02x", $0) }
            .joined()
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        try? await api.registerDevice(
            id: WidgetSync.deviceID,
            widgetSecret: WidgetSync.widgetSecret(),
            widgetPushToken: pushToken,
            sandbox: sandbox
        )
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
