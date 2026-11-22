//
//  ReportView.swift
//  Kelmteen
//

import SwiftUI

/// Report someone to the moderators: pick a reason, optionally explain, then offer to block.
/// The reported person is never told.
struct ReportView: View {
    let person: Person

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var isWorking = false
    @State private var isSent = false
    @State private var errorMessage: String?

    private static let maxDetailsLength = 500

    var body: some View {
        NavigationStack {
            Group {
                if isSent {
                    confirmation
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.lightBackground.ignoresSafeArea())
            .navigationTitle(isSent ? "" : "Report \(person.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isSent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", systemImage: "checkmark") {
                            Task { await send() }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(reason == nil || isWorking)
                    }
                }
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
        .interactiveDismissDisabled(isWorking)
    }

    private var form: some View {
        Form {
            Section {
                ForEach(ReportReason.allCases) { option in
                    Button {
                        reason = option
                    } label: {
                        HStack {
                            Text(option.title)
                            Spacer()
                            if reason == option {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(reason == option ? .isSelected : [])
                }
            } header: {
                Text("What's wrong?")
            } footer: {
                Text("\(person.firstName) won't know you reported them.")
            }

            Section("Details (optional)") {
                TextField("Anything that would help us review this", text: $details, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(isWorking)
        .onChange(of: details) {
            if details.count > Self.maxDetailsLength {
                details = String(details.prefix(Self.maxDetailsLength))
            }
        }
    }

    private var confirmation: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.ink)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Thanks for letting us know")
                    .font(.title)
                    .bold()
                Text("We'll review your report soon.")
                    .font(.body)
                    .foregroundStyle(Color.ink.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 16) {
                // Most people who report someone also want them gone.
                if !model.isBlocked(person.id) {
                    Button {
                        Task { await block() }
                    } label: {
                        if isWorking {
                            ProgressView()
                                .tint(Color.lightBackground)
                        } else {
                            Text("Block \(person.firstName)")
                        }
                    }
                    .buttonStyle(PillButtonStyle(background: .darkBackground, foreground: .lightBackground))
                }

                Button("Done") { dismiss() }
                    .font(.headline)
            }
            .disabled(isWorking)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func send() async {
        guard let reason else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.report(person, reason: reason, details: details)
            withAnimation { isSent = true }
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    private func block() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.block(person)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
        }
    }
}

#Preview {
    ReportView(person: Person(name: "Lily Light", phone: "", color: .bubblegum))
        .environment(AppModel.preview)
}
