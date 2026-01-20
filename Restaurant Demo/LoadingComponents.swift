import SwiftUI

// MARK: - Shimmer Effect View
struct ShimmerView: View {
    @State private var isAnimating = false
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.gray.opacity(0.3),
                Color.gray.opacity(0.1),
                Color.gray.opacity(0.3)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.6),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(30))
                .offset(x: isAnimating ? 200 : -200)
        )
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Gold Loading Skeleton
struct GoldLoadingSkeleton: View {
    @State private var isAnimating = false
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(height: CGFloat = 20, cornerRadius: CGFloat = 8) {
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.95, green: 0.85, blue: 0.7).opacity(0.3),
                        Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.6),
                        Color(red: 0.95, green: 0.85, blue: 0.7).opacity(0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
            .cornerRadius(cornerRadius)
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.8),
                                Color.white,
                                Color.white.opacity(0.8),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(15))
                    .offset(x: isAnimating ? 300 : -300)
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 2.0)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Gold Loading Card
struct GoldLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header skeleton
            HStack {
                GoldLoadingSkeleton(height: 24, cornerRadius: 12)
                    .frame(width: 120)
                
                Spacer()
                
                GoldLoadingSkeleton(height: 20, cornerRadius: 10)
                    .frame(width: 60)
            }
            
            // Content skeletons
            VStack(alignment: .leading, spacing: 8) {
                GoldLoadingSkeleton(height: 16, cornerRadius: 8)
                    .frame(width: 200)
                
                GoldLoadingSkeleton(height: 16, cornerRadius: 8)
                    .frame(width: 160)
                
                GoldLoadingSkeleton(height: 14, cornerRadius: 7)
                    .frame(width: 100)
            }
            
            // Button skeleton
            GoldLoadingSkeleton(height: 36, cornerRadius: 18)
                .frame(width: 100)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .padding(.horizontal, 20)
    }
} 