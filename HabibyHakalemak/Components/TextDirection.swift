//
//  TextDirection.swift
//  Kelmteen
//

import SwiftUI

extension String {
    /// Whether the text reads right to left, judged by its first letter (Arabic, Hebrew…).
    /// Notes follow their own language, not the app's: an Arabic note stays right-aligned
    /// in the English UI, and an English note stays left-aligned in the Arabic UI.
    var isRightToLeft: Bool {
        for scalar in unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
            default: return false
            }
        }
        return false
    }

    /// Keeps a left-to-right run (like a phone number) in order inside Arabic sentences.
    var leftToRightIsolated: String {
        "\u{2066}\(self)\u{2069}"
    }
}

extension View {
    /// Lays out a note's text in its own direction. Empty text follows the app's direction.
    func noteTextDirection(_ text: String) -> some View {
        modifier(NoteTextDirection(text: text))
    }
}

private struct NoteTextDirection: ViewModifier {
    let text: String
    @Environment(\.layoutDirection) private var appDirection

    func body(content: Content) -> some View {
        let direction: LayoutDirection = text.isEmpty
            ? appDirection
            : (text.isRightToLeft ? .rightToLeft : .leftToRight)
        content
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, direction)
    }
}
