//
//  InviteView.swift
//  Kelmteen
//

import SwiftUI

/// "Add <name> as your friend?", shown when the user opens someone's invite link or signs up
/// with a number someone invited. If the user blocked the inviter, it offers to unblock first.
struct InviteView: View {
    let invite: Invite

    @Environment(AppModel.self) private var model
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isReporting = false

    var body: some View {
        let inviter = invite.inviter

        VStack(spacing: 24) {
            Spacer()

            AvatarView(person: inviter, size: 140)

            VStack(spacing: 12) {
                if invite.isBlockedByMe {
                    Text("You blocked \(inviter.firstName)")
                        .font(.largeTitle)
                        .bold()
                    Text("Unblock \(inviter.firstName) to accept their invite.")
                        .font(.title3)
                        .foregroundStyle(Color.ink.opacity(0.7))
                } else {
                    Text("Add \(inviter.firstName) as your friend?")
                        .font(.largeTitle)
                        .bold()
                    Text("\(inviter.name) invited you to Kelmteen. Friends can send each other little notes that show up on their Home Screen.")
                        .font(.title3)
                        .foregroundStyle(Color.ink.opacity(0.7))
                }
            }
            .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 16) {
                Button {
                    Task { await primaryAction() }
                } label: {
                    if isWorking {
                        ProgressView()
                            .tint(Color.lightBackground)
                    } else {
                        Text(invite.isBlockedByMe ? "Unblock \(inviter.firstName)" : "Add \(inviter.firstName)")
                    }
                }
                .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground))

                if invite.isBlockedByMe {
                    // Leaves them blocked; the invite can be opened again later.
                    Button("Close") {
                        model.close(invite)
                    }
                    .font(.headline)
                } else {
                    Button("No Thanks") {
                        model.decline(invite)
                    }
                    .font(.headline)
                }
            }
            .disabled(isWorking)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(inviter.color.color.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Report") { isReporting = true }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.ink.opacity(0.7))
                .padding(20)
                .disabled(isWorking)
        }
        .sheet(isPresented: $isReporting, onDismiss: {
            // If they blocked the inviter from the report screen, this invite is done.
            if !invite.isBlockedByMe && model.isBlocked(inviter.id) {
                model.close(invite)
            }
        }) {
            ReportView(person: inviter)
        }
        // Swiping away would leave the invite unanswered; the buttons decide.
        .interactiveDismissDisabled()
        .alert(
            invite.isBlockedByMe ? "Couldn't Unblock" : "Couldn't Add Friend",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func primaryAction() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if invite.isBlockedByMe {
                try await model.unblockFromInvite(invite)
            } else {
                try await model.accept(invite)
            }
        } catch {
            errorMessage = error.userFacingMessage
        }
    }
}

#Preview {
    InviteView(invite: Invite(
        code: "aB3x-9Qk",
        inviter: Person(name: "Lily Light", phone: "", color: .bubblegum)
    ))
    .environment(AppModel.preview)
}

#Preview("Blocked") {
    InviteView(invite: Invite(
        code: "aB3x-9Qk",
        inviter: Person(name: "Lily Light", phone: "", color: .bubblegum),
        isBlockedByMe: true
    ))
    .environment(AppModel.preview)
}
