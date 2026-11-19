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
    static let appGroup = "group.com.ahmedshaheen.kelmteen"
    static let notesKey = "receivedNotes"
    /// Written by the app at sign-in (see WidgetSync); lets the widget read the user's notes.
    static let widgetSecretKey = "widgetSecret"

    // Public values; the server only returns notes for a valid widget secret.
    private static let projectURL = URL(string: "https://slwarapujtjzjtlhdciw.supabase.co")!
    private static let publishableKey = "sb_publishable_OuSLIA4YfvWOaI8B1T-fFw__2cY17Mm"

    /// The most recent unexpired note the user received.
    static func latestNote(at date: Date = .now) -> WidgetNote? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: notesKey),
              let notes = try? JSONDecoder().decode([WidgetNote].self, from: data) else { return nil }
        return notes
            .filter { $0.expiresAt > date }
            .max { $0.sentAt < $1.sentAt }
    }

    /// Loads the user's notes from the server, saves them for next time, and returns the
    /// newest. Falls back to the last saved notes when offline or signed out.
    static func fetchLatestNote(at date: Date = .now) async -> WidgetNote? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let secret = defaults.string(forKey: widgetSecretKey) else {
            return latestNote(at: date)
        }
        do {
            let data = try await callServer("widget_notes", body: ["secret": secret])
            let notes = try JSONDecoder().decode([ServerNote].self, from: data).map(\.widgetNote)
            defaults.set(try JSONEncoder().encode(notes), forKey: notesKey)
        } catch {
            // Keep showing whatever was saved last.
        }
        return latestNote(at: date)
    }

    /// Reports a new push token to the server so note pushes reach this widget.
    static func savePushToken(_ token: Data) async {
        guard let secret = UserDefaults(suiteName: appGroup)?.string(forKey: widgetSecretKey) else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        _ = try? await callServer("set_widget_push_token", body: ["secret": secret, "push_token": hex])
    }

    /// Calls a server function with the publishable key and returns the response body.
    private static func callServer(_ function: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: projectURL.appending(path: "rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// A row from the server's `widget_notes` function. Times are seconds since 1970.
private struct ServerNote: Decodable {
    let noteText: String
    let senderName: String
    let senderColor: String
    let sentAt: Double
    let expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case noteText = "note_text"
        case senderName = "sender_name"
        case senderColor = "sender_color"
        case sentAt = "sent_at"
        case expiresAt = "expires_at"
    }

    var widgetNote: WidgetNote {
        let initials = senderName.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return WidgetNote(
            text: noteText,
            senderName: senderName,
            senderInitials: initials,
            senderColor: senderColor,
            sentAt: Date(timeIntervalSince1970: sentAt),
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
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
