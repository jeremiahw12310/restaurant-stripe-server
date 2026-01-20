import SwiftUI

// MARK: - Confetti Particle
struct ConfettiParticle: View {
    let color: Color
    let size: CGFloat
    @State private var position: CGPoint = .zero
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: size, height: size * 0.6)
            .rotationEffect(.degrees(rotation))
            .offset(x: position.x, y: position.y)
            .opacity(opacity)
    }
}

// MARK: - Premium Confirmation Dialog
struct RedemptionConfirmationDialog: View {
    let rewardData: RedemptionConfirmationData
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var appearAnimation = false
    @State private var isConfirming = false
    
    private var pointsAfter: Int {
        max(rewardData.currentPoints - rewardData.pointsRequired, 0)
    }
    
    var body: some View {
        ZStack {
            backgroundView
            dialogCard
        }
        .onAppear {
            // Fade-in only (avoid scale animations during sheet presentation to reduce stutter)
            withAnimation(.easeOut(duration: 0.18)) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Subviews (split for compiler performance)
    private var backgroundView: some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .onTapGesture {
                guard !isConfirming else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    appearAnimation = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onCancel()
                }
            }
    }
    
    private var dialogCard: some View {
        VStack(spacing: 16) {
            headerView
            pointsImpactCard
            timeLimitCallout
            buttonsView
        }
        .padding(22)
        .background(cardBackground)
        .padding(.horizontal, 24)
        .opacity(appearAnimation ? 1.0 : 0)
    }
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Text(rewardData.icon)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Redemption")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
                
                Text(rewardData.rewardTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .whiteTextShadow(opacity: 0.25, radius: 2, x: 0, y: 2)
                    .lineLimit(2)
            }
            
            Spacer()
        }
    }
    
    private var pointsImpactCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(rewardData.currentPoints)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
                    
                    Text("Current")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 44)
                
                VStack(spacing: 4) {
                    Text("\(pointsAfter)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.9, blue: 0.5))
                        .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                    
                    Text("After")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity)
            }
            
            Text("Points used: \(rewardData.pointsRequired)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
    
    private var timeLimitCallout: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.25))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            
            Text("Redeem within 15 minutes")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .whiteTextShadow(opacity: 0.3, radius: 2, x: 0, y: 2)
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
    
    private var buttonsView: some View {
        VStack(spacing: 12) {
            Button(action: confirmTapped) {
                HStack(spacing: 10) {
                    if isConfirming {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(
                                    tint: Color(red: 0.15, green: 0.1, blue: 0.0)
                                )
                            )
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    
                    Text(isConfirming ? "Redeeming..." : "Confirm Redemption")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(confirmButtonBackground)
                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .disabled(isConfirming)
            .scaleEffect(isConfirming ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isConfirming)
            
            Button(action: cancelTapped) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .whiteTextShadow(opacity: 0.2, radius: 2, x: 0, y: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(cancelButtonBackground)
            }
            .disabled(isConfirming)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.12, blue: 0.16).opacity(0.94),
                        Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
    
    private var confirmButtonBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.9, blue: 0.5),
                        Color(red: 1.0, green: 0.75, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
    
    private var cancelButtonBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
    
    private func confirmTapped() {
        guard !isConfirming else { return }
        isConfirming = true
        DispatchQueue.main.async {
            onConfirm()
        }
    }
    
    private func cancelTapped() {
        guard !isConfirming else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            appearAnimation = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onCancel()
        }
    }
}

// MARK: - Redemption Success Screen
struct RedemptionSuccessScreen: View {
    let successData: RedemptionSuccessData
    let onDismiss: () -> Void
    
    @State private var showCode = false
    @State private var showConfetti = false
    @State private var timeRemaining: String = ""
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.15, green: 0.15, blue: 0.2)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Main content
                VStack(spacing: 32) {
                    // Success icon and title
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                            .scaleEffect(showConfetti ? 1.2 : 1.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showConfetti)
                        
                        VStack(spacing: 8) {
                            Text("Reward Redeemed!")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .whiteTextShadow()
                            
                            Text(successData.rewardTitle)
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.9))
                                .whiteTextShadow()
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    // Redemption QR (large display)
                    VStack(spacing: 16) {
                        Text("Show this QR code to your cashier")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .whiteTextShadow()
                            .multilineTextAlignment(.center)
                        
                        RewardRedemptionQRCodeView(text: successData.redemptionCode, foregroundColor: .black, backgroundColor: .white)
                            .frame(width: 260, height: 260)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                            )
                            .scaleEffect(showCode ? 1.03 : 1.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showCode)

                        // Small fallback (helps if camera scan fails)
                        Text("Code: \(successData.redemptionCode)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .whiteTextShadow()
                    }
                    
                    // Reward details
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(successData.pointsDeducted)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("Points Used")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .whiteTextShadow()
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(successData.newPointsBalance)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("New Balance")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .whiteTextShadow()
                            }
                        }
                        
                        // Expiration timer
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                                .font(.title3)
                            
                            Text("Expires in: \(timeRemaining)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .whiteTextShadow()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                                )
                        )
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    
                    Spacer()
                    
                    // Done button
                    Button(action: onDismiss) {
                        Text("Done")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .whiteTextShadow()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.blue,
                                                Color.blue.opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .overlay(
            // Confetti effect
            ZStack {
                if showConfetti {
                    ForEach(0..<25, id: \.self) { index in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .offset(
                                x: CGFloat.random(in: -150...150),
                                y: CGFloat.random(in: -300...0)
                            )
                            .opacity(0.8)
                            .animation(
                                .easeOut(duration: 2.0)
                                .delay(Double.random(in: 0...0.5)),
                                value: showConfetti
                            )
                    }
                }
            }
        )
        .onAppear {
            // Start animations
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                showConfetti = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showCode = true
                }
            }
            
            // Start timer
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let timeInterval = successData.expiresAt.timeIntervalSince(Date())
            
            if timeInterval <= 0 {
                timeRemaining = "Expired"
                timer?.invalidate()
            } else {
                let minutes = Int(timeInterval / 60)
                let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
                timeRemaining = "\(minutes)m \(seconds)s"
            }
        }
        
        // Initial update
        let timeInterval = successData.expiresAt.timeIntervalSince(Date())
        if timeInterval <= 0 {
            timeRemaining = "Expired"
        } else {
            let minutes = Int(timeInterval / 60)
            let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
            timeRemaining = "\(minutes)m \(seconds)s"
        }
    }
} 