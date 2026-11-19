//
//  SuspendedView.swift
//  Kelmteen
//

import SwiftUI

/// Shown instead of the app when a moderator has suspended the account.
struct SuspendedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Account Suspended", systemImage: "exclamationmark.lock")
        } description: {
            Text("Your account was suspended for going against Kelmteen's Terms. If you think this is a mistake, email us at \(KelmteenAPI.supportEmail).")
        } actions: {
            VStack(spacing: 16) {
                Link("Contact Us", destination: KelmteenAPI.supportURL)
                    .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground, size: .regular))
                    .frame(maxWidth: 240)
                Link("Read the Terms", destination: KelmteenAPI.termsURL)
                    .font(.headline)
                Button("Sign Out") { model.signOut() }
                    .font(.headline)
            }
        }
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
    }
}

#Preview {
    SuspendedView()
        .environment(AppModel.preview)
}
