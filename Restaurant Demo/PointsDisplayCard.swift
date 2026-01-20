import SwiftUI
import FirebaseAuth

// MARK: - Points Display Card Component
struct PointsDisplayCard: View {
    @ObservedObject var userVM: UserViewModel
    let animatedPoints: Double
    let cardAnimations: [Bool]
    let primaryGold: Color
    
    init(userVM: UserViewModel, animatedPoints: Double, cardAnimations: [Bool], primaryGold: Color = Color(red: 1.0, green: 0.8, blue: 0.0)) {
        self.userVM = userVM
        self.animatedPoints = animatedPoints
        self.cardAnimations = cardAnimations
        self.primaryGold = primaryGold
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 15) {
                avatarView
                loyaltyStatusView
                Spacer(minLength: 10)
                pointsCounterView
            }
            progressBarView
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(primaryGold.opacity(0.9), lineWidth: 4)
                )
                .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
                .shadow(color: primaryGold.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .padding(.horizontal, 20)
        .scaleEffect(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.8)
        .opacity(cardAnimations.indices.contains(0) && cardAnimations[0] ? 1.0 : 0.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardAnimations.indices.contains(0) ? cardAnimations[0] : false)
    }
    
    private var avatarView: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [primaryGold, Color(red: 0.95, green: 0.85, blue: 0.7)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            )
            .overlay(
                Text(userInitials)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            )
            .shadow(color: primaryGold.opacity(0.4), radius: 8, x: 0, y: 4)
    }
    
    private var loyaltyStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back!")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
            
            HStack(spacing: 8) {
                Text(loyaltyStatus)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(primaryGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(primaryGold.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(primaryGold.opacity(0.3), lineWidth: 1)
                            )
                    )
                
                if userVM.isVerified {
                    Image("verified")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            }
        }
    }
    
    private var pointsCounterView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("POINTS")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1)
            
            // Fixed width container to prevent shaking
            ZStack(alignment: .trailing) {
                // Background text with final value for sizing (invisible)
                Text("\(Int(userVM.points))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .opacity(0)
                    .accessibilityHidden(true)
                
                // Animated text
                Text("\(Int(animatedPoints))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(primaryGold)
                    .shadow(color: primaryGold.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    private var progressBarView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Progress to next reward")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(animatedPoints))/100")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(primaryGold)
            }
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [primaryGold, Color(red: 0.95, green: 0.85, blue: 0.7)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(1.0, animatedPoints / 100.0)) * UIScreen.main.bounds.width * 0.8, height: 8)
                    .shadow(color: primaryGold.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var userInitials: String {
        let firstName = userVM.firstName.isEmpty ? "User" : userVM.firstName
        return String(firstName.prefix(2)).uppercased()
    }
    
    private var loyaltyStatus: String {
        switch userVM.lifetimePoints {
        case 0..<1000:
            return "BRONZE"
        case 1000..<5000:
            return "SILVER"
        case 5000..<15000:
            return "GOLD"
        default:
            return "PLATINUM"
        }
    }
} 