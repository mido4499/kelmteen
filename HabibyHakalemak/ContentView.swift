//
//  ContentView.swift
//  Kelmteen
//
//  Created by Ahmed Shaheen on 11/8/26.
//

import SwiftUI

/// Shows sign-up until the user has an account, then the main tabs.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasRestoredSession {
                Color.lightBackground.ignoresSafeArea()
            } else if model.isSignedIn {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: model.isSignedIn)
        .task { await model.restoreSession() }
        // The palette is designed for light backgrounds only.
        .preferredColorScheme(.light)
    }
}

#Preview("Signed in") {
    ContentView()
        .environment(AppModel.preview)
}

#Preview("Signed out") {
    ContentView()
        .environment(AppModel())
}
