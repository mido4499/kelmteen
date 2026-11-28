//
//  UserFacingError.swift
//  Kelmteen
//

import Foundation
import OSLog
import Supabase

extension Error {
    /// A clear, translated message for an alert, saying what went wrong and what to do next.
    ///
    /// Sign-in errors are recognised by Supabase's error code, the app's own server errors by
    /// their message (see supabase/migrations), and connection problems by type. The original
    /// error is always logged, and debug builds also show it under the message, so problems like
    /// an SMS provider rejecting a number are easy to diagnose.
    var userFacingMessage: String {
        Logger.errors.error("\(String(describing: self), privacy: .public)")

        if let message = connectionMessage ?? authMessage ?? serverMessage {
            return message
        }
        return String(appLocalized: "Something went wrong. Please try again.") + debugDetails
    }

    private var connectionMessage: String? {
        guard let urlError = self as? URLError else { return nil }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return String(appLocalized: "You're offline. Check your internet connection and try again.")
        case .timedOut:
            return String(appLocalized: "The connection timed out. Check your internet connection and try again.")
        default:
            // Already translated by the system.
            return urlError.localizedDescription
        }
    }

    /// Sign-in and phone verification errors, by Supabase's error code.
    private var authMessage: String? {
        guard let authError = self as? AuthError else { return nil }
        let message: LocalizedStringResource? = switch authError.errorCode {
        case .smsSendFailed:
            "We couldn't text a code to this number. Check that it's a mobile number that can receive texts, then try again. If it keeps happening, contact us."
        case .overSMSSendRateLimit:
            "Too many codes were sent to this number. Wait a few minutes before asking for another one."
        case .overRequestRateLimit:
            "Too many tries. Wait a minute and try again."
        case .otpExpired:
            "That code is wrong or has expired. Check it, or go back to get a new code."
        case .validationFailed:
            "That phone number doesn't look right. Check the country and number, then try again."
        case .phoneExists:
            "This number is already used by another account."
        case .phoneProviderDisabled, .signupDisabled:
            "Signing up with a phone number isn't available right now. Please try again later."
        case .userBanned:
            "Your account is suspended."
        default:
            nil
        }
        return message.map { String(appLocalized: $0) + debugDetails }
    }

    /// The app's own server errors and older-style sign-in errors, matched by their text.
    private var serverMessage: String? {
        let raw = localizedDescription
        return Self.knownMessages
            .first { raw.localizedCaseInsensitiveContains($0.fragment) }
            .map { String(appLocalized: $0.message) }
    }

    /// The original error under the message, in debug builds only.
    private var debugDetails: String {
        #if DEBUG
        let detail = (self as? AuthError)?.message ?? localizedDescription
        return "\n\n[Debug] \(detail)"
        #else
        return ""
        #endif
    }

    /// Fragments of server (see supabase/migrations) and sign-in error messages, with the
    /// wording to show instead.
    private static var knownMessages: [(fragment: String, message: LocalizedStringResource)] {
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
            ("already been registered", "This number is already used by another account."),
            ("phone_exists", "This number is already used by another account."),
            ("For security purposes", "Too many tries. Wait a minute and try again."),
            ("rate limit", "Too many tries. Wait a minute and try again.")
        ]
    }
}

extension Logger {
    /// Every error shown to the user, with its full original details (visible in Xcode's console).
    nonisolated static let errors = Logger(subsystem: "com.ahmedshaheen.kelmteen", category: "errors")
}
