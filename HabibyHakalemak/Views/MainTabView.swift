//
//  MainTabView.swift
//  Kelmteen
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Write", systemImage: "pencil", value: AppTab.write) {
                ComposeView()
            }
            Tab("Friends", systemImage: "heart", value: AppTab.friends) {
                FriendsView()
            }
            Tab(value: AppTab.account) {
                AccountView()
            } label: {
                Label {
                    Text("Me")
                } icon: {
                    meIcon
                }
            }
        }
    }

    /// The user's own avatar (photo, or initials on their color) for the Me tab. Tab bars
    /// only accept images, so the avatar is drawn into one, kept in full color.
    private var meIcon: Image {
        guard let user = model.currentUser else { return Image(systemName: "person.crop.circle") }
        let renderer = ImageRenderer(content: AvatarView(person: user, size: 28))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return Image(systemName: "person.crop.circle") }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}

#Preview {
    MainTabView()
        .environment(AppModel.preview)
}
