//
//  WidgetTutorialVideo.swift
//  Kelmteen
//

import AVFoundation
import SwiftUI

/// Renders `WidgetTutorialScene` into a short silent video, because Picture in Picture can
/// only show video. It's made on the phone so it's always in the user's language, mirrored
/// for right-to-left, and in their color. Finished videos are cached.
enum WidgetTutorialVideo {
    private static let framesPerSecond: Int32 = 24
    private static let scale: CGFloat = 2
    /// Bump when the scene changes so old cached videos aren't reused.
    private static let version = 1

    static func make(
        wallpaper: PaletteColor,
        locale: Locale,
        layoutDirection: LayoutDirection
    ) async throws -> URL {
        let language = locale.language.languageCode?.identifier ?? "en"
        let name = "widget-tutorial-v\(version)-\(language)-\(wallpaper.rawValue).mp4"
        let cache = URL.cachesDirectory.appending(path: name)
        if FileManager.default.fileExists(atPath: cache.path()) { return cache }

        let width = Int(WidgetTutorialScene.size.width * scale)
        let height = Int(WidgetTutorialScene.size.height * scale)
        let temporary = URL.temporaryDirectory.appending(path: UUID().uuidString + ".mp4")

        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(WidgetTutorialScene.duration * Double(framesPerSecond))
        for frame in 0..<frameCount {
            let time = Double(frame) / Double(framesPerSecond)
            let renderer = ImageRenderer(content:
                WidgetTutorialScene(time: time, wallpaper: wallpaper.color)
                    .environment(\.locale, locale)
                    .environment(\.layoutDirection, layoutDirection)
            )
            renderer.scale = scale
            guard let image = renderer.cgImage,
                  let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool) else { continue }

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))

            // Rendering happens on the main thread, so give the UI a turn now and then.
            if frame.isMultiple(of: 4) { await Task.yield() }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }

        try? FileManager.default.removeItem(at: cache)
        try FileManager.default.moveItem(at: temporary, to: cache)
        return cache
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return buffer
    }
}
