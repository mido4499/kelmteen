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
    // The publishable key is safe to ship in the app: row level security protects the data.
    private static let client = SupabaseClient(
        supabaseURL: URL(string: "https://slwarapujtjzjtlhdciw.supabase.co")!,
        supabaseKey: "sb_publishable_OuSLIA4YfvWOaI8B1T-fFw__2cY17Mm"
    )

    /// Every user's permanent invite link is this followed by their invite code. The site
    /// lives in `website/` and is hosted on Cloudflare Pages.
    static let inviteBaseURL = URL(string: "https://kelmteen.ahmedshaheen.com/i/")!

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

    enum CodingKeys: String, CodingKey {
        case id, phone, name, color
        case inviteCode = "invite_code"
    }

    @MainActor var person: Person {
        Person(id: id, name: name, phone: phone, color: PaletteColor(rawValue: color) ?? .sky)
    }
}

/// A row returned by the `match_contacts` function.
nonisolated private struct ContactMatchRecord: Decodable, Sendable {
    let phoneHash: String
    let id: UUID
    let name: String
    let color: String

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case phoneHash = "phone_hash"
    }

    @MainActor var person: Person {
        Person(id: id, name: name, phone: "", color: PaletteColor(rawValue: color) ?? .sky)
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
