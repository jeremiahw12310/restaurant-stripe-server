import SwiftUI

struct SplashView: View {
    // This binding is received from LaunchView and tells us when the launch
    // animation has started.
    @Binding var launchPhase: LaunchView.LaunchPhase

    var body: some View {
        NavigationStack {
            ZStack {
                // We show a solid black background that will be covered by the video.
                Color.white.ignoresSafeArea()
                
                // ✅ FIX: The video is added to the view hierarchy as soon as the launch animation
                // begins, and it appears instantly without its own fade effect.
                if launchPhase != .initial {
                    LoopingVideoPlayer(videoName: "dump", videoType: "mp4")
                        .ignoresSafeArea()
                        // .identity means no transition animation for the video itself, preventing the glitch.
                        .transition(.identity)
                }
                
                // The overlay content (Text and Button).
                VStack {
                    Spacer()
                    
             
                    
                    Spacer()
                    
                    NavigationLink(destination: AuthFlowView()) {
                        Text("Login or Sign Up")
                    }
                    .buttonStyle(PrimaryButtonStyle(backgroundColor: .green))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }
                // The UI elements on top of the video will still fade in smoothly.
                .opacity(launchPhase == .animating || launchPhase == .finished ? 1 : 0)
                .animation(.easeIn(duration: 1.0).delay(0.5), value: launchPhase)
            }
        }
    }
}
