//
//  ProfilePhotos.swift
//  Kelmteen
//

import SwiftUI
import UIKit

enum ProfilePhotoProcessing {
    /// A square JPEG cropped from the center, small enough for avatars (roughly 20–40 KB).
    static func avatarJPEG(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = max(side / image.size.width, side / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        return square.jpegData(compressionQuality: 0.8)
    }
}

/// Keeps downloaded profile photos in memory. Every upload gets a new file name, so a cached
/// photo never goes stale.
final class PhotoCache {
    static let shared = PhotoCache()

    private let cache = NSCache<NSURL, UIImage>()

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// A person's profile photo: the one picked on this device, or their uploaded one. Draws
/// nothing until it has loaded, and nothing at all for people without a photo.
struct PersonPhoto: View {
    let person: Person

    @State private var downloaded: UIImage?

    var body: some View {
        Group {
            if let data = person.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let downloaded {
                Image(uiImage: downloaded)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: person.photoURL) {
            guard person.photoData == nil, let url = person.photoURL else {
                downloaded = nil
                return
            }
            downloaded = await PhotoCache.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
}
