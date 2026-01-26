import SwiftUI
import AVFoundation
import UIKit
import QuartzCore

extension Notification.Name {
    static let interstitialEarlyCutRequested = Notification.Name("interstitialEarlyCutRequested")
}

struct VideoInterstitialView: View {
    enum FlashStyle {
        case none
        case double
    }

    let videoName: String
    let videoType: String
    let flashStyle: FlashStyle
    @Binding var earlyCutRequested: Bool
    let earlyCutLeadSeconds: Double
    let earlyCutMinPlaySeconds: Double
    let onComplete: () -> Void

    @State private var flashOpacity: Double = 0.0

    init(videoName: String, videoType: String = "mov", flashStyle: FlashStyle = .double, earlyCutRequested: Binding<Bool> = .constant(false), earlyCutLeadSeconds: Double = 1.0, earlyCutMinPlaySeconds: Double = 0, onComplete: @escaping () -> Void) {
        self.videoName = videoName
        self.videoType = videoType
        self.flashStyle = flashStyle
        self._earlyCutRequested = earlyCutRequested
        self.earlyCutLeadSeconds = earlyCutLeadSeconds
        self.earlyCutMinPlaySeconds = earlyCutMinPlaySeconds
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            OneShotVideoPlayer(
                videoName: videoName,
                videoType: videoType,
                earlyCutLeadSeconds: earlyCutLeadSeconds,
                earlyCutMinPlaySeconds: earlyCutMinPlaySeconds,
                earlyCutRequested: earlyCutRequested,
                onComplete: onComplete
            )
                .ignoresSafeArea()

            // Power flash overlay for receipt interstitial
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            runFlash()
        }
    }

    private func runFlash() {
        switch flashStyle {
        case .none:
            flashOpacity = 0
        case .double:
            // First strong flash
            withAnimation(.easeOut(duration: 0.10)) { flashOpacity = 1.0 }
            // Haptic at peak
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred(intensity: 1.0)
            }
            // Hold briefly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeIn(duration: 0.18)) { flashOpacity = 0.0 }
            }
            // Second softer flash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.55 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                withAnimation(.easeIn(duration: 0.20)) { flashOpacity = 0.0 }
            }
        }
    }
}

