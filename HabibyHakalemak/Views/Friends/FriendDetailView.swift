//
//  FriendDetailView.swift
//  HabibyHakalemak
//

import SwiftUI

/// A friend's page showing their latest note (Figma screens 5 and 6).
struct FriendDetailView: View {
    let friendID: Person.ID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingRemoval = false

    var body: some View {
        if let friend = model.friend(id: friendID) {
            content(for: friend)
        } else {
            ContentUnavailableView("Friend Removed", systemImage: "person.slash")
        }
    }

    private func content(for friend: Person) -> some View {
        // Received notes only ever appear on the widget, so this page shows the note
        // the current user sent, in the current user's color.
        let sentNote = model.latestNote(to: friend)
        let myColor = model.currentUser?.color.color ?? Color.sky

        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.largeTitle)
                    .bold()

                if model.hasNote(from: friend) {
                    Label("Sent you something! Check your widget.", systemImage: "sparkles")
                        .font(.footnote)
                } else {
                    Text("Nothing from \(friend.firstName) yet today")
                        .font(.footnote)
                }

                if let sentNote {
                    NoteCard(
                        color: myColor,
                        footnote: sentNote.timeLeftDescription,
                        sender: model.currentUser,
                        senderLabel: "You"
                    ) {
                        Text(sentNote.text)
                            .font(.note(for: sentNote.text))
                    }
                    // Keeps the card visible when both people share a color.
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 14)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Your note to \(friend.firstName): \(sentNote.text)")
                } else {
                    Text("You haven't sent \(friend.firstName) a note today.")
                        .font(.footnote)
                        .foregroundStyle(Color.ink.opacity(0.6))
                        .padding(.top, 14)
                }
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
        .background(friend.color.color.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            Button {
                model.startNote(to: friend)
            } label: {
                Image(systemName: "bubble.and.pencil")
                    .font(.largeTitle)
                    .foregroundStyle(Color.ink)
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(friend.color == model.currentUser?.color ? Color.lightBackground : myColor)
            .accessibilityLabel("Write to \(friend.firstName)")
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Remove Friend", systemImage: "person.badge.minus", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmationDialog(
            "Remove \(friend.firstName)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Friend", role: .destructive) {
                dismiss()
                model.remove(friend)
            }
        } message: {
            Text("You won't be able to send each other notes anymore.")
        }
    }
}

#Preview("With a note") {
    let model = AppModel.preview
    NavigationStack {
        FriendDetailView(friendID: model.friends[0].id)
    }
    .environment(model)
}

#Preview("Empty") {
    let model = AppModel.preview
    NavigationStack {
        FriendDetailView(friendID: model.friends[1].id)
    }
    .environment(model)
}
