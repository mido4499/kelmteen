//
//  NoteCard.swift
//  Kelmteen
//

import SwiftUI

/// The square sticky-note card from the design ("Input Preview"). It mirrors how a note
/// looks on the widget, and hosts either static text or the compose text field.
struct NoteCard<Content: View>: View {
    var color: Color = .sunshine
    var footnote: LocalizedStringResource?
    var sender: Person?
    var senderLabel: LocalizedStringResource?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Color.ink.opacity(0.55))
            }

            if sender != nil || senderLabel != nil {
                HStack {
                    if let sender {
                        AvatarView(person: sender, size: 56)
                    }
                    Spacer()
                    if let senderLabel {
                        Text(senderLabel)
                            .font(.title2)
                            .foregroundStyle(Color.ink.opacity(0.62))
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 275, maxHeight: 275)
        .aspectRatio(1, contentMode: .fit)
        .background(color, in: RoundedRectangle(cornerRadius: 46, style: .continuous))
    }
}

extension Font {
    /// Shrinks note text as it gets longer so up to 120 characters fit on the card,
    /// like the Short / Medium / Long variants in the design.
    static func note(for text: String) -> Font {
        switch text.count {
        case ..<24: .largeTitle
        case ..<60: .title2
        default: .body
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        NoteCard(
            footnote: "18 hours left",
            sender: Person(name: "Ahmed Wael", phone: "", color: .sky),
            senderLabel: "Ahmed"
        ) {
            Text("Coffee later?")
                .font(.note(for: "Coffee later?"))
        }
    }
    .padding()
    .background(Color.lightBackground)
}
