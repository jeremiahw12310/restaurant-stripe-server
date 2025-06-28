import SwiftUI

struct SplashView: View {
    // This binding is received from LaunchView and tells us when the launch
    // animation has started.
    @Binding var launchPhase: LaunchView.LaunchPhase

    var body: some View {
        NavigationStack {
            ZStack {
                // Beautiful gradient background
                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.95, green: 0.97, blue: 1.0),
                                        Color(red: 1.0, green: 0.98, blue: 0.95)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .ignoresSafeArea()
                
                // ✅ FIX: The video is added to the view hierarchy as soon as the launch animation
                // begins, and it appears instantly without its own fade effect.
                if launchPhase != .initial {
                    LoopingVideoPlayer(videoName: "dump", videoType: "mp4")
                        .ignoresSafeArea()
                        // .identity means no transition animation for the video itself, preventing the glitch.
                        .transition(.identity)
                }
                
                // The overlay content with beautiful design
                VStack {
                    Spacer()
                    
                    // Welcome Text with Glass Effect
                
            
                    
                    Spacer()
                    
                    // Beautiful Login Button
                    NavigationLink(destination: AuthFlowView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Get Started")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 30)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.2, green: 0.6, blue: 0.9),
                                            Color(red: 0.3, green: 0.7, blue: 1.0)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 15, x: 0, y: 8)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
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
