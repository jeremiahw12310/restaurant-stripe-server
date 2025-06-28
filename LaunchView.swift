import SwiftUI

struct LaunchView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    
    // Using an enum for the animation state is clearer and less error-prone.
    enum LaunchPhase {
        case initial
        case animating
        case finished
    }
    
    @State private var launchPhase: LaunchPhase = .initial
    
    var body: some View {
        ZStack {
            // The content that will be revealed underneath is always present in the hierarchy.
            if isLoggedIn {
                ContentView()
            } else {
                // We pass a binding of the launchPhase to the SplashView
                // so it knows when to start its own animation.
                SplashView(launchPhase: $launchPhase)
            }
            
            // The launch screen overlay.
            if launchPhase != .finished {
                // ✅ FIX: By placing the image in the background of a view that fills the space,
                // we guarantee it is always perfectly centered and properly scaled.
                Color.black // A solid black background to prevent any transparency glitches.
                    .overlay(
                        Image("dumpsplash") // Ensure this image is in your Assets.xcassets
                            .resizable()
                            .scaledToFill()
                    )
                    .ignoresSafeArea()
                    // ✅ FIX: The image starts already zoomed in and animates to a larger scale.
                    .scaleEffect(launchPhase == .animating ? 1.1 : 1.1)
                    .opacity(launchPhase == .animating ? 0 : 1) // Fades out during animation.
                    .onAppear(perform: startAnimation)
            }
        }
    }
    
    private func startAnimation() {
        let animationDelay = isLoggedIn ? 1.5 : 0.5
        
        // This is the animation that the user sees.
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
            withAnimation(.easeInOut(duration: 1.2)) {
                launchPhase = .animating
            }
        }
        
        // This timer removes the launch view from the hierarchy after the animation is complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay + 1.2) {
            launchPhase = .finished
        }
    }
}
