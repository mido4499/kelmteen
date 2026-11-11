//
//  AvatarView.swift
//  HabibyHakalemak
//

import SwiftUI
import UIKit

/// A circular avatar showing a person's photo, or their initials on their palette color.
struct AvatarView: View {
    let person: Person
    var size: CGFloat = 63

    var body: some View {
        Circle()
            .fill(person.color.color)
            .overlay {
                if let data = person.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(.circle)
                } else {
                    Text(person.initials)
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(Color.ink)
                }
            }
            // A light ring keeps the avatar visible on a background of the same color,
            // e.g. on the user's own account page or note card.
            .overlay {
                Circle().strokeBorder(.white.opacity(0.7), lineWidth: max(1.5, size * 0.03))
            }
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(person.name)
    }
}

#Preview {
    HStack {
        AvatarView(person: Person(name: "Ahmed Wael", phone: "", color: .sky))
        AvatarView(person: Person(name: "Lily Light", phone: "", color: .bubblegum))
        AvatarView(person: Person(name: "Maya Adam", phone: "", color: .sunshine), size: 40)
    }
}
