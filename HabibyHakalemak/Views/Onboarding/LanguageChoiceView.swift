//
//  LanguageChoiceView.swift
//  Kelmteen
//

import SwiftUI

/// The very first screen: choose العربية or English. It's written in both languages so
/// anyone can read it, and it has no navigation bar or tabs, so the screens after it are all
/// created in the chosen direction. Later changes go through Settings (see Me → Language).
struct LanguageChoiceView: View {
    @AppStorage(AppLanguage.storageKey, store: AppLanguage.store) private var language: AppLanguage = .arabic
    @AppStorage(AppLanguage.chosenKey, store: AppLanguage.store) private var hasChosenLanguage = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text(verbatim: "كلمتين")
                    .font(.largeTitle)
                    .bold()
                Text(verbatim: "Kelmteen")
                    .font(.title3)
                    .foregroundStyle(Color.ink.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text(verbatim: "اختار اللغة")
                Text(verbatim: "Choose your language")
            }
            .font(.headline)
            .foregroundStyle(Color.ink.opacity(0.75))

            Spacer()

            VStack(spacing: 14) {
                Button(AppLanguage.arabic.nativeName) { choose(.arabic) }
                    .buttonStyle(PillButtonStyle())
                    .environment(\.layoutDirection, .rightToLeft)
                Button(AppLanguage.english.nativeName) { choose(.english) }
                    .buttonStyle(PillButtonStyle(background: .white))
                    .environment(\.layoutDirection, .leftToRight)
            }

            Text(verbatim: "تقدر تغيرها بعدين من الإعدادات · You can change it later in Settings")
                .font(.footnote)
                .foregroundStyle(Color.ink.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
    }

    private func choose(_ choice: AppLanguage) {
        // Set the direction first, so the Welcome screen and everything after it is created in it.
        choice.applySystemWide()
        choice.applyToUIKit()
        language = choice
        hasChosenLanguage = true
    }
}

#Preview {
    LanguageChoiceView()
}
