import SwiftUI

// MARK: - Active Reward Countdown Banner (Clean / Mainstream)
struct RedeemedRewardsCountdownCard: View {
    let activeRedemption: ActiveRedemption
    let onExpired: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var timeRemainingText: String = "--:--"
    @State private var timer: Timer?
    @State private var urgentMode = false
    @State private var pulse = false
    @State private var showTapHint = false
    @State private var hintTimer: Timer?
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Theme.darkGoldGradient)
                    .frame(width: 42, height: 42)
                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
            }
            
            // Title
            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {
                    Text("Active reward")
                        .opacity(showTapHint ? 0.0 : 1.0)
                    
                    Text("Tap to redeem")
                        .opacity(showTapHint ? 1.0 : 0.0)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: showTapHint)
                
                Text(activeRedemption.rewardTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer(minLength: 12)
            
            // Timer
            Text(timeRemainingText)
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundStyle(urgentMode ? LinearGradient(colors: [Theme.energyRed, Theme.energyOrange], startPoint: .topLeading, endPoint: .bottomTrailing) : Theme.darkGoldGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .scaleEffect((urgentMode && pulse && !reduceMotion) ? 1.04 : 1.0)
                .animation(urgentMode ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulse)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Theme.darkGoldGradient, lineWidth: 1.5)
                )
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
        )
        .onAppear {
            startTimer()
            if !reduceMotion {
                pulse = true
            }
            startHintLoop()
        }
        .onDisappear {
            timer?.invalidate()
            hintTimer?.invalidate()
        }
    }
    
    // MARK: - Timer Logic
    private func startTimer() {
        updateTimeRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        let remaining = activeRedemption.expiresAt.timeIntervalSinceNow
        if remaining <= 0 {
            timer?.invalidate()
            timeRemainingText = "00:00"
            onExpired()
        } else {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            timeRemainingText = String(format: "%d:%02d", minutes, seconds)
            
            // Activate urgent mode when less than 2 minutes remain
            if remaining <= 120 && !urgentMode {
                urgentMode = true
            }
        }
    }
    
    private func startHintLoop() {
        hintTimer?.invalidate()
        guard !reduceMotion else { return }
        
        // Crossfade between the two labels (kept subtle so it doesn't fight the timer)
        hintTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.45)) {
                showTapHint.toggle()
            }
        }
    }
}

#Preview {
    RedeemedRewardsCountdownCard(
        activeRedemption: ActiveRedemption(rewardId: "test", rewardTitle: "Free Peanut Sauce", redemptionCode: "47319015", expiresAt: Date().addingTimeInterval(120)),
        onExpired: {}
    )
    .padding()
    .previewLayout(.sizeThatFits)
    .background(Color.black)
}