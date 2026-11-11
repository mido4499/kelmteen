//
//  WidgetNote.swift
//  NotesWidget
//

import SwiftUI

/// A received note as the widget sees it. The app writes these into the shared App Group
/// (see `WidgetSync` in the app target), so the JSON shape must stay in sync with it.
struct WidgetNote: Codable, Hashable {
    let text: String
    let senderName: String
    let senderInitials: String
    /// The sender's assigned palette color: "sky", "bubblegum" or "sunshine".
    let senderColor: String
    let sentAt: Date
    let expiresAt: Date

    var color: Color {
        switch senderColor {
        case "bubblegum": Color.bubblegum
        case "sunshine": Color.sunshine
        default: Color.sky
        }
    }

    /// "6 min. ago", as in the design.
    func sentDescription(relativeTo date: Date) -> String {
        guard date.timeIntervalSince(sentAt) >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: sentAt, relativeTo: date)
    }

    var senderFirstName: String {
        senderName.split(separator: " ").first.map(String.init) ?? senderName
    }
}

enum WidgetNoteStore {
    static let appGroup = "group.shaheen.HabibyHakalemak"
    static let notesKey = "receivedNotes"

    /// The most recent unexpired note the user received.
    static func latestNote(at date: Date = .now) -> WidgetNote? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: notesKey),
              let notes = try? JSONDecoder().decode([WidgetNote].self, from: data) else { return nil }
        return notes
            .filter { $0.expiresAt > date }
            .max { $0.sentAt < $1.sentAt }
    }
}

extension WidgetNote {
    static let samples: [WidgetNote] = [
        WidgetNote(text: "Coffee later?", senderName: "Ahmed Wael", senderInitials: "AW",
                   senderColor: "sky", sentAt: .now.addingTimeInterval(-6 * 60),
                   expiresAt: .now.addingTimeInterval(18 * 60 * 60)),
        WidgetNote(text: "Good luck on your exams! You've got this, I'm so proud of you.",
                   senderName: "Lily Light", senderInitials: "LL", senderColor: "bubblegum",
                   sentAt: .now.addingTimeInterval(-2 * 60 * 60),
                   expiresAt: .now.addingTimeInterval(22 * 60 * 60)),
        WidgetNote(text: "Thinking of you today. Call me when you're out of class, I have so much to tell you about the trip!",
                   senderName: "Maya Adam", senderInitials: "MA", senderColor: "sunshine",
                   sentAt: .now.addingTimeInterval(-30 * 60),
                   expiresAt: .now.addingTimeInterval(23 * 60 * 60))
    ]
}
