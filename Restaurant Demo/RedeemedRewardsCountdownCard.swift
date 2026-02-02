import SwiftUI

// MARK: - Active Reward Countdown Banner (Enhanced / Prominent)
struct RedeemedRewardsCountdownCard: View {
    let activeRedemption: ActiveRedemption
    let onExpired: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var timeRemainingText: String = "--:--"
    @State private var timer: Timer?
    @State private var progress: Double = 1.0
    @State private var urgencyLevel: UrgencyLevel = .normal
    @State private var pulse = false
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var chevronOffset: CGFloat = 0
    @State private var appeared = false
    @State private var glowPulse = false
    
    private let totalDuration: TimeInterval = 15 * 60 // 15 minutes
    
    private enum UrgencyLevel {
        case normal      // > 5 minutes
        case warning     // 2-5 minutes
        case urgent      // 30s - 2 minutes
        case critical    // < 30 seconds
        
        var glowColor: Color {
            switch self {
            case .normal: return Theme.primaryGold
            case .warning: return Theme.energyOrange
            case .urgent: return Theme.energyOrange
            case .critical: return Theme.energyRed
            }
        }
        
        var progressColor: Color {
            switch self {
            case .normal: return Theme.primaryGold
            case .warning: return Theme.energyOrange
            case .urgent: return Theme.energyOrange
            case .critical: return Theme.energyRed
            }
        }
        
        var glowIntensity: Double {
            switch self {
            case .normal: return 0.3
            case .warning: return 0.4
            case .urgent: return 0.5
            case .critical: return 0.6
            }
        }
        
        var pulseSpeed: Double {
            switch self {
            case .normal: return 2.0
            case .warning: return 1.5
            case .urgent: return 1.0
            case .critical: return 0.5
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Enhanced Icon with pulse
            ZStack {
                // Glow behind icon
                Circle()
                    .fill(urgencyLevel.glowColor.opacity(0.3))
                    .frame(width: 58, height: 58)
                    .blur(radius: 8)
                    .scaleEffect(pulse && !reduceMotion ? 1.2 : 1.0)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGold, Theme.deepGold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.goldShadow, radius: 10, x: 0, y: 4)
                    .scaleEffect(pulse && !reduceMotion ? 1.05 : 1.0)
                
                Image(systemName: "gift.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.white)
            }
            
            // Title & CTA
            VStack(alignment: .leading, spacing: 4) {
                Text(activeRedemption.rewardTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                // Always-visible CTA with animated chevron
                HStack(spacing: 4) {
                    Text("Tap to Redeem")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .offset(x: chevronOffset)
                }
            }
            
            Spacer(minLength: 8)
            
            // Timer with progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 56, height: 56)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        urgencyLevel.progressColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                
                // Timer text
                Text(timeRemainingText)
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .scaleEffect(urgencyLevel == .critical && pulse && !reduceMotion ? 1.1 : 1.0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Base gradient background
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.75, green: 0.55, blue: 0.15),
                                Color(red: 0.55, green: 0.35, blue: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Shimmer overlay
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset * 400)
                    .mask(RoundedRectangle(cornerRadius: 22))
                
                // Border glow
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.lightGold, Theme.primaryGold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        // Outer glow effect
        .shadow(
            color: urgencyLevel.glowColor.opacity(glowPulse ? urgencyLevel.glowIntensity : urgencyLevel.glowIntensity * 0.5),
            radius: glowPulse ? 20 : 12,
            x: 0,
            y: 4
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
        // Entry animation
        .scaleEffect(appeared ? 1.0 : 0.9)
        .opacity(appeared ? 1.0 : 0.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activeRedemption.rewardTitle), \(timeRemainingText) remaining")
        .accessibilityHint("Double tap to view redemption code")
        .onAppear {
            startTimer()
            startAnimations()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Timer Logic
    private func startTimer() {
        updateTimeRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async { updateTimeRemaining() }
        }
    }
    
    private func updateTimeRemaining() {
        let remaining = activeRedemption.expiresAt.timeIntervalSinceNow
        if remaining <= 0 {
            timer?.invalidate()
            timeRemainingText = "00:00"
            progress = 0
            onExpired()
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            timeRemainingText = String(format: "%d:%02d", minutes, seconds)
            
            // Calculate progress (assuming 15 min total)
            progress = min(1.0, remaining / totalDuration)
            
            // Update urgency level
            let newUrgency: UrgencyLevel
            if remaining <= 30 {
                newUrgency = .critical
            } else if remaining <= 120 {
                newUrgency = .urgent
            } else if remaining <= 300 {
                newUrgency = .warning
            } else {
                newUrgency = .normal
            }
            
            if newUrgency != urgencyLevel {
                withAnimation(.easeInOut(duration: 0.3)) {
                    urgencyLevel = newUrgency
                }
            }
        }
    }
    
    private func startAnimations() {
        guard !reduceMotion else {
            appeared = true
            return
        }
        
        // Entry animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            appeared = true
        }
        
        // Continuous pulse animation
        withAnimation(.easeInOut(duration: urgencyLevel.pulseSpeed).repeatForever(autoreverses: true)) {
            pulse = true
        }
        
        // Glow pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
        
        // Shimmer animation
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.0
        }
        
        // Chevron bounce animation
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            chevronOffset = 4
        }
    }
}

#Preview("Normal") {
    VStack(spacing: 20) {
        RedeemedRewardsCountdownCard(
            activeRedemption: ActiveRedemption(rewardId: "test", rewardTitle: "Free Peanut Sauce", redemptionCode: "47319015", expiresAt: Date().addingTimeInterval(600)),
            onExpired: {}
        )
        
        RedeemedRewardsCountdownCard(
            activeRedemption: ActiveRedemption(rewardId: "test2", rewardTitle: "Free Boba Tea", redemptionCode: "47319016", expiresAt: Date().addingTimeInterval(90)),
            onExpired: {}
        )
    }
    .padding()
    .background(Color(red: 0.98, green: 0.98, blue: 0.99))
}