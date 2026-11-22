//
//  TextDirection.swift
//  NotesWidget
//

import SwiftUI

// Same rules as the app's TextDirection.swift: a note is laid out in its own language's
// direction, regardless of the phone's language.

extension String {
    /// Whether the text reads right to left, judged by its first letter (Arabic, Hebrew…).
    var isRightToLeft: Bool {
        for scalar in unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
            default: return false
            }
        }
        return false
    }
}

extension View {
    /// Lays out a note's text in its own direction.
    func noteTextDirection(_ text: String) -> some View {
        multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, text.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
