//
//  PhotoCropView.swift
//  Kelmteen
//

import SwiftUI

/// A photo picked for the profile, waiting to be cropped.
struct CroppingPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The usual "Move and Scale" screen: drag and pinch the photo inside a circle, then Choose.
struct PhotoCropView: View {
    let image: UIImage
    /// Called with the cropped avatar JPEG.
    let onChoose: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Zoom on top of the scale that makes the photo just fill the circle.
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    /// How far the photo's center is from the circle's center, in screen points.
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize = .zero

    private let maximumZoom: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) - 32
            let baseScale = max(diameter / image.size.width, diameter / image.size.height)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(
                        width: image.size.width * baseScale * zoom,
                        height: image.size.height * baseScale * zoom
                    )
                    .offset(offset)

                // Dims everything outside the circle.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addEllipse(in: circleRect(diameter: diameter, in: proxy.size))
                }
                .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Circle()
                    .strokeBorder(.white.opacity(0.8), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = clamped(
                                CGSize(
                                    width: offsetAtGestureStart.width + value.translation.width,
                                    height: offsetAtGestureStart.height + value.translation.height
                                ),
                                diameter: diameter, baseScale: baseScale
                            )
                        }
                        .onEnded { _ in offsetAtGestureStart = offset },
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(zoomAtGestureStart * value.magnification, 1), maximumZoom)
                            offset = clamped(offset, diameter: diameter, baseScale: baseScale)
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = zoom
                            offsetAtGestureStart = offset
                        }
                )
            )
            .overlay(alignment: .top) {
                Text("Move and Scale")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 16)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Choose") {
                        if let jpeg = ProfilePhotoProcessing.avatarJPEG(
                            from: image,
                            cropping: cropRect(diameter: diameter, baseScale: baseScale)
                        ) {
                            onChoose(jpeg)
                        }
                        dismiss()
                    }
                    .bold()
                }
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            // Drag and offset math are in screen coordinates, so the canvas never mirrors.
            .environment(\.layoutDirection, .leftToRight)
        }
        .background(.black)
        .accessibilityAction(named: "Zoom In") { zoom = min(zoom * 1.5, maximumZoom); zoomAtGestureStart = zoom }
        .accessibilityAction(named: "Zoom Out") {
            zoom = max(zoom / 1.5, 1)
            zoomAtGestureStart = zoom
        }
    }

    private func circleRect(diameter: CGFloat, in size: CGSize) -> CGRect {
        CGRect(
            x: (size.width - diameter) / 2,
            y: (size.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
    }

    /// Keeps the photo covering the whole circle.
    private func clamped(_ offset: CGSize, diameter: CGFloat, baseScale: CGFloat) -> CGSize {
        let scale = baseScale * zoom
        let maxX = max(0, (image.size.width * scale - diameter) / 2)
        let maxY = max(0, (image.size.height * scale - diameter) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    /// The part of the photo inside the circle, in the image's own points.
    private func cropRect(diameter: CGFloat, baseScale: CGFloat) -> CGRect {
        let scale = baseScale * zoom
        let side = diameter / scale
        return CGRect(
            x: image.size.width / 2 - offset.width / scale - side / 2,
            y: image.size.height / 2 - offset.height / scale - side / 2,
            width: side,
            height: side
        )
    }
}

#Preview {
    PhotoCropView(image: UIImage(systemName: "person.crop.square.fill")!) { _ in }
}
