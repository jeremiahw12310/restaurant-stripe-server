import SwiftUI

struct DumplingPopAnimation: View {
    @Binding var isShowing: Bool
    let onAnimationComplete: () -> Void
    let startPosition: CGPoint
    
    @State private var dumplingOffset = CGSize.zero
    @State private var dumplingScale: CGFloat = 0.1
    @State private var dumplingOpacity: Double = 0.0
    @State private var rotationAngle: Double = 0.0
    @State private var bounceCount = 0
    @State private var finalY: CGFloat = 0
    @State private var finalOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Dumpling emoji
            Text("🥟")
                .font(.system(size: 40))
                .position(startPosition)
                .offset(dumplingOffset)
                .scaleEffect(dumplingScale)
                .opacity(dumplingOpacity)
                .rotationEffect(.degrees(rotationAngle))
                .onAppear {
                    startAnimation()
                }
        }
        .allowsHitTesting(false) // Don't interfere with other interactions
    }
    
    private func startAnimation() {
        // Get screen height and safe area for final position
        let screenHeight = UIScreen.main.bounds.height
        // Account for tab bar and safe area - stop well above the bottom
        // Increased from 100 to 180 to prevent getting stuck at bottom
        finalY = screenHeight - 180
        
        // Calculate the offset needed to reach the final position
        finalOffset = CGSize(
            width: 0,
            height: finalY - startPosition.y
        )
        
        // Phase 1: Pop out with scale and rotation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            dumplingScale = 1.2
            dumplingOpacity = 1.0
            dumplingOffset = CGSize(width: 0, height: -50) // Pop up from button
            rotationAngle = 360 // Full rotation
        }
        
        // Phase 2: Start falling with bounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 1.2)) {
                dumplingOffset = finalOffset
                dumplingScale = 0.8
            }
            
            // Add bouncy effect during fall
            addBounceEffect()
        }
        
        // Phase 3: Final bounce and completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                dumplingScale = 1.0
                // Reduced bounce from +20 to +10 to prevent going too low
                dumplingOffset = CGSize(width: finalOffset.width, height: finalOffset.height + 10)
            }
            
            // Phase 4: Fade out and complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) {
                    dumplingOpacity = 0.0
                    dumplingScale = 0.5
                }
                
                // Call completion callback
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isShowing = false
                    onAnimationComplete()
                }
            }
        }
    }
    
    private func addBounceEffect() {
        let bounceInterval = 0.3 // OPTIMIZED: Increased from 0.2 to 0.3 for lower energy usage
        let bounceHeight: CGFloat = 20 // OPTIMIZED: Reduced from 25 to 20
        
        Timer.scheduledTimer(withTimeInterval: bounceInterval, repeats: true) { timer in
            bounceCount += 1
            
            if bounceCount <= 1 { // OPTIMIZED: Reduced from 2 to 1 bounce for lower energy usage
                withAnimation(.easeInOut(duration: bounceInterval)) {
                    dumplingOffset = CGSize(
                        width: finalOffset.width, // OPTIMIZED: Removed random horizontal movement
                        height: finalOffset.height - bounceHeight
                    )
                    rotationAngle += 20 // OPTIMIZED: Reduced from 30 to 20 degrees
                }
            } else {
                timer.invalidate()
            }
        }
    }
}

#Preview {
    DumplingPopAnimation(
        isShowing: .constant(true),
        onAnimationComplete: {
            DebugLogger.debug("Animation complete!", category: "UI")
        },
        startPosition: CGPoint(x: 200, y: 300)
    )
} 