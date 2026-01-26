//
//  LoopingVideoPlayer.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/24/25.
//
import SwiftUI
import AVFoundation
import UIKit

struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    let videoType: String
    @Binding var isAudioEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        // Use .ambient so iOS doesn't trigger AirPods auto-connect (avoids video stutter on launch)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Audio session configuration failed: \(error)")
        }
        
        guard let path = Bundle.main.path(forResource: videoName, ofType: videoType) else {
            print("⚠️ Video file not found: \(videoName).\(videoType)")
            return view
        }
        
        let url = URL(fileURLWithPath: path)
        let playerItem = AVPlayerItem(url: url)
        
        // Optimize for smooth playback
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        playerItem.preferredForwardBufferDuration = 1.0
        
        let player = AVPlayer(playerItem: playerItem)
        let playerLayer = AVPlayerLayer(player: player)
        
        // Optimize video rendering
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = UIScreen.main.bounds
        playerLayer.needsDisplayOnBoundsChange = false
        
        // Ensure smooth playback with audio enabled
        player.automaticallyWaitsToMinimizeStalling = true
        // Audio is now enabled - removed the muted setting
        
        view.layer.addSublayer(playerLayer)
        
        // Store references for cleanup
        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        
        // Set up looping with proper timing
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            // Smooth loop restart
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                player.play()
            }
        }
        
        // Start playback when ready
        playerItem.addObserver(context.coordinator, forKeyPath: "status", options: [.new], context: nil)

        // Pause/resume on app lifecycle changes
        let willResign = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.player?.pause()
        }
        let didBecome = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.player?.play()
        }
        context.coordinator.observers.append(willResign)
        context.coordinator.observers.append(didBecome)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update frame if needed
        context.coordinator.playerLayer?.frame = UIScreen.main.bounds
        // Update audio muting
        context.coordinator.player?.isMuted = !isAudioEnabled
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        fileprivate var observers: [NSObjectProtocol] = []
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "status" {
                if let playerItem = object as? AVPlayerItem {
                    switch playerItem.status {
                    case .readyToPlay:
                        player?.play()
                    case .failed:
                        print("⚠️ Video playback failed: \(playerItem.error?.localizedDescription ?? "Unknown error")")
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
        
        deinit {
            // Clean up observers and resources
            if let playerItem = player?.currentItem {
                playerItem.removeObserver(self, forKeyPath: "status")
            }
            for token in observers { NotificationCenter.default.removeObserver(token) }
            player?.pause()
            player = nil
            playerLayer = nil
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Ensure the player is paused and observers are removed when the view is dismantled
        coordinator.player?.pause()
        for token in coordinator.observers { NotificationCenter.default.removeObserver(token) }
        coordinator.observers.removeAll()
    }
}
