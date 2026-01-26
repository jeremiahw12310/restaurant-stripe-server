import SwiftUI

// MARK: - Confetti Piece Model
struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var rotation: Double
    var scale: Double
    var color: Color
    var velocity: Double
    var angularVelocity: Double
}

struct WelcomePopupView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var userVM: UserViewModel
    var onPointsAdded: (() -> Void)?
    
    // Confetti animation states
    @State private var confettiPieces: [ConfettiPiece] = []
    @State private var showConfetti = false
    @State private var showPoints = false
    @State private var showMessage = false
    @State private var confettiTimer: Timer?
    
    // Colors for confetti
    private let confettiColors: [Color] = [
        .red, .blue, .green, .yellow, .purple, .orange, .pink
    ]
    
    var body: some View {
        ZStack {
            // Main popup content
            VStack(spacing: 24) {
                // Confetti container
                ZStack {
                    // Confetti pieces
                    ForEach(confettiPieces) { piece in
                        Circle()
                            .fill(piece.color)
                            .frame(width: 8, height: 8)
                            .position(x: piece.x, y: piece.y)
                            .rotationEffect(.degrees(piece.rotation))
                            .scaleEffect(piece.scale)
                    }
                    
                    // Main content
                    VStack(spacing: 20) {
                        // Welcome icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.85, green: 0.65, blue: 0.25), Color(red: 0.75, green: 0.55, blue: 0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                            
                            Image(systemName: "party.popper.fill")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .scaleEffect(showConfetti ? 1.1 : 0.8)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: showConfetti)
                        
                        // Welcome text
                        VStack(spacing: 8) {
                            Text("Welcome to")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text("Dumpling House!")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .opacity(showMessage ? 1 : 0)
                        .offset(y: showMessage ? 0 : 20)
                        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: showMessage)
                        
                        // Points earned
                        VStack(spacing: 12) {
                            Text("+5")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.25))
                                                            .scaleEffect(showPoints ? 1.2 : 0.8)
                            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: showPoints)
                            
                            Text("Welcome Points!")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .opacity(showPoints ? 1 : 0)
                        .offset(y: showPoints ? 0 : 20)
                        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: showPoints)
                        
                        // Message
                        VStack(spacing: 16) {
                            Text("Thanks for signing up!")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Scan receipts to earn more points and unlock exclusive rewards.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .opacity(showMessage ? 1 : 0)
                        .offset(y: showMessage ? 0 : 20)
                        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: showMessage)
                        
                        // Done button
                        Button(action: {
                            dismissPopup()
                        }) {
                            Text("Done")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.85, green: 0.65, blue: 0.25), Color(red: 0.75, green: 0.55, blue: 0.15)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                                .shadow(color: Color(red: 0.75, green: 0.55, blue: 0.15).opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .opacity(showMessage ? 1 : 0)
                        .offset(y: showMessage ? 0 : 20)
                        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: showMessage)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 40)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                    )
                    .padding(.horizontal, 20)
                }
            }
        }
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            confettiTimer?.invalidate()
            confettiTimer = nil
        }
    }
    
    private func startAnimations() {
        // Create confetti pieces
        createConfetti()
        
        // Start background fade-in immediately for smooth overlay
        withAnimation(.easeInOut(duration: 0.4)) {
            showConfetti = true
        }
        
        // Start content animation sequence with smoother timing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                // Content animations will trigger based on showConfetti being true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showPoints = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showMessage = true
            }
        }
    }
    
    private func createConfetti() {
        confettiPieces = []
        for _ in 0..<50 {
            let piece = ConfettiPiece(
                x: Double.random(in: 0...UIScreen.main.bounds.width),
                y: -50,
                rotation: Double.random(in: 0...360),
                scale: Double.random(in: 0.5...1.5),
                color: confettiColors.randomElement() ?? .red,
                velocity: Double.random(in: 100...300),
                angularVelocity: Double.random(in: -5...5)
            )
            confettiPieces.append(piece)
        }
        
        // Start confetti animation
        confettiTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                for i in self.confettiPieces.indices {
                    self.confettiPieces[i].y += self.confettiPieces[i].velocity * 0.05
                    self.confettiPieces[i].rotation += self.confettiPieces[i].angularVelocity
                }
                
                // Remove confetti that has fallen off screen
                self.confettiPieces.removeAll { piece in
                    piece.y > UIScreen.main.bounds.height + 50
                }
                
                // Stop animation when all confetti is gone
                if self.confettiPieces.isEmpty {
                    self.confettiTimer?.invalidate()
                    self.confettiTimer = nil
                }
            }
        }
    }
    
    private func dismissPopup() {
        // Add welcome points when popup is dismissed
        userVM.addWelcomePoints { success, blockedReason in
            if success {
                if blockedReason == "phone_previously_claimed" {
                    print("ℹ️ Welcome points blocked - phone previously claimed")
                } else {
                    print("✅ Welcome points added successfully")
                }
                // Trigger points animation callback
                DispatchQueue.main.async {
                    self.onPointsAdded?()
                }
            } else {
                print("❌ Failed to add welcome points")
            }
        }
        
        // Fade out background first, then dismiss
        withAnimation(.easeInOut(duration: 0.2)) {
            showConfetti = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isPresented = false
            }
        }
    }
}

#if DEBUG
struct WelcomePopupView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomePopupView(isPresented: .constant(true))
            .environmentObject(UserViewModel())
            .previewDevice("iPhone 16")
    }
}
#endif 