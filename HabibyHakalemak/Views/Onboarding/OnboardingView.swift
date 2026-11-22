//
//  OnboardingView.swift
//  Kelmteen
//

import SwiftUI

/// Sign-up flow: welcome → phone number → verification code → name.
/// Returning users skip the name step: verifying their code signs them straight in.
struct OnboardingView: View {
    enum Step: Hashable {
        case phone
        /// `phone` is in E.164 format.
        case code(phone: String)
        case name
    }

    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.phone) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .phone:
                        PhoneStepView { path.append(.code(phone: $0)) }
                    case .code(let phone):
                        CodeStepView(phone: phone) { path.append(.name) }
                    case .name:
                        NameStepView()
                    }
                }
        }
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // A small pile of sample notes to set the mood.
            ZStack {
                sampleCard("Thinking of you", color: .bubblegum)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -80, y: -70)
                sampleCard("Good luck today!", color: .sky)
                    .rotationEffect(.degrees(8))
                    .offset(x: 80, y: -30)
                sampleCard("Coffee later?", color: .sunshine)
                    .rotationEffect(.degrees(-2))
                    .offset(y: 80)
            }
            .frame(height: 340)
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Kelmteen")
                    .font(.largeTitle)
                    .bold()
                Text("Little notes from your people,\nright on your Home Screen.")
                    .font(.title3)
                    .foregroundStyle(Color.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.ink)

            Spacer()

            VStack(spacing: 12) {
                Button("Get Started", action: onGetStarted)
                    .buttonStyle(PillButtonStyle())
                Text("By continuing, you agree to Kelmteen's [Terms](https://kelmteen.ahmedshaheen.com/terms) and [Privacy Policy](https://kelmteen.ahmedshaheen.com/privacy).")
                    .font(.footnote)
                    .foregroundStyle(Color.ink.opacity(0.6))
                    .tint(Color.ink)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
    }

    private func sampleCard(_ text: LocalizedStringKey, color: Color) -> some View {
        NoteCard(color: color) {
            Text(text).font(.title3)
        }
        .frame(width: 160, height: 160)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

// MARK: - Steps

private struct PhoneStepView: View {
    let onContinue: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var phone = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let e164 = PhoneNumber.e164(from: phone)
        OnboardingStep(
            title: "What's your number?",
            subtitle: "We'll text you a code to verify it.",
            buttonTitle: "Continue",
            isButtonEnabled: e164 != nil,
            action: {
                guard let e164 else { return }
                try await model.sendCode(to: e164)
                onContinue(e164)
            }
        ) {
            TextField("+20 100 123 4567", text: $phone)
                // Phone numbers always read left to right.
                .environment(\.layoutDirection, .leftToRight)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($isFocused)
                .onboardingField()
        }
        .onAppear { isFocused = true }
    }
}

private struct CodeStepView: View {
    let phone: String
    /// Called for new users, who still need to choose a name.
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingStep(
            title: "Enter the code",
            subtitle: "Sent to \(phone.leftToRightIsolated).",
            buttonTitle: "Verify",
            isButtonEnabled: code.count == 6,
            action: {
                let isReturningUser = try await model.verify(code: code, phone: phone)
                if !isReturningUser { onContinue() }
            }
        ) {
            TextField("123456", text: $code)
                .environment(\.layoutDirection, .leftToRight)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .onboardingField()
                .onChange(of: code) {
                    code = String(code.filter(\.isNumber).prefix(6))
                }
        }
        .onAppear { isFocused = true }
    }
}

private struct NameStepView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        OnboardingStep(
            title: "What should friends call you?",
            subtitle: "This shows up on their widget with your notes.",
            buttonTitle: "Create Account",
            isButtonEnabled: !trimmedName.isEmpty,
            action: { try await model.createProfile(name: trimmedName) }
        ) {
            TextField("Your name", text: $name)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($isFocused)
                .onboardingField()
        }
        .onAppear { isFocused = true }
    }
}

/// Shared layout for each sign-up step: a title, one field, and a big button at the bottom.
private struct OnboardingStep<Field: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let isButtonEnabled: Bool
    /// Runs when the button is tapped. Errors are shown in an alert.
    let action: () async throws -> Void
    @ViewBuilder var field: Field

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.largeTitle)
                .bold()
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Color.ink.opacity(0.65))
            field
                .padding(.top, 20)
            Spacer()
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .safeAreaInset(edge: .bottom) {
            Button(action: run) {
                if isWorking {
                    ProgressView()
                        .tint(Color.ink)
                } else {
                    Text(buttonTitle)
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!isButtonEnabled || isWorking)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
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

    private func run() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await action()
            } catch {
                errorMessage = error.userFacingMessage
            }
        }
    }
}

private extension View {
    func onboardingField() -> some View {
        font(.title2)
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
}
