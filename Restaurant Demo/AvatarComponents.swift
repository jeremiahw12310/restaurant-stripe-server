import SwiftUI

// MARK: - Avatar Helper Views
struct ProfileImageView: View {
    let image: UIImage
    let cardAnimations: [Bool]
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 75, height: 75)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            .scaleEffect(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.8)
            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
            .onAppear {
                DebugLogger.debug("🖼️ HomeView: Profile image displayed", category: "User")
            }
    }
}

struct EmojiAvatarView: View {
    @ObservedObject var userVM: UserViewModel
    let cardAnimations: [Bool]
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [userVM.avatarColor, userVM.avatarColor.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 75, height: 75)
                .shadow(color: userVM.avatarColor.opacity(0.3), radius: 8, x: 0, y: 4)
                .scaleEffect(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
            
            Text(userVM.avatarEmoji)
                .font(.system(size: 38))
                .shadow(radius: 2)
                .scaleEffect(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(1.4), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
        }
        .onAppear {
            DebugLogger.debug("🖼️ HomeView: No profile image, showing emoji avatar", category: "User")
        }
    }
}

struct LoyaltyStatusView: View {
    @ObservedObject var userVM: UserViewModel
    let cardAnimations: [Bool]
    let loyaltyStatus: String
    let loyaltyStatusColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loyaltyStatus)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6) // Scale down to 60% if needed
                .lineLimit(1) // Ensure single line
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(loyaltyStatusColor)
                )
                .opacity(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.5), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
            
            Text("Lifetime: \(userVM.lifetimePoints)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.black)
                .opacity(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.6), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
        }
    }
}

struct PointsCounterView: View {
    let animatedPoints: Double
    let cardAnimations: [Bool]
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(animatedPoints))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .minimumScaleFactor(0.5) // Scale down to 50% if needed
                .lineLimit(1) // Ensure single line
                .frame(width: 120, height: 44) // Fixed frame size
                .animation(.easeInOut(duration: 0.3), value: animatedPoints)
                .scaleEffect(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.7), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
            
            Text("POINTS")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .tracking(1)
                .opacity(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.8), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
        }
        .frame(width: 120) // Fixed width for the entire counter
    }
}

struct ProgressBarView: View {
    let animatedPoints: Double
    let progressBarColor: Color
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                // Radial glow behind the bar
                GeometryReader { geo in
                    let barWidth = max(0, min(CGFloat(animatedPoints / 10000.0) * (UIScreen.main.bounds.width - 120), UIScreen.main.bounds.width - 120))
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [progressBarColor.opacity(0.12), Color.clear]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 13
                            )
                        )
                        .frame(width: barWidth, height: 14)
                        .offset(y: -1)
                        .opacity(barWidth > 0 ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .frame(height: 12)
                
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                
                // Progress bar
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [progressBarColor, progressBarColor.opacity(0.7), progressBarColor.opacity(0.9)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(CGFloat(animatedPoints / 10000.0) * (UIScreen.main.bounds.width - 120), UIScreen.main.bounds.width - 120)), height: 12)
                    .animation(.easeInOut(duration: 0.5), value: animatedPoints)
            }
            
            HStack {
                Text("0")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("10K")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
} 