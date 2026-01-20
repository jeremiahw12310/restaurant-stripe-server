import SwiftUI

struct JellyGlimmerView: View {
    var scrollOffset: CGFloat
    var time: Double
    var colorScheme: ColorScheme
    var pop: Bool

    var body: some View {
        ZStack {
            // OPTIMIZED: Reduced from 5 blobs to 3 blobs for better performance
            JellyBlob(color: .purple, baseX: 0.2, baseY: 0.3, scrollOffset: scrollOffset, time: time, size: 280, speed: 0.4, colorScheme: colorScheme, pop: pop)
            JellyBlob(color: .blue, baseX: 0.7, baseY: 0.2, scrollOffset: scrollOffset, time: time, size: 220, speed: 0.5, colorScheme: colorScheme, pop: pop)
            JellyBlob(color: .pink, baseX: 0.5, baseY: 0.7, scrollOffset: scrollOffset, time: time, size: 260, speed: 0.45, colorScheme: colorScheme, pop: pop)
            // Removed 2 blobs to reduce CPU usage
        }
        .blendMode(.screen)
        .ignoresSafeArea()
    }
}

struct JellyBlob: View {
    var color: Color
    var baseX: CGFloat
    var baseY: CGFloat
    var scrollOffset: CGFloat
    var time: Double
    var size: CGFloat
    var speed: Double
    var colorScheme: ColorScheme
    var pop: Bool
    
    var body: some View {
        // OPTIMIZED: Simplified calculations to reduce CPU usage
        let x = baseX + 0.01 * CGFloat(sin(time * speed)) + 0.0005 * scrollOffset // Reduced multipliers
        let y = baseY + 0.01 * CGFloat(cos(time * speed)) + 0.0007 * scrollOffset // Reduced multipliers
        let scale = 1 + 0.02 * CGFloat(sin(time * speed * 0.5)) // Simplified scale calculation
        
        if colorScheme == .light && pop {
            return Circle()
                .fill(color)
                .frame(width: size * scale, height: size * scale)
                .position(x: UIScreen.main.bounds.width * x,
                          y: UIScreen.main.bounds.height * y)
                .blur(radius: 30) // Reduced blur radius
                .opacity(0.6) // Reduced opacity
                .shadow(color: .white.opacity(0.15), radius: 30) // Reduced shadow
        } else {
            return Circle()
                .fill(color)
                .frame(width: size * scale, height: size * scale)
                .position(x: UIScreen.main.bounds.width * x,
                          y: UIScreen.main.bounds.height * y)
                .blur(radius: 30) // Reduced blur radius
                .opacity(0.35) // Reduced opacity
                .shadow(color: .clear, radius: 30) // Reduced shadow
        }
    }
} 