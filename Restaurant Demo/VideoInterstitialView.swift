import SwiftUI
import AVFoundation
import UIKit

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
    let onComplete: () -> Void

    @State private var flashOpacity: Double = 0.0

    init(videoName: String, videoType: String = "mov", flashStyle: FlashStyle = .double, earlyCutRequested: Binding<Bool> = .constant(false), earlyCutLeadSeconds: Double = 1.0, onComplete: @escaping () -> Void) {
        self.videoName = videoName
        self.videoType = videoType
        self.flashStyle = flashStyle
        self._earlyCutRequested = earlyCutRequested
        self.earlyCutLeadSeconds = earlyCutLeadSeconds
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            OneShotVideoPlayer(
                videoName: videoName,
                videoType: videoType,
                earlyCutLeadSeconds: earlyCutLeadSeconds,
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
    let earlyCutRequested: Bool
    let onComplete: () -> Void
    
    // Store a reference to the current earlyCutRequested value in the coordinator
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(earlyCutLeadSeconds: earlyCutLeadSeconds, onComplete: onComplete)
        coordinator.currentEarlyCutRequested = earlyCutRequested
        return coordinator
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
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
            queue: .main
        ) { [weak coordinator] _ in
            guard let coordinator = coordinator, !coordinator.hasCompleted else { return }
            print("🎬 Early cut notification received - finishing video immediately")
            coordinator.finishEarly()
        }

        playerItem.addObserver(context.coordinator, forKeyPath: "status", options: [.new], context: nil)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = UIScreen.main.bounds
        // Update the current value in coordinator so periodic observer can check it
        let wasRequested = context.coordinator.lastEarlyCutRequested
        context.coordinator.lastEarlyCutRequested = earlyCutRequested
        context.coordinator.currentEarlyCutRequested = earlyCutRequested
        
        // If early cut is requested (newly or already), finish immediately
        if earlyCutRequested {
            print("🎬 Early cut requested in updateUIView (wasRequested: \(wasRequested), hasCompleted: \(context.coordinator.hasCompleted))")
            if !wasRequested {
                // Newly requested - finish immediately
                print("✅ Newly requested - calling finishEarly()")
                context.coordinator.finishEarly()
            } else if !context.coordinator.hasCompleted {
                // Already requested but not finished yet - finish now
                print("✅ Already requested but not completed - calling finishEarly()")
                context.coordinator.finishEarly()
            } else {
                print("⚠️ Early cut requested but already completed")
            }
        }
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
        private let maxPlays: Int = 1  // Changed from 2 to 1 - remove double-play
        let earlyCutLeadSeconds: Double
        let onComplete: () -> Void

        init(earlyCutLeadSeconds: Double, onComplete: @escaping () -> Void) {
            self.earlyCutLeadSeconds = earlyCutLeadSeconds
            self.onComplete = onComplete
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "status" {
                if let item = object as? AVPlayerItem {
                    switch item.status {
                    case .readyToPlay:
                        // Don't play if we've already completed (early cut was requested)
                        guard !hasCompleted else { return }
                        // Check if early cut was requested before starting playback
                        if lastEarlyCutRequested || currentEarlyCutRequested {
                            print("🎬 Early cut already requested before playback - finishing immediately")
                            finishEarly()
                            return
                        }
                        // Only play if not already at end
                        if item.currentTime().seconds < item.duration.seconds - 0.1 {
                            // First play with audio, subsequent plays muted
                            player?.isMuted = playCount > 0
                            player?.play()
                        }
                        // Configure early-cut boundary observer when duration is known
                        let durationSec = item.duration.seconds
                        if durationSec.isFinite && durationSec > 0 {
                            let cutSec = max(durationSec - earlyCutLeadSeconds, 0)
                            cutThresholdTime = CMTime(seconds: cutSec, preferredTimescale: 600)
                            if boundaryObserver == nil, let player = player {
                                boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: cutThresholdTime)], queue: .main) { [weak self] in
                                    guard let self = self, !self.hasCompleted else { return }
                                    if self.lastEarlyCutRequested {
                                        self.finishEarly()
                                    }
                                }
                            }
                        }
                        // Set up periodic observer to check for early cut requests during playback
                        if periodicObserver == nil, let player = player {
                            let interval = CMTime(seconds: 0.05, preferredTimescale: 600) // Check every 50ms for faster response
                            periodicObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
                                guard let self = self, !self.hasCompleted else { return }
                                // Check both lastEarlyCutRequested and currentEarlyCutRequested
                                if self.lastEarlyCutRequested || self.currentEarlyCutRequested {
                                    print("🎬 Early cut detected in periodic observer - finishing video")
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

            // Mark this play as completed
            playCount += 1

            // If early cut was requested during first play, finish immediately instead of looping
            // Check both lastEarlyCutRequested and currentEarlyCutRequested to catch binding updates
            if playCount == 1 && (lastEarlyCutRequested || currentEarlyCutRequested) {
                player.pause()
                playerLayer?.isHidden = true
                player.replaceCurrentItem(with: nil)
                hasCompleted = true
                DispatchQueue.main.async { self.onComplete() }
                return
            }

            if playCount < maxPlays {
                // Continue to second play only if early cut wasn't requested
                // Double-check before looping in case the binding was updated
                if lastEarlyCutRequested || currentEarlyCutRequested {
                    player.pause()
                    playerLayer?.isHidden = true
                    player.replaceCurrentItem(with: nil)
                    hasCompleted = true
                    DispatchQueue.main.async { self.onComplete() }
                    return
                }
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                player.isMuted = true
                player.play()
                return
            }

            // Final completion after last loop
            player.pause()
            // Hide the layer to avoid flashing the first frame on teardown
            playerLayer?.isHidden = true
            // Detach the item to prevent any residual frame rendering
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


