//
//  ComposeView.swift
//  HabibyHakalemak
//

import SwiftUI

/// Write a note and send it to a friend's widget (Figma screens 1–3).
struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var sentNote: Note?
    @FocusState private var isEditing: Bool

    private var recipient: Person? {
        model.selectedRecipientID.flatMap(model.friend(id:)) ?? model.friends.first
    }

    /// Notes always use the sender's color, matching how they'll look on the friend's widget.
    private var noteColor: Color {
        model.currentUser?.color.color ?? Color.sky
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if let recipient {
                content(for: recipient)
            } else {
                ContentUnavailableView {
                    Label("No Friends Yet", systemImage: "person.2")
                } description: {
                    Text("Add a friend to start sending them notes.")
                } actions: {
                    Button("Add Friends") { model.selectedTab = .friends }
                        .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground, size: .regular))
                        .frame(maxWidth: 240)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
        .onChange(of: text) {
            if text.count > AppModel.maxNoteLength {
                text = String(text.prefix(AppModel.maxNoteLength))
            }
        }
    }

    private func content(for recipient: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sentNote == nil ? "Send to" : "Sent to")
                .font(.title3)
                .foregroundStyle(Color.ink.opacity(0.5))

            RecipientPicker(
                friends: model.friends,
                selection: recipient,
                sentTo: sentNote == nil ? nil : recipient
            ) { friend in
                model.selectedRecipientID = friend.id
            }
            .disabled(sentNote != nil)

            Spacer(minLength: 12)

            Group {
                if let sentNote {
                    sentConfirmation(note: sentNote, recipient: recipient)
                } else {
                    editor
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .safeAreaInset(edge: .bottom) {
            bottomBar(for: recipient)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    // MARK: Editing

    private var editor: some View {
        NoteCard(
            color: noteColor,
            footnote: "\(text.count)/\(AppModel.maxNoteLength)",
            sender: model.currentUser,
            senderLabel: "You"
        ) {
            TextField("Write a note…", text: $text, axis: .vertical)
                .font(.note(for: text))
                .focused($isEditing)
        }
        .onTapGesture { isEditing = true }
    }

    // MARK: Sent

    private func sentConfirmation(note: Note, recipient: Person) -> some View {
        VStack(spacing: 28) {
            NoteCard(color: noteColor, sender: model.currentUser, senderLabel: "You") {
                Text(note.text)
                    .font(.note(for: note.text))
            }
            .rotationEffect(.degrees(3))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    // Decorative badge peeking over the card's corner, as in the design.
                    .offset(x: 10, y: -14)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Text("Sent!")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.ink)
                Text("Your note is on its way to \(recipient.firstName).")
                    .font(.body)
                    .foregroundStyle(Color.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: Bottom bar

    @ViewBuilder
    private func bottomBar(for recipient: Person) -> some View {
        if sentNote != nil {
            VStack(spacing: 14) {
                HStack {
                    Text("Sent to \(recipient.firstName)")
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .pill(background: .sentGreen)
                .accessibilityElement(children: .combine)

                Button("Write another note") {
                    withAnimation(.spring) {
                        sentNote = nil
                        text = ""
                    }
                }
                .font(.headline)
                .fontWeight(.medium)
            }
        } else {
            Button(action: { send(to: recipient) }) {
                HStack {
                    Text("Send to \(recipient.firstName)")
                    Spacer()
                    Image(systemName: "paperplane")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(trimmedText.isEmpty)
        }
    }

    private func send(to recipient: Person) {
        isEditing = false
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            sentNote = model.send(trimmedText, to: recipient)
        }
    }
}

/// The horizontal row of friend avatars at the top of the compose screen.
private struct RecipientPicker: View {
    let friends: [Person]
    let selection: Person
    let sentTo: Person?
    let onSelect: (Person) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(friends) { friend in
                    Button {
                        onSelect(friend)
                    } label: {
                        AvatarView(person: friend)
                            .padding(3)
                            .overlay {
                                if friend.id == selection.id {
                                    Circle().strokeBorder(Color.ink.opacity(0.6), lineWidth: 1.5)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if friend.id == sentTo?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .green)
                                        .background(.white, in: .circle)
                                        .transition(.scale)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(friend.id == selection.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    ComposeView()
        .environment(AppModel.preview)
}
