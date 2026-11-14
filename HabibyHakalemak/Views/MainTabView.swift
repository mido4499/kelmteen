//
//  MainTabView.swift
//  Kelmteen
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Write", systemImage: "square.and.pencil", value: AppTab.write) {
                ComposeView()
            }
            Tab("Friends", systemImage: "person.2.fill", value: AppTab.friends) {
                FriendsView()
            }
            Tab("Me", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.preview)
}
