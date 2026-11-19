//
//  WidgetSync.swift
//  Kelmteen
//

import Foundation
import WidgetKit

/// Mirrors the notes the user received into the shared App Group so the widget can show them.
/// The widget decodes the same JSON shape (see `WidgetNote` in the NotesWidget target).
enum WidgetSync {
    static let appGroup = "group.com.ahmedshaheen.kelmteen"
    static let notesKey = "receivedNotes"
    // Shared with the widget (see WidgetNoteStore), which uses them to load notes itself.
    static let widgetSecretKey = "widgetSecret"
    static let deviceIDKey = "deviceID"
    static let widgetUserKey = "widgetUserID"

    /// A stable ID for this install, so the server can keep one row per phone.
    static var deviceID: String {
        let defaults = UserDefaults(suiteName: appGroup)
        if let id = defaults?.string(forKey: deviceIDKey) { return id }
        let id = UUID().uuidString.lowercased()
        defaults?.set(id, forKey: deviceIDKey)
        return id
    }

    /// The secret the widget uses to read the signed-in user's notes. Created on first use and
    /// replaced at every sign-in, so a previous account's widget access can't carry over.
    static func widgetSecret(renew: Bool = false) -> String {
        let defaults = UserDefaults(suiteName: appGroup)
        if !renew, let secret = defaults?.string(forKey: widgetSecretKey) { return secret }
        var generator = SystemRandomNumberGenerator()
        let secret = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
        defaults?.set(secret, forKey: widgetSecretKey)
        return secret
    }

    /// Gives the widget a fresh secret when a different account signs in on this phone, so the
    /// previous account's notes can't be read with the old one.
    static func prepareWidgetAccess(forUser userID: UUID) {
        let defaults = UserDefaults(suiteName: appGroup)
        guard defaults?.string(forKey: widgetUserKey) != userID.uuidString else { return }
        defaults?.set(userID.uuidString, forKey: widgetUserKey)
        _ = widgetSecret(renew: true)
    }

    /// Forgets the widget's access and its notes, e.g. on sign-out.
    static func clearWidgetAccess() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: widgetSecretKey)
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: widgetUserKey)
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: notesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private struct WidgetNote: Codable {
        let text: String
        let senderName: String
        let senderInitials: String
        let senderColor: String
        let sentAt: Date
        let expiresAt: Date
    }

    static func publish(notes: [Note], friends: [Person], currentUser: Person?) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        let received: [WidgetNote] = notes.compactMap { note in
            guard note.recipientID == currentUser?.id, !note.isExpired,
                  let sender = friends.first(where: { $0.id == note.senderID }) else { return nil }
            return WidgetNote(
                text: note.text,
                senderName: sender.name,
                senderInitials: sender.initials,
                senderColor: sender.color.rawValue,
                sentAt: note.sentAt,
                expiresAt: note.expiresAt
            )
        }

        if let data = try? JSONEncoder().encode(received) {
            defaults.set(data, forKey: notesKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
