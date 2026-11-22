//
//  AccountView.swift
//  Kelmteen
//

import SwiftUI
import PhotosUI

/// The user's account and settings (Figma screen 7).
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingSignOut = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var photoErrorMessage: String?
    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var deletionErrorMessage: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                if let user = model.currentUser {
                    Section {
                        HStack(spacing: 16) {
                            // Tapping the avatar is the only way to change the photo.
                            PhotosPicker(selection: $photoSelection, matching: .images) {
                                AvatarView(person: user, size: 64)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "pencil")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.ink)
                                            .padding(5)
                                            .background(.white, in: .circle)
                                            // Nudges the badge past the corner; guides mirror in right-to-left.
                                            .alignmentGuide(.trailing) { $0[.trailing] - 3 }
                                            .alignmentGuide(.bottom) { $0[.bottom] - 3 }
                                    }
                            }
                            // Borderless keeps the rest of the row from opening the picker.
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Change profile photo")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text(user.phone.leftToRightIsolated)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ink.opacity(0.6))
                            }
                        }
                        .foregroundStyle(Color.ink)
                        .padding(.vertical, 4)
                    }
                    .accountRowStyle()
                }

                Section {
                    // Notes always reach the widget; this only controls the extra notification.
                    Toggle(isOn: $model.notificationsEnabled) {
                        AccountRow(title: "Notifications", systemImage: "bell.fill")
                    }
                    NavigationLink { EditPhoneView() } label: {
                        AccountRow(title: "Edit phone number", systemImage: "phone.fill")
                    }
                    NavigationLink { EditNameView() } label: {
                        AccountRow(title: "Edit name", systemImage: "textformat")
                    }
                    NavigationLink { BlockedUsersView() } label: {
                        AccountRow(title: "Blocked", systemImage: "nosign")
                    }
                    Link(destination: KelmteenAPI.supportURL) {
                        AccountRow(title: "Contact Us", systemImage: "envelope.fill")
                    }
                    Link(destination: KelmteenAPI.termsURL) {
                        AccountRow(title: "Terms", systemImage: "doc.text.fill")
                    }
                    Link(destination: KelmteenAPI.privacyURL) {
                        AccountRow(title: "Privacy Policy", systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text("General")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.ink)
                        .textCase(nil)
                }
                .accountRowStyle()

                Section {
                    Button(role: .destructive) {
                        isConfirmingDeletion = true
                    } label: {
                        HStack {
                            Text("Delete Account")
                            if isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .font(.title3)
                        .fontWeight(.semibold)
                    }
                    .disabled(isDeleting)
                }
                .accountRowStyle()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(model.accountColor.ignoresSafeArea())
            .navigationTitle("My Account")
            .task(id: photoSelection) {
                guard let photoSelection,
                      let data = try? await photoSelection.loadTransferable(type: Data.self) else { return }
                do {
                    try await model.setProfilePhoto(data)
                } catch {
                    photoErrorMessage = error.userFacingMessage
                }
            }
            .alert("Delete your account?", isPresented: $isConfirmingDeletion) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your account, friends, notes and photo. It can't be undone.")
            }
            .alert(
                "Couldn't Delete Account",
                isPresented: Binding(
                    get: { deletionErrorMessage != nil },
                    set: { if !$0 { deletionErrorMessage = nil } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(deletionErrorMessage ?? "")
            }
            .alert(
                "Couldn't Update Photo",
                isPresented: Binding(
                    get: { photoErrorMessage != nil },
                    set: { if !$0 { photoErrorMessage = nil } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(photoErrorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        isConfirmingSignOut = true
                    }
                }
            }
            .alert("Sign out?", isPresented: $isConfirmingSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Yes, Sign Out", role: .destructive) { model.signOut() }
            } message: {
                Text("You'll need your phone number to sign back in.")
            }
        }
    }
}

extension AccountView {
    fileprivate func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await model.deleteAccount()
        } catch {
            deletionErrorMessage = String(localized: "Please check your connection and try again. If it keeps failing, email us at \(KelmteenAPI.supportEmail).")
        }
    }
}

private struct AccountRow: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
        } icon: {
            Image(systemName: systemImage)
                .font(.title2)
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 6)
    }
}

private extension AppModel {
    /// The account page uses the user's assigned color as its background.
    var accountColor: Color {
        currentUser?.color.color ?? Color.sky
    }
}

// MARK: - Edit screens

private struct EditNameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
            } footer: {
                Text("This is how you appear to your friends.")
            }
        }
        .accountFormStyle(model.accountColor)
        .navigationTitle("Edit Name")
        .onAppear { name = model.currentUser?.name ?? "" }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    model.updateCurrentUser { $0.name = name.trimmingCharacters(in: .whitespaces) }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct EditPhoneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""

    var body: some View {
        Form {
            Section {
                TextField("Phone number", text: $phone)
                    // Phone numbers always read left to right.
                    .environment(\.layoutDirection, .leftToRight)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } footer: {
                Text("Friends find you by your phone number.")
            }
        }
        .accountFormStyle(model.accountColor)
        .navigationTitle("Phone Number")
        .onAppear { phone = model.currentUser?.phone ?? "" }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") {
                    model.updateCurrentUser { $0.phone = phone }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(phone.filter(\.isNumber).count < 8)
            }
        }
    }
}

/// People the user has blocked, each with an Unblock button.
private struct BlockedUsersView: View {
    @Environment(AppModel.self) private var model
    @State private var personToUnblock: Person?
    @State private var personToReport: Person?
    @State private var errorMessage: String?

    var body: some View {
        List(model.blockedUsers) { person in
            HStack(spacing: 12) {
                AvatarView(person: person, size: 44)
                Text(person.name)
                    .font(.headline)
                Spacer()
                Button("Unblock") { personToUnblock = person }
                    .buttonStyle(.bordered)
                    .tint(Color.ink)
                    .accessibilityLabel("Unblock \(person.name)")
            }
            .foregroundStyle(Color.ink)
            .listRowBackground(Color.white.opacity(0.6))
            .swipeActions {
                Button("Report", systemImage: "exclamationmark.bubble") {
                    personToReport = person
                }
                .tint(.orange)
            }
        }
        .sheet(item: $personToReport) { person in
            ReportView(person: person)
        }
        .overlay {
            if model.blockedUsers.isEmpty {
                ContentUnavailableView(
                    "No Blocked People",
                    systemImage: "nosign",
                    description: Text("People you block show up here.")
                )
                .foregroundStyle(Color.ink)
            }
        }
        .accountFormStyle(model.accountColor)
        .navigationTitle("Blocked")
        .task { await model.refreshBlockedUsers() }
        .alert(
            "Unblock \(personToUnblock?.firstName ?? "")?",
            isPresented: Binding(
                get: { personToUnblock != nil },
                set: { if !$0 { personToUnblock = nil } }
            ),
            presenting: personToUnblock
        ) { person in
            Button("Cancel", role: .cancel) {}
            Button("Unblock") {
                Task {
                    do {
                        try await model.unblock(person)
                    } catch {
                        errorMessage = error.userFacingMessage
                    }
                }
            }
        } message: { _ in
            Text("If you were friends before you blocked them, you'll be friends again.")
        }
        .alert(
            "Couldn't Unblock",
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
}

private extension View {
    /// Rows sit directly on the yellow background, with no cards or separators, as in the design.
    func accountRowStyle() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
    }

    func accountFormStyle(_ color: Color) -> some View {
        scrollContentBackground(.hidden)
            .background(color.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AccountView()
        .environment(AppModel.preview)
}
