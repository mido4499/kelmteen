//
//  FriendsView.swift
//  HabibyHakalemak
//

import SwiftUI

/// The list of friends (Figma screen 4).
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingFriend = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(model.friends) { friend in
                        NavigationLink(value: friend.id) {
                            FriendRow(friend: friend, hasNewNote: model.hasNote(from: friend))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .overlay {
                if model.friends.isEmpty {
                    ContentUnavailableView(
                        "No Friends Yet",
                        systemImage: "person.2",
                        description: Text("Add friends to send notes to their Home Screen.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add Friends") { isAddingFriend = true }
                    .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground, size: .regular))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 12)
            }
            .background(Color.lightBackground.ignoresSafeArea())
            .navigationTitle("Friends")
            .navigationDestination(for: Person.ID.self) { id in
                FriendDetailView(friendID: id)
            }
            .sheet(isPresented: $isAddingFriend) {
                AddFriendView()
            }
        }
    }
}

private struct FriendRow: View {
    let friend: Person
    let hasNewNote: Bool

    var body: some View {
        HStack {
            Text(friend.name)
                .font(.title2)
                .bold()
            Spacer()
            if hasNewNote {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .accessibilityLabel("New note on your widget")
            }
            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundStyle(Color.ink.opacity(0.5))
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(friend.color.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    FriendsView()
        .environment(AppModel.preview)
}
