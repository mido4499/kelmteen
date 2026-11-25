//
//  AppLanguage.swift
//  Kelmteen
//

import SwiftUI
import WidgetKit

/// The app's language. Kelmteen defaults to Arabic whatever the phone's language is,
/// and people can switch to English on the Welcome screen or in Me → Language.
///
/// It's applied as the SwiftUI locale and layout direction at the root of the app, so it
/// takes effect immediately. It's stored in the App Group so the widget follows it too,
/// and saved as the app's iOS language so system-drawn text matches from the next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"

    static let storageKey = "appLanguage"
    static let store = UserDefaults(suiteName: WidgetSync.appGroup) ?? .standard

    static var current: AppLanguage {
        store.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .arabic
    }

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }
    var layoutDirection: LayoutDirection { self == .arabic ? .rightToLeft : .leftToRight }

    /// The language's own name, shown untranslated so people can always find theirs.
    var nativeName: String {
        switch self {
        case .arabic: "العربية"
        case .english: "English"
        }
    }

    /// Saves the choice for iOS-drawn text (alerts, permission prompts) and refreshes the widget.
    func applySystemWide() {
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension String {
    /// Like `String(localized:)`, but in the app's chosen language rather than the phone's.
    init(appLocalized resource: LocalizedStringResource) {
        var resource = resource
        resource.locale = AppLanguage.current.locale
        self.init(localized: resource)
    }
}

extension View {
    /// Applies the app's language and its reading direction to everything below.
    func appLanguage(_ language: AppLanguage) -> some View {
        environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
    }
}
