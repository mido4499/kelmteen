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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.hasRestoredSession {
                Color.lightBackground.ignoresSafeArea()
            } else if model.currentUser?.isSuspended == true {
                SuspendedView()
            } else if model.isSignedIn {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: model.isSignedIn)
        .task { await model.restoreSession() }
        // Pick up notes and friend changes that happened while the app was in the background.
        .onChange(of: scenePhase) {
            if scenePhase == .active, model.isSignedIn {
                Task { await model.refresh() }
            }
        }
        // Invite links (https://kelmteen.ahmedshaheen.com/i/<code>) can arrive either way
        // depending on how the app was opened; the model ignores duplicates.
        .onOpenURL { model.handleInviteLink($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                model.handleInviteLink(url)
            }
        }
        .sheet(item: $model.presentedInvite) { invite in
            InviteView(invite: invite)
        }
        // Deliberately vague: also shown when the link's owner blocked this user.
        .alert("This invite isn't available.", isPresented: $model.isShowingUnavailableInvite) {
            Button("OK") {}
        }
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
