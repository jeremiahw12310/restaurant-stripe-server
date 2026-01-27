import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - Countdown Ring for Reward Card
struct CountdownRing: View {
    let progress: Double // 0 to 1
    let ringSize: CGFloat
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 6)
            
            // Progress ring (depleting)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: progress > 0.3 ?
                            [Color(red: 1.0, green: 0.9, blue: 0.5), Color(red: 1.0, green: 0.7, blue: 0.2)] :
                            [Color.red.opacity(0.9), Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
        .frame(width: ringSize, height: ringSize)
    }
}

// MARK: - Premium Ticket Code Display
struct TicketCodeDisplay: View {
    let code: String
    @State private var codeAppear = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top perforated edge
            HStack(spacing: 8) {
                ForEach(0..<15, id: \.self) { _ in
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, -4)
            
            // Code card
            VStack(spacing: 16) {
                Text("REDEMPTION CODE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(2)
                
                // Large code display
                HStack(spacing: 8) {
                    ForEach(Array(code.enumerated()), id: \.offset) { index, char in
                        Text(String(char))
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 36)
                            .scaleEffect(codeAppear ? 1.0 : 0.5)
                            .opacity(codeAppear ? 1.0 : 0)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.7)
                                .delay(Double(index) * 0.05),
                                value: codeAppear
                            )
                    }
                }
                
                // Decorative barcode-style element
                HStack(spacing: 2) {
                    ForEach(0..<25, id: \.self) { index in
                        Rectangle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: index % 3 == 0 ? 3 : 2, height: 30)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.white.opacity(0.12))
                    
                    // Shimmer overlay
                    RoundedRectangle(cornerRadius: 0)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            
            // Bottom perforated edge
            HStack(spacing: 8) {
                ForEach(0..<15, id: \.self) { _ in
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, -4)
        }
        .onAppear {
            codeAppear = true
        }
    }
}

// MARK: - Reward Card Screen (Premium Redesign)
struct RewardCardScreen: View {
    let userName: String
    let successData: RedemptionSuccessData
    let onDismiss: () -> Void
    
    private enum TerminalState: Equatable {
        case none
        case claimed
        case expired
    }
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var terminalState: TerminalState = .none
    @State private var showClaimedCongrats = false
    @State private var timeRemaining: TimeInterval = 0
    @State private var rewardListener: ListenerRegistration?
    @State private var timer: Timer?
    @State private var appearAnimation = false
    @State private var shimmerActive = false
    @State private var showDetails = false
    @State private var showCopiedToast = false
    @State private var hasScheduledAutoDismiss = false
    
    private var progress: Double {
        let total: TimeInterval = 15 * 60 // 15 minutes
        return max(0, min(1, timeRemaining / total))
    }
    
