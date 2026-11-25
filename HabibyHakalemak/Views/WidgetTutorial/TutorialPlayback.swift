//
//  TutorialPlayback.swift
//  Kelmteen
//

import AVKit
import SwiftUI

/// Plays the widget tutorial video on a loop and lets it continue in Picture in Picture,
/// so it floats over the Home Screen while the user adds the widget.
@Observable
final class TutorialPlayback: NSObject {
    private(set) var isPictureInPicturePossible = false
    private(set) var isPictureInPictureActive = false
    private(set) var isLoaded = false

    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var pictureInPicture: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func load(_ url: URL) {
        // Picture in Picture needs a playback audio session. The video is silent, so it
        // mixes with whatever the user is listening to instead of pausing it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
        isLoaded = true
    }

    /// Connects Picture in Picture to the layer showing the video in the app.
    func attach(to layer: AVPlayerLayer) {
        guard Self.isSupported, pictureInPicture == nil,
              let controller = AVPictureInPictureController(playerLayer: layer) else { return }
        // Starts on its own when the user swipes home to add the widget.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        controller.delegate = self
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let isPossible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.isPictureInPicturePossible = isPossible }
        }
        pictureInPicture = controller
    }

    func startPictureInPicture() {
        pictureInPicture?.startPictureInPicture()
    }

    func stopPictureInPicture() {
        if pictureInPicture?.isPictureInPictureActive == true {
            pictureInPicture?.stopPictureInPicture()
        }
    }

    func tearDown() {
        stopPictureInPicture()
        player.pause()
        looper = nil
        possibleObservation = nil
        pictureInPicture = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension TutorialPlayback: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isPictureInPictureActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isPictureInPictureActive = false
    }
}

/// Shows the tutorial video in the app; Picture in Picture takes over from this layer.
struct TutorialPlayerView: UIViewRepresentable {
    let playback: TutorialPlayback

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = playback.player
        view.playerLayer.videoGravity = .resizeAspect
        playback.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {}

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
