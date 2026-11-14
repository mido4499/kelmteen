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
