//
//  FriendsView.swift
//  Kelmteen
//

import SwiftUI

/// The list of friends (Figma screen 4).
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingFriend = false
    /// Links each friend's pill to their page so the pill zooms open into it.
    @Namespace private var pillTransition

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(model.friends) { friend in
                        NavigationLink(value: friend.id) {
                            FriendRow(friend: friend, hasNewNote: model.hasNote(from: friend))
                                .matchedTransitionSource(id: friend.id, in: pillTransition) { source in
                                    source.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
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
                    .navigationTransition(.zoom(sourceID: id, in: pillTransition))
            }
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $isAddingFriend) {
                NavigationStack {
                    ContactsView()
                        .navigationTitle("Add Friends")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", systemImage: "checkmark") { isAddingFriend = false }
                            }
                        }
                }
            }
        }
    }
}

private struct FriendRow: View {
    let friend: Person
    let hasNewNote: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Only real photos show here; friends without one get just their name.
            if friend.hasPhoto {
                PersonPhoto(person: friend)
                    .frame(width: 44, height: 44)
                    .clipShape(.circle)
            }
            Text(friend.name)
                .font(.title2)
                .bold()
            Spacer()
            if hasNewNote {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .accessibilityLabel("New note on your widget")
            }
            Image(systemName: "chevron.forward")
                .font(.headline)
                .foregroundStyle(Color.ink.opacity(0.5))
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Every pill is the same height, with or without a photo, and its content is centered.
        .frame(minHeight: 60, alignment: .center)
        .background(friend.color.color, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    FriendsView()
        .environment(AppModel.preview)
}
