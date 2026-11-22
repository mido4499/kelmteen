//
//  ContactsView.swift
//  Kelmteen
//

import Contacts
import ContactsUI
import SwiftUI
import UIKit

/// The user's contacts, with people already on Kelmteen first. Tapping "Invite" opens WhatsApp
/// with a prefilled message containing the user's invite link.
struct ContactsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var access = DeviceContacts.authorizationStatus
    @State private var contacts: [ContactEntry]?
    @State private var searchText = ""
    @State private var invitingID: ContactEntry.ID?
    @State private var isManagingAccess = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch access {
            case .authorized, .limited:
                contactList
            case .notDetermined:
                consent
            default:
                denied
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
        .task(id: access) {
            if access == .authorized || access == .limited {
                await loadContacts()
            }
        }
        .contactAccessPicker(isPresented: $isManagingAccess) { _ in
            Task { await loadContacts() }
        }
        .alert(
            "Something went wrong",
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

    // MARK: States

    private var consent: some View {
        ContentUnavailableView {
            Label("Find Your Friends", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("See which of your contacts are on Kelmteen. Numbers are hashed before they leave your phone, and your contacts are never stored.")
        } actions: {
            Button("Allow Contacts") {
                Task { access = await DeviceContacts.requestAccess() }
            }
            .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground, size: .regular))
            .frame(maxWidth: 240)
        }
        .foregroundStyle(Color.ink)
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("Contacts Are Off", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("Allow access to Contacts in Settings to invite your friends.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground, size: .regular))
            .frame(maxWidth: 240)
        }
        .foregroundStyle(Color.ink)
    }

    private var contactList: some View {
        let visible = filteredContacts
        let onApp = visible.filter { $0.user != nil }
        let notOnApp = visible.filter { $0.user == nil }

        return List {
            if access == .limited {
                Section {
                    Button("Choose More Contacts", systemImage: "plus.circle") {
                        isManagingAccess = true
                    }
                } footer: {
                    Text("You've shared some of your contacts with Kelmteen.")
                }
            }

            if !onApp.isEmpty {
                Section("On Kelmteen") {
                    ForEach(onApp) { row(for: $0) }
                }
            }

            if !notOnApp.isEmpty {
                Section("Invite to Kelmteen") {
                    ForEach(notOnApp) { row(for: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search contacts")
        .refreshable { await loadContacts() }
        .overlay {
            if contacts == nil {
                ProgressView()
            } else if visible.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Contacts", systemImage: "person.crop.circle",
                                           description: Text("Contacts with phone numbers show up here."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private func row(for contact: ContactEntry) -> some View {
        ContactRow(
            contact: contact,
            isFriend: contact.user.flatMap { model.friend(id: $0.id) } != nil,
            isBlocked: contact.user.map { model.isBlocked($0.id) } ?? false,
            isInviting: invitingID == contact.id
        ) {
            Task { await invite(contact) }
        }
    }

    private var filteredContacts: [ContactEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return contacts ?? [] }
        return (contacts ?? []).filter { $0.name.localizedStandardContains(query) }
    }

    // MARK: Actions

    private func loadContacts() async {
        do {
            contacts = try await model.loadContacts()
        } catch {
            contacts = contacts ?? []
            errorMessage = error.userFacingMessage
        }
    }

    private func invite(_ contact: ContactEntry) async {
        invitingID = contact.id
        defer { invitingID = nil }
        do {
            openURL(try await model.whatsAppInvite(for: contact))
        } catch {
            errorMessage = error.userFacingMessage
        }
    }
}

private struct ContactRow: View {
    let contact: ContactEntry
    let isFriend: Bool
    let isBlocked: Bool
    let isInviting: Bool
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App users get their colored avatar; everyone else gets a plain person icon.
            if let user = contact.user {
                AvatarView(person: user, size: 44)
            } else {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(Color.ink.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .background(Color.ink.opacity(0.08), in: .circle)
                    .accessibilityHidden(true)
            }

            Text(contact.name)
                .font(.headline)
                .foregroundStyle(Color.ink)

            Spacer()

            if isFriend {
                Text(LocalizedStringResource("contactStatus.friends", defaultValue: "Friends",
                                             comment: "Status next to a contact who is already a friend"))
                    .font(.subheadline)
                    .foregroundStyle(Color.ink.opacity(0.5))
            } else if isBlocked {
                // Unblock from Me → Blocked first; inviting a blocked person makes no sense.
                Text(LocalizedStringResource("contactStatus.blocked", defaultValue: "Blocked",
                                             comment: "Status next to a single contact the user blocked"))
                    .font(.subheadline)
                    .foregroundStyle(Color.ink.opacity(0.5))
            } else {
                Button(action: onInvite) {
                    if isInviting {
                        ProgressView()
                    } else {
                        Text("Invite")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(contact.user?.color.color ?? Color.sky)
                .foregroundStyle(Color.ink)
                .disabled(isInviting)
                .accessibilityLabel("Invite \(contact.name)")
            }
        }
        .listRowBackground(Color.white.opacity(0.6))
    }
}

#Preview {
    NavigationStack {
        ContactsView()
            .navigationTitle("Add Friends")
    }
    .environment(AppModel.preview)
}
