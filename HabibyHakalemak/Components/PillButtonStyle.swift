//
//  PillButtonStyle.swift
//  Kelmteen
//

import SwiftUI

/// The big rounded buttons from the design, e.g. "Send to Ahmed" and "Add Friends".
struct PillButtonStyle: ButtonStyle {
    var background: Color = .sky
    var foreground: Color = .ink
    var size: PillSize = .large

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pill(background: background, foreground: foreground, size: size)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

enum PillSize {
    /// Full capsule, used for the main action on a screen.
    case large
    /// Shorter rounded rectangle, used for secondary actions like "Add Friends".
    case regular
}

extension View {
    /// Styles content like a pill button without making it tappable (e.g. the "Sent to Ahmed" status).
    func pill(background: Color, foreground: Color = .ink, size: PillSize = .large) -> some View {
        let shape: AnyShape = size == .large
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

        return self
            .font(size == .large ? .title : .title2)
            .fontWeight(size == .large ? .semibold : .bold)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, size == .large ? 20 : 16)
            .frame(maxWidth: .infinity, minHeight: size == .large ? 83 : 50)
            .background(background, in: shape)
            .contentShape(shape)
    }
}
