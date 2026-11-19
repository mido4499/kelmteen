//
//  KelmteenAPI.swift
//  Kelmteen
//

import CryptoKit
import Foundation
import Supabase

/// The app's only connection to the Supabase backend. Everything Supabase-specific lives here
/// so the rest of the app works with plain `Person` values.
struct KelmteenAPI {
    nonisolated private static let projectURL = URL(string: "https://slwarapujtjzjtlhdciw.supabase.co")!

    // The publishable key is safe to ship in the app: row level security protects the data.
    private static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: "sb_publishable_OuSLIA4YfvWOaI8B1T-fFw__2cY17Mm"
    )

    /// Every user's permanent invite link is this followed by their invite code. The site
    /// lives in `website/` and is hosted on Cloudflare Pages.
    static let inviteBaseURL = URL(string: "https://kelmteen.ahmedshaheen.com/i/")!

    static let supportEmail = "kelmteen@ahmedshaheen.com"
    static let supportURL = URL(string: "mailto:kelmteen@ahmedshaheen.com")!
    static let termsURL = URL(string: "https://kelmteen.ahmedshaheen.com/terms")!
    static let privacyURL = URL(string: "https://kelmteen.ahmedshaheen.com/privacy")!

    private var client: SupabaseClient { Self.client }

    // MARK: Auth

    /// Texts a 6-digit code to an E.164 phone number.
    func sendCode(to phone: String) async throws {
        try await client.auth.signInWithOTP(phone: phone)
    }

    /// Verifies the code and returns the user's profile, or nil for a new user who still
    /// needs to pick a name.
    func verify(code: String, phone: String) async throws -> Person? {
        try await client.auth.verifyOTP(phone: phone, token: code, type: .sms)
        return try await currentProfile()
    }

    /// The signed-in user's profile from a saved session, if there is one.
    func restoreProfile() async throws -> Person? {
        guard (try? await client.auth.session) != nil else { return nil }
        return try await currentProfile()
    }

    /// Creates the profile for a newly verified user. The server assigns their color.
    func createProfile(name: String) async throws -> Person {
        let profile: ProfileRecord = try await client
            .rpc("create_profile", params: ["display_name": name])
            .execute()
            .value
        return profile.person
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    /// Permanently deletes the account and all its data (see supabase/functions/delete-account),
    /// then clears the local session.
    func deleteAccount() async throws {
        try await client.functions.invoke("delete-account")
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: Photos

    /// Public URL of a photo in the `avatars` bucket.
    nonisolated static func photoURL(for path: String) -> URL {
        projectURL
            .appending(path: "storage/v1/object/public/avatars")
            .appending(path: path)
    }

    /// Uploads a new profile photo, points the user's profile at it and deletes the old one.
    /// Returns the new storage path.
    func uploadProfilePhoto(_ jpeg: Data, replacing oldPath: String?) async throws -> String {
        guard let userID = client.auth.currentUser?.id else { throw URLError(.userAuthenticationRequired) }
        // Storage rules only allow writes inside the user's own folder. A new file name per
        // upload means cached copies never show an old photo, so they can be kept for a year.
        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage
            .from("avatars")
            .upload(path, data: jpeg, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
        try await client
            .from("profiles")
            .update(["photo_path": path])
            .eq("id", value: userID)
            .execute()
        if let oldPath {
            _ = try? await client.storage.from("avatars").remove(paths: [oldPath])
        }
        return path
    }

    // MARK: Friends

    /// Row level security only lets users see their own profile and their friends',
    /// so every other profile the query returns is a friend.
    func fetchFriends() async throws -> [Person] {
        guard let userID = client.auth.currentUser?.id else { return [] }
        let profiles: [ProfileRecord] = try await client
            .from("profiles")
            .select()
            .neq("id", value: userID)
            .order("name")
            .execute()
            .value
        return profiles.map(\.person)
    }

    func removeFriend(id friendID: UUID) async throws {
        guard let userID = client.auth.currentUser?.id else { return }
        let me = userID.uuidString.lowercased()
        let friend = friendID.uuidString.lowercased()
        try await client
            .from("friendships")
            .delete()
            .or("and(user_a.eq.\(me),user_b.eq.\(friend)),and(user_a.eq.\(friend),user_b.eq.\(me))")
            .execute()
    }

    /// Looks up which phone hashes belong to Kelmteen users. Returns accounts keyed by hash.
    func matchContacts(phoneHashes: [String]) async throws -> [String: Person] {
        var matches: [String: Person] = [:]
        // The server accepts up to 5,000 hashes per call.
        for start in stride(from: 0, to: phoneHashes.count, by: 1000) {
            let batch = Array(phoneHashes[start..<min(start + 1000, phoneHashes.count)])
            let records: [ContactMatchRecord] = try await client
                .rpc("match_contacts", params: ["phone_hashes": batch])
                .execute()
                .value
            for record in records {
                matches[record.phoneHash] = record.person
            }
        }
        return matches
    }

    /// Records that the user invited this number and returns the user's invite link.
    func createInvite(phone: String) async throws -> URL {
        let code: String = try await client
            .rpc("create_invite", params: ["contact_phone_hash": PhoneNumber.hash(phone)])
            .execute()
            .value
        return Self.inviteBaseURL.appending(path: code)
    }

    // MARK: Invites

    /// The invite code in a link like https://kelmteen.ahmedshaheen.com/i/<code>, if it is one.
    static func inviteCode(from url: URL) -> String? {
        guard url.host() == inviteBaseURL.host() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "i", !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// Who an invite code belongs to, or nil if the code doesn't exist.
    func invite(code: String) async throws -> Invite? {
        let records: [InviterRecord] = try await client
            .rpc("invite_preview", params: ["code": code])
            .execute()
            .value
        return records.first.map {
            Invite(code: code, inviter: $0.person, isBlockedByMe: $0.blockedByMe ?? false)
        }
    }

    /// Invites other users sent to this user's phone number before they had the app.
    func pendingInvites() async throws -> [Invite] {
        let records: [InviterRecord] = try await client
            .rpc("my_pending_invites")
            .execute()
            .value
        return records.compactMap { record in
            record.inviteCode.map { Invite(code: $0, inviter: record.person) }
        }
    }

    /// Makes the user and the invite's sender friends.
    func acceptInvite(code: String) async throws {
        try await client
            .rpc("accept_invite", params: ["code": code])
            .execute()
    }

    /// Clears an invite the user turned down so it isn't offered again.
    func dismissInvite(code: String) async throws {
        try await client
            .rpc("dismiss_invite", params: ["code": code])
            .execute()
    }

    // MARK: Devices

    /// Registers this phone so its widget can load notes and get push updates.
    func registerDevice(id: String, widgetSecret: String, widgetPushToken: String?, sandbox: Bool) async throws {
        try await client
            .from("devices")
            .upsert(
                DeviceRecord(deviceID: id, widgetSecret: widgetSecret, widgetPushToken: widgetPushToken, apnsSandbox: sandbox),
                onConflict: "user_id,device_id"
            )
            .execute()
    }

    func unregisterDevice(id: String) async {
        _ = try? await client
            .from("devices")
            .delete()
            .eq("device_id", value: id)
            .execute()
    }

    // MARK: Notes

    func sendNote(_ text: String, to recipientID: UUID) async throws -> Note {
        // Only the recipient and text come from the app; the server sets sender and times.
        let record: NoteRecord = try await client
            .from("notes")
            .insert(["recipient_id": recipientID.uuidString.lowercased(), "text": text])
            .select()
            .single()
            .execute()
            .value
        return record.note
    }

    /// Unexpired notes the user sent or received (row level security limits it to theirs).
    func fetchNotes() async throws -> [Note] {
        let records: [NoteRecord] = try await client
            .from("notes")
            .select()
            .gt("expires_at", value: Date.now.ISO8601Format())
            .order("sent_at", ascending: false)
            .execute()
            .value
        return records.map(\.note)
    }

    // MARK: Reporting

    func reportUser(id: UUID, reason: ReportReason, details: String) async throws {
        try await client
            .rpc("report_user", params: ReportParams(target: id, reason: reason.rawValue, details: details))
            .execute()
    }

    // MARK: Blocking

    /// Blocks someone: ends the friendship and stops them adding the user. They aren't told.
    func blockUser(id: UUID) async throws {
        try await client
            .rpc("block_user", params: ["target": id])
            .execute()
    }

    /// Unblocks someone. The server restores the friendship if they were friends before.
    func unblockUser(id: UUID) async throws {
        try await client
            .rpc("unblock_user", params: ["target": id])
            .execute()
    }

    func blockedUsers() async throws -> [Person] {
        let records: [InviterRecord] = try await client
            .rpc("my_blocked_users")
            .execute()
            .value
        return records.map(\.person)
    }

    private func currentProfile() async throws -> Person? {
        guard let userID = client.auth.currentUser?.id else { return nil }
        let profiles: [ProfileRecord] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .execute()
            .value
        return profiles.first?.person
    }
}

/// A row of the `profiles` table.
nonisolated private struct ProfileRecord: Decodable, Sendable {
    let id: UUID
    let phone: String
    let name: String
    let color: String
    let inviteCode: String
    let photoPath: String?
    let suspendedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, name, color
        case inviteCode = "invite_code"
        case photoPath = "photo_path"
        case suspendedAt = "suspended_at"
    }

    @MainActor var person: Person {
        var person = Person(id: id, name: name, phone: phone, color: PaletteColor(rawValue: color) ?? .sky, photoPath: photoPath)
        person.isSuspended = suspendedAt != nil
        return person
    }
}

/// The columns of `devices` the app writes; `user_id` defaults to the signed-in user.
nonisolated private struct DeviceRecord: Encodable, Sendable {
    let deviceID: String
    let widgetSecret: String
    let widgetPushToken: String?
    let apnsSandbox: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case widgetSecret = "widget_secret"
        case widgetPushToken = "widget_push_token"
        case apnsSandbox = "apns_sandbox"
    }
}

/// A row of the `notes` table.
nonisolated private struct NoteRecord: Decodable, Sendable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let text: String
    let sentAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id, text
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case sentAt = "sent_at"
        case expiresAt = "expires_at"
    }

    @MainActor var note: Note {
        Note(id: id, text: text, senderID: senderID, recipientID: recipientID, sentAt: sentAt, expiresAt: expiresAt)
    }
}