    private var timeDisplay: String {
        if timeRemaining <= 0 {
            return "Expired"
        }
        let minutes = Int(timeRemaining / 60)
        let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var isUrgent: Bool {
        timeRemaining <= 180 && timeRemaining > 0 // Less than 3 minutes
    }
    
    var body: some View {
        ZStack {
            // MARK: - Rich Gradient Background
            ZStack {
                // Base gradient - uses reward color if available, else gold
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.85, green: 0.55, blue: 0.15),
                        Color(red: 0.75, green: 0.45, blue: 0.1),
                        Color(red: 0.65, green: 0.35, blue: 0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Ambient glow
                RadialGradient(
                    colors: [Color.white.opacity(0.25), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 350
                )
                
                // Secondary glow
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.3), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 300
                )
            }
            .ignoresSafeArea()
            
            // Shimmer overlay
            SelectiveGlimmerView(
                isActive: shimmerActive,
                intensity: .subtle,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
            .ignoresSafeArea()
            
            // MARK: - Main Content
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.2))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // MARK: - Hero Section
                        VStack(spacing: 16) {
                            // Countdown ring with icon
                            ZStack {
                                CountdownRing(progress: progress, ringSize: 140)
                                
                                VStack(spacing: 4) {
                                    if let icon = successData.rewardIcon {
                                        Text(icon)
                                            .font(.system(size: 44))
                                    } else {
                                        Image(systemName: "gift.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text(timeDisplay)
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundColor(isUrgent ? .red : .white)
                                        .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
                                }
                            }
                            .scaleEffect(appearAnimation ? 1.0 : 0.8)
                            .opacity(appearAnimation ? 1.0 : 0)
                            
                            // Success message
                            VStack(spacing: 8) {
                                Text("Reward Redeemed")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
                                
                                // Show selected item name if available, otherwise reward title
                                Text(successData.displayName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .whiteTextShadow(opacity: 0.25, radius: 2, x: 0, y: 2)
                                    .multilineTextAlignment(.center)
                            }
                            .offset(y: appearAnimation ? 0 : 20)
                            .opacity(appearAnimation ? 1.0 : 0)
                        }
                        .padding(.top, 20)
                        
                        // MARK: - QR Display
                        VStack(spacing: 12) {
                            RewardQRCodeView(text: successData.redemptionCode, foregroundColor: .black, backgroundColor: .white)
                                .frame(width: 240, height: 240)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(Color.white.opacity(0.35), lineWidth: 2)
                                        )
                                        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
                                )
                        }
                        .padding(.horizontal, 24)
                            .offset(y: appearAnimation ? 0 : 30)
                            .opacity(appearAnimation ? 1.0 : 0)
                        
                        // MARK: - Instructions
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.point.right.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                                
                                Text("Show this QR code to your cashier")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
                            }
                            
                            if isUrgent {
                                Text("⚠️ Hurry! Less than 3 minutes remaining")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.red)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.red.opacity(0.2))
                                    )
                            }
                        }
                        .padding(.top, 8)
                        
                        // MARK: - Details (secondary information; keeps main UI focused on code + timer)
                        DisclosureGroup(isExpanded: $showDetails) {
                            HStack(spacing: 0) {
                                VStack(spacing: 4) {
                                    Text("-\(successData.pointsDeducted)")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .whiteTextShadow(opacity: 0.25, radius: 2, x: 0, y: 2)
                                    
                                    Text("Points Used")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                                }
                                .frame(maxWidth: .infinity)
                                
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 1, height: 40)
                                
                                VStack(spacing: 4) {
                                    Text("\(successData.newPointsBalance)")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(red: 1.0, green: 0.9, blue: 0.5))
                                        .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                                    
                                    Text("New Balance")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.top, 12)
                        } label: {
                            Text("Details")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .whiteTextShadow(opacity: 0.25, radius: 2, x: 0, y: 2)
                        }
                        .accentColor(.white.opacity(0.9))
                        .padding(.vertical, 16)
                        .padding(.horizontal, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 20)
                        
                        // MARK: - Done Button
                        Button(action: onDismiss) {
                            Text("Done")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .whiteTextShadow(opacity: 0.25, radius: 2, x: 0, y: 2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.black.opacity(0.25))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                )
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 32)
                    }
                }
            }
            
        }
        .fullScreenCover(isPresented: $showClaimedCongrats) {
            RewardClaimedCongratulationsScreen(onDone: onDismiss)
        }
        .overlay(alignment: .center) {
            if terminalState == .expired {
                terminalStateOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay(alignment: .top) {
            if showCopiedToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                    Text("Copied")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.top, 72)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            // Entrance animations
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.1)) {
                appearAnimation = true
            }
            
            // Subtle, time-limited shimmer (avoid heavy effects)
            shimmerActive = !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                shimmerActive = false
            }
            
            startTimer()
            attachFirestoreListener()
        }
        .onDisappear {
            timer?.invalidate()
            rewardListener?.remove()
        }
        .onChange(of: terminalState) { _, newState in
            guard newState == .expired else { return }
            scheduleAutoDismissIfNeeded()
        }
    }
    
    // MARK: - Firestore Live Updates
    private func attachFirestoreListener() {
        let db = Firestore.firestore()
        rewardListener = db.collection("redeemedRewards")
            .whereField("redemptionCode", isEqualTo: successData.redemptionCode)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    DebugLogger.debug("❌ Reward listener error: \(error.localizedDescription)", category: "Rewards")
                    return
                }
                guard let doc = snapshot?.documents.first else { return }
                let data = doc.data()
                if let isUsed = data["isUsed"] as? Bool, isUsed {
                    self.terminalState = .claimed
                    self.showClaimedCongrats = true
                }
                if let isExpired = data["isExpired"] as? Bool, isExpired {
                    self.terminalState = .expired
                }
            }
    }
    
    // MARK: - Timer
    private func startTimer() {
        updateTimeRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        let remaining = successData.expiresAt.timeIntervalSince(Date())
        if remaining <= 0 {
            timeRemaining = 0
            timer?.invalidate()
            terminalState = .expired
        } else {
            timeRemaining = remaining
        }
    }

    // MARK: - Actions
    private func copyRedemptionCode() {
        UIPasteboard.general.string = successData.redemptionCode
        withAnimation(.easeOut(duration: 0.2)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }

    private func scheduleAutoDismissIfNeeded() {
        guard !hasScheduledAutoDismiss else { return }
        hasScheduledAutoDismiss = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            onDismiss()
        }
    }

    // MARK: - Overlays
    private var terminalStateOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: terminalState == .claimed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)

            Text(terminalState == .claimed ? "Redeemed" : "Expired")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)

            Text(terminalState == .claimed ? "This reward has been used." : "This code is no longer valid.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .whiteTextShadow(opacity: 0.25, radius: 2, x: 0, y: 2)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 28)
    }
}

// MARK: - Preview
struct RewardCardScreen_Previews: PreviewProvider {
    static var previews: some View {
        RewardCardScreen(
            userName: "Alex",
            successData: RedemptionSuccessData(
                redemptionCode: "48291736",
                rewardTitle: "Free Pork Dumplings",
                rewardDescription: "6pc pork dumplings",
                newPointsBalance: 200,
                pointsDeducted: 500,
                expiresAt: Date().addingTimeInterval(15 * 60),
                rewardColorHex: nil,
                rewardIcon: "🥟"
            ),
            onDismiss: {}
        )
    }
}