//
//  LoopingVideoPlayer.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/24/25.
//
import SwiftUI
import AVFoundation

struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    let videoType: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        guard let path = Bundle.main.path(forResource: "dump", ofType: "mp4") else {
            print("⚠️ Video file not found")
            return view
        }

        let player = AVPlayer(url: URL(fileURLWithPath: path))
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = UIScreen.main.bounds

        view.layer.addSublayer(playerLayer)

        // Looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        player.isMuted = true
        player.play()
       

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