nonisolated private struct ReportParams: Encodable, Sendable {
    let target: UUID
    let reason: String
    let details: String
}

/// A row returned by `invite_preview`, `my_pending_invites` and `my_blocked_users`.
/// Only pending invites include the code; only `invite_preview` says whether the user blocked them.
nonisolated private struct InviterRecord: Decodable, Sendable {
    let inviteCode: String?
    let id: UUID
    let name: String
    let color: String
    let photoPath: String?
    let blockedByMe: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case inviteCode = "invite_code"
        case photoPath = "photo_path"
        case blockedByMe = "blocked_by_me"
    }

    @MainActor var person: Person {
        Person(id: id, name: name, phone: "", color: PaletteColor(rawValue: color) ?? .sky, photoPath: photoPath)
    }
}

/// A row returned by the `match_contacts` function.
nonisolated private struct ContactMatchRecord: Decodable, Sendable {
    let phoneHash: String
    let id: UUID
    let name: String
    let color: String
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case phoneHash = "phone_hash"
        case photoPath = "photo_path"
    }

    @MainActor var person: Person {
        Person(id: id, name: name, phone: "", color: PaletteColor(rawValue: color) ?? .sky, photoPath: photoPath)
    }
}

nonisolated enum PhoneNumber {
    /// Converts what the user typed into E.164 (e.g. "+201001234567"). Numbers without a
    /// country code are treated as Egyptian. Returns nil if it doesn't look like a number.
    ///
    /// This is deliberately simple: foreign numbers saved without a country code will be
    /// misread as Egyptian. A full parser (e.g. PhoneNumberKit) would fix that.
    static func e164(from input: String) -> String? {
        // Converts Arabic-Indic digits ("٠١٠٠") to ASCII so hashes match the server's.
        var digits = input.compactMap(\.wholeNumberValue).map(String.init).joined()
        if input.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
            // Already international.
        } else if digits.hasPrefix("00") {
            digits.removeFirst(2)
        } else if digits.hasPrefix("0") {
            digits = "20" + digits.dropFirst()
        } else if !digits.hasPrefix("20") {
            digits = "20" + digits
        }
        guard (8...15).contains(digits.count) else { return nil }
        return "+" + digits
    }

    /// Hex SHA-256 of an E.164 number. Must match how the server hashes `profiles.phone`.
    static func hash(_ e164: String) -> String {
        SHA256.hash(data: Data(e164.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
