//
//  UserFacingError.swift
//  Kelmteen
//

import Foundation

extension Error {
    /// A short, translated message for an alert. Server and sign-in errors arrive in English,
    /// so known ones are mapped to the app's own wording and the rest get a generic message.
    var userFacingMessage: String {
        // Connection problems already come translated by the system.
        if let urlError = self as? URLError {
            return urlError.localizedDescription
        }

        let raw = localizedDescription
        for (fragment, message) in Self.knownMessages where raw.localizedCaseInsensitiveContains(fragment) {
            return String(localized: message)
        }
        return String(localized: "Something went wrong. Please try again.")
    }

    /// Fragments of server (see supabase/migrations) and sign-in error messages, with the
    /// wording to show instead.
    private static var knownMessages: [(String, LocalizedStringResource)] {
        [
            ("Create a profile first", "Finish setting up your profile first."),
            ("Invite not found", "This invite isn't available."),
            ("This invite isn't available", "This invite isn't available."),
            ("Sign in with a phone number first", "Sign in with your phone number first."),
            ("This person isn't on Kelmteen", "This person isn't on Kelmteen yet."),
            ("Unblock this person to accept their invite", "Unblock this person to accept their invite."),
            ("You can't add yourself", "You can't add yourself."),
            ("You can't block yourself", "You can't block yourself."),
            ("You can't report yourself", "You can't report yourself."),
            ("sent a lot of reports today", "You've sent a lot of reports today. Please try again tomorrow."),
            ("Your account is suspended", "Your account is suspended."),
            ("expired or is invalid", "That code is wrong or has expired."),
            ("For security purposes", "Too many tries. Wait a minute and try again."),
            ("rate limit", "Too many tries. Wait a minute and try again.")
        ]
    }
}