private struct OneShotVideoPlayer: UIViewRepresentable {
    let videoName: String
    let videoType: String
    let earlyCutLeadSeconds: Double
    let earlyCutMinPlaySeconds: Double
    let earlyCutRequested: Bool
    let onComplete: () -> Void
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(earlyCutLeadSeconds: earlyCutLeadSeconds, earlyCutMinPlaySeconds: earlyCutMinPlaySeconds, onComplete: onComplete)
        coordinator.currentEarlyCutRequested = earlyCutRequested
        return coordinator
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        // Use .ambient to avoid AirPods auto-connect and video stutter
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio session configuration failed: \(error)")
        }

        guard let path = Bundle.main.path(forResource: videoName, ofType: videoType) else {
            print("⚠️ Video file not found: \(videoName).\(videoType)")
            DispatchQueue.main.async { context.coordinator.onComplete() }
            return view
        }

        let url = URL(fileURLWithPath: path)
        let playerItem = AVPlayerItem(url: url)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        playerItem.preferredForwardBufferDuration = 0.5

        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(playerLayer)

        context.coordinator.player = player
        context.coordinator.playerItem = playerItem
        context.coordinator.playerLayer = playerLayer
        context.coordinator.currentEarlyCutRequested = earlyCutRequested
        context.coordinator.lastEarlyCutRequested = earlyCutRequested

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Subscribe to early cut notification for immediate interruption
        let coordinator = context.coordinator
        context.coordinator.notificationObserver = NotificationCenter.default.addObserver(
            forName: .interstitialEarlyCutRequested,
            object: nil,
            queue: nil
        ) { [weak coordinator] _ in
            guard let coordinator = coordinator, !coordinator.hasCompleted else { return }
            print("🎬 Early cut notification received - finishing video immediately")
            if Thread.isMainThread {
                coordinator.finishEarly()
            } else {
                DispatchQueue.main.async {
                    coordinator.finishEarly()
                }
            }
        }

        playerItem.addObserver(context.coordinator, forKeyPath: "status", options: [.new], context: nil)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = UIScreen.main.bounds
        let wasRequested = context.coordinator.lastEarlyCutRequested
        context.coordinator.lastEarlyCutRequested = earlyCutRequested
        context.coordinator.currentEarlyCutRequested = earlyCutRequested

        guard earlyCutRequested, !context.coordinator.hasCompleted else { return }
        let minPlay = context.coordinator.earlyCutMinPlaySeconds
        if minPlay == 0 {
            print("🎬 Early cut requested in updateUIView (wasRequested: \(wasRequested)) - finishing immediately")
            if !wasRequested { print("✅ Newly requested - calling finishEarly()") }
            else { print("✅ Already requested but not completed - calling finishEarly()") }
            context.coordinator.finishEarly()
        }
        // If minPlay > 0, only flags were updated; periodic observer will finish once min play elapsed
    }

    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerItem: AVPlayerItem?
        var playerLayer: AVPlayerLayer?
        var boundaryObserver: Any?
        var periodicObserver: Any?
        var notificationObserver: NSObjectProtocol?
        var hasCompleted: Bool = false
        var cutThresholdTime: CMTime = .zero
        var lastEarlyCutRequested: Bool = false
        var currentEarlyCutRequested: Bool = false  // Current value from binding
        // Track how many full plays have completed (first with audio, second muted)
        private var playCount: Int = 0
        // Loop effectively indefinitely; `ReceiptScanView` enforces a 45s timeout and posts
        // `.interstitialEarlyCutRequested` on any server response (success or error).
        private let maxPlays: Int = Int.max
        let earlyCutLeadSeconds: Double
        let earlyCutMinPlaySeconds: Double
        let onComplete: () -> Void
        var playbackStartWallTime: CFTimeInterval?

        init(earlyCutLeadSeconds: Double, earlyCutMinPlaySeconds: Double, onComplete: @escaping () -> Void) {
            self.earlyCutLeadSeconds = earlyCutLeadSeconds
            self.earlyCutMinPlaySeconds = earlyCutMinPlaySeconds
            self.onComplete = onComplete
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "status" {
                if let item = object as? AVPlayerItem {
                    switch item.status {
                    case .readyToPlay:
                        guard !hasCompleted else { return }
                        let earlyRequested = lastEarlyCutRequested || currentEarlyCutRequested
                        if earlyRequested && earlyCutMinPlaySeconds == 0 {
                            print("🎬 Early cut already requested before playback - finishing immediately")
                            finishEarly()
                            return
                        }
                        if item.currentTime().seconds < item.duration.seconds - 0.1 {
                            player?.isMuted = playCount > 0
                            player?.play()
                            if playbackStartWallTime == nil {
                                playbackStartWallTime = CACurrentMediaTime()
                            }
                        }
                        // Configure early-cut boundary observer when duration is known
                        let durationSec = item.duration.seconds
                        if durationSec.isFinite && durationSec > 0 {
                            let cutSec = max(durationSec - earlyCutLeadSeconds, 0)
                            cutThresholdTime = CMTime(seconds: cutSec, preferredTimescale: 600)
                            if boundaryObserver == nil, let player = player {
                                boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: cutThresholdTime)], queue: .main) { [weak self] in
                                    guard let self = self, !self.hasCompleted else { return }
                                    guard self.lastEarlyCutRequested else { return }
                                    if self.earlyCutMinPlaySeconds == 0 {
                                        self.finishEarly()
                                        return
                                    }
                                    if let start = self.playbackStartWallTime, CACurrentMediaTime() - start >= self.earlyCutMinPlaySeconds {
                                        self.finishEarly()
                                    }
                                }
                            }
                        }
                        // Set up periodic observer to check for early cut requests during playback
                        if periodicObserver == nil, let player = player {
                            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
                            periodicObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
                                guard let self = self, !self.hasCompleted else { return }
                                guard self.lastEarlyCutRequested || self.currentEarlyCutRequested else { return }
                                if self.earlyCutMinPlaySeconds == 0 {
                                    print("🎬 Early cut detected in periodic observer - finishing video")
                                    self.finishEarly()
                                    return
                                }
                                guard let start = self.playbackStartWallTime else { return }
                                if CACurrentMediaTime() - start >= self.earlyCutMinPlaySeconds {
                                    print("🎬 Early cut min play elapsed - finishing video")
                                    self.finishEarly()
                                }
                            }
                        }
                    case .failed:
                        print("⚠️ Interstitial video failed: \(item.error?.localizedDescription ?? "Unknown error")")
                        player?.pause()
                        DispatchQueue.main.async { self.onComplete() }
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }

        @objc func playerItemDidReachEnd() {
            guard let player = player, !hasCompleted else { return }

            playCount += 1
            let earlyRequested = lastEarlyCutRequested || currentEarlyCutRequested

            // If early cut requested: finish only when min-play allows (0 or elapsed >= minPlay)
            if earlyRequested {
                let mayFinish: Bool
                if earlyCutMinPlaySeconds == 0 {
                    mayFinish = true
                } else if let start = playbackStartWallTime, CACurrentMediaTime() - start >= earlyCutMinPlaySeconds {
                    mayFinish = true
                } else {
                    mayFinish = false  // keep looping until min play elapsed
                }
                if mayFinish {
                    player.pause()
                    playerLayer?.isHidden = true
                    player.replaceCurrentItem(with: nil)
                    hasCompleted = true
                    DispatchQueue.main.async { self.onComplete() }
                    return
                }
            }

            if playCount < maxPlays {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.isMuted = true
                player.play()
                return
            }

            player.pause()
            playerLayer?.isHidden = true
            player.replaceCurrentItem(with: nil)
            hasCompleted = true
            DispatchQueue.main.async { self.onComplete() }
        }

        func tryEarlyFinishIfPastThreshold() {
            guard !hasCompleted, cutThresholdTime.isValid, let player = player else { return }
            let current = player.currentTime()
            if current >= cutThresholdTime {
                finishEarly()
            }
        }

        func finishEarly() {
            guard !hasCompleted else { 
                print("⚠️ finishEarly called but already completed")
                return 
            }
            print("✅ finishEarly - stopping video playback")
            player?.pause()
            // Remove observers to prevent any callbacks
            if let observer = periodicObserver, let player = player {
                player.removeTimeObserver(observer)
                periodicObserver = nil
            }
            if let observer = boundaryObserver, let player = player {
                player.removeTimeObserver(observer)
                boundaryObserver = nil
            }
            // Hide the layer to avoid flashing the first frame on teardown
            playerLayer?.isHidden = true
            // Detach the item to prevent any residual frame rendering
            player?.replaceCurrentItem(with: nil)
            hasCompleted = true
            DispatchQueue.main.async { self.onComplete() }
        }

        deinit {
            if let item = playerItem {
                item.removeObserver(self, forKeyPath: "status")
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            }
            if let observer = boundaryObserver, let player = player {
                player.removeTimeObserver(observer)
            }
            if let observer = periodicObserver, let player = player {
                player.removeTimeObserver(observer)
            }
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            player?.pause()
            player = nil
            playerLayer = nil
        }
    }
}


