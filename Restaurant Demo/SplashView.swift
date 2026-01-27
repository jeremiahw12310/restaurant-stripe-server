import SwiftUI

struct SplashView: View {
    // This binding is received from LaunchView and tells us when the launch
    // animation has started.
    @Binding var launchPhase: LaunchView.LaunchPhase
    

    // State for audio control
    @State private var isAudioEnabled = true
    // State for navigation
    @State private var navigateToAuth = false
    // State to prevent animation conflicts
    @State private var isButtonPressed = false

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
                    LoopingVideoPlayer(videoName: "dump", videoType: "MOV", isAudioEnabled: $isAudioEnabled)
                        .ignoresSafeArea()
                        // .identity means no transition animation for the video itself, preventing the glitch.
                        .transition(.identity)
                }
                
                // The overlay content with beautiful design
                VStack {
                    Spacer()
                    
                    // Welcome Text with Glass Effect
                
            
                    
                    Spacer()
                    
                    // Get Started Button - Vibrant Energy Style
                    Button(action: {
                        // Prevent multiple taps
                        guard !isButtonPressed else { return }
                        isButtonPressed = true
                        
                        isAudioEnabled = false
                        // Navigate immediately
                        navigateToAuth = true
                    }) {
                        HStack(spacing: 12) {
                            Text("GET STARTED")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .tracking(0.5)
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 40)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Theme.darkGoldGradient)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.4),
                                                    Color.white.opacity(0.1)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isButtonPressed ? 0.96 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonPressed)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                    // Navigation trigger
                    NavigationLink(destination: AuthFlowView(), isActive: $navigateToAuth) { EmptyView() }
                }
                // The UI elements on top of the video will still fade in smoothly.
                .opacity(launchPhase == .animating || launchPhase == .finished ? 1 : 0)
                .animation(.easeIn(duration: 1.0).delay(0.5), value: launchPhase)
            }
        }
        .onAppear {
            // Reset button state so it can be tapped again after returning
            isButtonPressed = false
        }
        // Reset button state whenever navigation back to SplashView occurs
        .onChange(of: navigateToAuth) { newValue in
            if !newValue {
                isButtonPressed = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reset navigation state when app comes to foreground (user swipes back)
            DebugLogger.debug("🔵 SplashView: App will enter foreground, resetting navigation state", category: "App")
        }
    }
}

