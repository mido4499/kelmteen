//
//  AddFriendView.swift
//  HabibyHakalemak
//

import SwiftUI

/// Sheet for adding a friend by phone number.
struct AddFriendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.filter(\.isNumber).count >= 8
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } footer: {
                    Text("They'll get an invite to join if they're not on the app yet.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.lightBackground)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        model.addFriend(
                            name: name.trimmingCharacters(in: .whitespaces),
                            phone: phone
                        )
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!isValid)
                }
            }
        }
    }
}

#Preview {
    AddFriendView()
        .environment(AppModel.preview)
}
