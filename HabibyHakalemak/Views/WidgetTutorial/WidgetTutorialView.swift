//
//  WidgetTutorialView.swift
//  Kelmteen
//

import SwiftUI
import WidgetKit

/// Shows how to add the Kelmteen widget to the Home Screen. Shown once after sign-in
/// (when the phone has no Kelmteen widget yet) and from Me → Add the Widget.
///
/// The demo keeps playing in Picture in Picture while the user is on the Home Screen,
/// and when they come back the app checks whether the widget was added.
struct WidgetTutorialView: View {
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var playback = TutorialPlayback()
    @State private var isWidgetAdded = false
    @State private var startDate = Date.now

    private var wallpaper: PaletteColor { model.currentUser?.color ?? .sky }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(isWidgetAdded ? "Your widget is ready!" : "Put Kelmteen on your Home Screen")
                    .font(.title)
                    .bold()
                Text(isWidgetAdded
                     ? "Notes from friends will show up on it."
                     : "Notes from friends show up right on your widget. Here's how to add it.")
                    .font(.body)
                    .foregroundStyle(Color.ink.opacity(0.65))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.ink)
            .padding(.top, 24)

            demo
                .frame(maxHeight: .infinity)

            buttons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lightBackground.ignoresSafeArea())
        .animation(.default, value: isWidgetAdded)
        .task { await prepareVideo() }
        .task { isWidgetAdded = await Self.isWidgetInstalled() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            // Back from the Home Screen: close the floating video and check for the widget.
            playback.stopPictureInPicture()
            Task { isWidgetAdded = await Self.isWidgetInstalled() }
        }
        .onDisappear { playback.tearDown() }
    }

    /// The live animation, replaced by the identical video once it's rendered so that
    /// Picture in Picture can take over from it.
    private var demo: some View {
        ZStack {
            if playback.isLoaded {
                TutorialPlayerView(playback: playback)
            } else {
                TimelineView(.animation) { context in
                    WidgetTutorialScene(
                        time: context.date.timeIntervalSince(startDate)
                            .truncatingRemainder(dividingBy: WidgetTutorialScene.duration),
                        wallpaper: wallpaper.color
                    )
                }
            }
        }
        .frame(width: WidgetTutorialScene.size.width, height: WidgetTutorialScene.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.ink.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        // Shrinks to fit smaller screens; the scene itself is drawn at a fixed size.
        .scaleToFit(WidgetTutorialScene.size)
        .overlay(alignment: .topTrailing) {
            if isWidgetAdded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .background(.white, in: .circle)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Touch and hold an empty spot on your Home Screen, tap Edit, then Add Widget. Find Kelmteen, tap Add Widget, then tap Done.")
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 14) {
            if isWidgetAdded {
                Button("Continue", action: onFinish)
                    .buttonStyle(PillButtonStyle())
            } else {
                if TutorialPlayback.isSupported {
                    Button {
                        playback.startPictureInPicture()
                    } label: {
                        Label("Show me while I add it", systemImage: "pip.enter")
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!playback.isPictureInPicturePossible)

                    Text("Then swipe up to go to your Home Screen. The video keeps playing.")
                        .font(.footnote)
                        .foregroundStyle(Color.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                Button("Later", action: onFinish)
                    .font(.headline)
                    .foregroundStyle(Color.ink.opacity(0.7))
            }
        }
    }

    private func prepareVideo() async {
        guard TutorialPlayback.isSupported, !playback.isLoaded else { return }
        if let url = try? await WidgetTutorialVideo.make(
            wallpaper: wallpaper,
            locale: locale,
            layoutDirection: layoutDirection
        ) {
            playback.load(url)
        }
    }

    /// Whether this phone has a Kelmteen widget on the Home Screen or Lock Screen.
    static func isWidgetInstalled() async -> Bool {
        let widgets = try? await WidgetCenter.shared.currentConfigurations()
        return widgets?.contains { $0.kind == "NotesWidget" } ?? false
    }
}

private extension View {
    /// Scales a fixed-size view down (never up) to fit the space it's offered.
    func scaleToFit(_ size: CGSize) -> some View {
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / size.width, proxy.size.height / size.height)
            self
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

#Preview {
    WidgetTutorialView {}
        .environment(AppModel.preview)
}
