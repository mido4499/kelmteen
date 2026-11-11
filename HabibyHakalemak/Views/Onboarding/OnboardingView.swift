//
//  OnboardingView.swift
//  HabibyHakalemak
//

import SwiftUI

/// Sign-up flow: welcome → phone number → verification code → name.
/// Verification is mocked until there's a backend — any 6-digit code works.
struct OnboardingView: View {
    enum Step: Hashable {
        case phone
        case code(phone: String)
        case name(phone: String)
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
                        CodeStepView(phone: phone) { path.append(.name(phone: phone)) }
                    case .name(let phone):
                        NameStepView(phone: phone)
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
                Text("Habiby Hakalemak")
                    .font(.largeTitle)
                    .bold()
                Text("Little notes from your people,\nright on your Home Screen.")
                    .font(.title3)
                    .foregroundStyle(Color.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.ink)

            Spacer()

            Button("Get Started", action: onGetStarted)
                .buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
    }

    private func sampleCard(_ text: String, color: Color) -> some View {
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
    @State private var phone = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingStep(
            title: "What's your number?",
            subtitle: "We'll text you a code to verify it.",
            buttonTitle: "Continue",
            isButtonEnabled: phone.filter(\.isNumber).count >= 8,
            action: { onContinue(phone) }
        ) {
            TextField("+20 100 123 4567", text: $phone)
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
    let onContinue: () -> Void
    @State private var code = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingStep(
            title: "Enter the code",
            subtitle: "Sent to \(phone).",
            buttonTitle: "Verify",
            isButtonEnabled: code.count == 6,
            action: onContinue
        ) {
            TextField("123456", text: $code)
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
    let phone: String
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
            action: { model.signUp(name: trimmedName, phone: phone) }
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
    let title: String
    let subtitle: String
    let buttonTitle: String
    let isButtonEnabled: Bool
    let action: () -> Void
    @ViewBuilder var field: Field

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
            Button(buttonTitle, action: action)
                .buttonStyle(PillButtonStyle())
                .disabled(!isButtonEnabled)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
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
