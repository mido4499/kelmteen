//
//  ComposeView.swift
//  Kelmteen
//

import SwiftUI

/// Write a note and send it to a friend's widget (Figma screens 1–3).
struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var isSending = false
    @State private var sendErrorMessage: String?
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
        // Tapping any empty space closes the keyboard without sending.
        .background(
            Color.lightBackground
                .ignoresSafeArea()
                .onTapGesture { isEditing = false }
        )
        .onChange(of: text) {
            // The field grows to fit multiple lines, so Return types a newline instead of
            // submitting. Treat it as "Done" instead: notes are short and single-paragraph.
            if text.contains("\n") {
                text = text.replacingOccurrences(of: "\n", with: "")
                isEditing = false
            }
            if text.count > AppModel.maxNoteLength {
                text = String(text.prefix(AppModel.maxNoteLength))
            }
        }
    }

    private func content(for recipient: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to")
                .font(.title3)
                .foregroundStyle(Color.ink.opacity(0.5))

            RecipientPicker(
                friends: model.friends,
                selection: recipient
            ) { friend in
                model.selectedRecipientID = friend.id
            }

            Spacer(minLength: 12)

            editor
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
                .noteTextDirection(text)
                .focused($isEditing)
                .submitLabel(.done)
        }
        .onTapGesture { isEditing = true }
    }

    // MARK: Bottom bar

    private func bottomBar(for recipient: Person) -> some View {
        Button {
            Task { await send(to: recipient) }
        } label: {
            HStack {
                Text("Send to \(recipient.firstName)")
                Spacer()
                if isSending {
                    ProgressView()
                        .tint(Color.ink)
                } else {
                    Image(systemName: "paperplane")
                        .flipsForRightToLeftLayoutDirection(true)
                }
            }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(trimmedText.isEmpty || isSending)
        .alert(
            "Couldn't Send Note",
            isPresented: Binding(
                get: { sendErrorMessage != nil },
                set: { if !$0 { sendErrorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(sendErrorMessage ?? "")
        }
    }

    private func send(to recipient: Person) async {
        isEditing = false
        isSending = true
        defer { isSending = false }
        do {
            try await model.send(trimmedText, to: recipient)
            // Start fresh for the next note and show the friends list, where the friend's
            // page now has the note just sent.
            text = ""
            model.selectedRecipientID = nil
            model.selectedTab = .friends
        } catch {
            // Keep the text so nothing is lost.
            sendErrorMessage = String(localized: "Check your connection and try again.")
        }
    }
}

/// The horizontal row of friend avatars at the top of the compose screen.
private struct RecipientPicker: View {
    let friends: [Person]
    let selection: Person
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
