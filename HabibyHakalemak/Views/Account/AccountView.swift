//
//  AccountView.swift
//  HabibyHakalemak
//

import SwiftUI
import PhotosUI

/// The user's account and settings (Figma screen 7).
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let user = model.currentUser {
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(person: user, size: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text(user.phone)
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
                    NavigationLink { NotificationSettingsView() } label: {
                        AccountRow(title: "Notifications", systemImage: "bell.fill")
                    }
                    NavigationLink { EditPhoneView() } label: {
                        AccountRow(title: "Edit phone number", systemImage: "phone.fill")
                    }
                    NavigationLink { EditNameView() } label: {
                        AccountRow(title: "Edit name", systemImage: "textformat")
                    }
                    NavigationLink { EditPhotoView() } label: {
                        AccountRow(title: "Edit profile photo", systemImage: "person.crop.circle.fill")
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
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .accountRowStyle()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(model.accountColor.ignoresSafeArea())
            .navigationTitle("My Account")
            .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut) {
                Button("Sign Out", role: .destructive) { model.signOut() }
            }
        }
    }
}

private struct AccountRow: View {
    let title: String
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

private struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("New notes from friends", isOn: $model.notificationsEnabled)
            } footer: {
                Text("Notes always show up on your widget. This controls whether you also get a notification.")
            }
        }
        .accountFormStyle(model.accountColor)
        .navigationTitle("Notifications")
    }
}

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

private struct EditPhotoView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 24) {
            if let user = model.currentUser {
                AvatarView(person: user, size: 160)
            }

            PhotosPicker(selection: $selection, matching: .images) {
                Text("Choose Photo")
            }
            .buttonStyle(PillButtonStyle(background: .lightBackground, size: .regular))

            if model.currentUser?.photoData != nil {
                Button("Remove Photo", role: .destructive) {
                    model.updateCurrentUser { $0.photoData = nil }
                }
                .font(.headline)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.accountColor.ignoresSafeArea())
        .navigationTitle("Profile Photo")
        .task(id: selection) {
            guard let selection,
                  let data = try? await selection.loadTransferable(type: Data.self) else { return }
            model.updateCurrentUser { $0.photoData = data }
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
