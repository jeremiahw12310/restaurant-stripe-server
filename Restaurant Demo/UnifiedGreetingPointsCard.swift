import SwiftUI

// MARK: - Unified Greeting + Points Card
struct UnifiedGreetingPointsCard: View {
    @EnvironmentObject var userVM: UserViewModel
    let animatedPoints: Double
    @Binding var animate: Bool
    let onOrder: () -> Void
    let onRedeem: () -> Void
    let onScan: () -> Void
    let onDirections: () -> Void
    let onRefer: () -> Void
    let onAdminOffice: (() -> Void)?

    private var firstName: String { userVM.firstName.isEmpty ? "Friend" : userVM.firstName }

    var body: some View {
        VStack(spacing: 16) {
            if userVM.isLoading {
                // Loading skeleton
                VStack(spacing: 12) {
                    HStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.3)).frame(width: 90, height: 12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.3)).frame(width: 60, height: 18)
                    }
                    .redacted(reason: .placeholder)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 14)
                        .redacted(reason: .placeholder)

                    HStack(spacing: 10) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.25)).frame(height: 32)
                        }
                    }
                    .redacted(reason: .placeholder)
                }
            } else {
            // Top row: logo (left) + points (center-left) - moved upward
            HStack(alignment: .center, spacing: 20) {
                // Restaurant logo - larger and left-aligned, positioned higher
                Image("logo2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
                    .offset(y: -10)

                // Compact points display - moved to left and upward
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Points number
                    ZStack(alignment: .trailing) {
                        Text("\(userVM.points)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .opacity(0)
                            .accessibilityHidden(true)
                        Text("\(Int(animatedPoints))")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.darkGoldGradient)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .animation(.easeInOut(duration: 0.3), value: animatedPoints)
                    }
                    .scaleEffect(animate ? 1.0 : 0.9)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: animate)
                    
                    // "Points" label to the right of number
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Theme.energyOrange)
                            Text("Points")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                        }
                    }
                    .opacity(animate ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.4).delay(0.25), value: animate)
                }
                .contentShape(Rectangle())
                .onTapGesture { onRedeem() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open Rewards")
                .accessibilityHint("Opens the rewards screen")
                .offset(y: -10)
                
                Spacer()
            }

            // Progress bar to 2000
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Neutral, rounded track
                        Capsule()
                            .fill(Theme.modernCardSecondary)
                            .frame(height: 13)

                        // Progress fill — rounded ends at any width
                        let targetForAnimation = max(CGFloat(userVM.points), 2000.0)
                        let progress = max(0, min(CGFloat(animatedPoints) / targetForAnimation, 1.0))
                        Capsule()
                            .fill(Theme.primaryGold)
                            .frame(width: progress * geo.size.width, height: 13)
                            .animation(.easeInOut(duration: 0.2), value: animatedPoints)

                        // Circular checkpoint markers at each milestone (removed 500)
                        let milestones: [CGFloat] = [250, 450, 650, 850, 1500, 2000]
                        ForEach(milestones, id: \.self) { m in
                            let x = (m / 2000.0) * geo.size.width
                            let isCompleted = CGFloat(userVM.points) >= m
                            
                            ZStack {
                                // Outer ring
                                Circle()
                                    .strokeBorder(isCompleted ? Theme.primaryGold : Theme.modernSecondary.opacity(0.4), lineWidth: 2)
                                    .frame(width: 16, height: 16)
                                
                                // Filled circle for completed milestones
                                if isCompleted {
                                    Circle()
                                        .fill(Theme.primaryGold)
                                        .frame(width: 10, height: 10)
                                }
                            }
                            .position(x: x, y: 6.5)
                        }

                        // Next goal indicator with label and icon - more prominent with extra space
                        // Use final points value (userVM.points) instead of animatedPoints to prevent number flickering
                        if let next = ([250, 450, 650, 850, 1500, 2000] as [CGFloat]).first(where: { CGFloat(userVM.points) < $0 }) {
                            let x = (next / 2000.0) * geo.size.width
                            VStack(spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: "target")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("NEXT GOAL")
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                        .tracking(0.5)
                                }
                                .foregroundColor(Theme.energyOrange)
                                
                                Text("\(Int(next))")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundColor(Theme.primaryGold)
                            }
                            .position(x: x, y: -16)
                            .opacity(animate ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.3).delay(0.8), value: animate)
                        }
                    }
                }
                .frame(height: 13)
                HStack {
                    Text("0")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    Spacer()
                    Text("2,000")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .opacity(animate ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.4).delay(0.35), value: animate)
            }
            .contentShape(Rectangle())
            .onTapGesture { onRedeem() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Open Rewards")
            .accessibilityHint("Tap to view available rewards")

            // Bottom actions (scrollable + larger + reordered)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Admin Office first (only for admins)
                    if userVM.isAdmin, let onAdminOffice = onAdminOffice {
                        smallActionButton(title: "Admin Office", icon: "building.2.fill", color: .purple, action: onAdminOffice)
                    }
                    // Order first (red)
                    smallActionButton(title: "Order", icon: "bag.fill", color: Theme.energyRed, action: onOrder)
                    // Scan next
                    smallActionButton(title: "Scan", icon: "camera.fill", color: Theme.energyBlue, action: onScan)
                    // Directions next
                    smallActionButton(title: "Directions", icon: "location.fill", color: Theme.energyOrange, action: onDirections)
                    // Redeem last (to the right, reachable via scroll)
                    smallActionButton(title: "Redeem", icon: "gift.fill", color: Theme.energyGreen, action: onRedeem)
                    // Refer a Friend
                    smallActionButton(title: "Refer a Friend", icon: "person.badge.plus", color: Theme.energyBlue, action: {
                        DebugLogger.debug("🔗 Refer button tapped (UnifiedGreetingPointsCard)", category: "UI")
                        onRefer()
                        NotificationCenter.default.post(name: Notification.Name("presentReferral"), object: nil)
                    })
                }
            }
            .opacity(animate ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.4).delay(0.4), value: animate)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 18, x: 0, y: 8)
                .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
        .scaleEffect(animate ? 1.0 : 0.95)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1), value: animate)
    }

    // MARK: - Helpers
    private var eligibleToRedeem: Bool {
        // Eligible if any reward option threshold is met; simplest proxy: >= 250
        return Int(animatedPoints) >= 250
    }

    private var loyaltyStatus: String {
        switch userVM.lifetimePoints {
        case 0..<1000: return "BRONZE"
        case 1000..<5000: return "SILVER"
        case 5000..<15000: return "GOLD"
        default: return "PLATINUM"
        }
    }

    private var loyaltyStatusColor: Color {
        switch loyaltyStatus {
        case "BRONZE": return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "SILVER": return Color(red: 0.7, green: 0.7, blue: 0.7)
        case "GOLD": return Color(red: 1.0, green: 0.8, blue: 0.0)
        default: return Color(red: 0.9, green: 0.9, blue: 1.0)
        }
    }

    private var loyaltyGradient: LinearGradient {
        switch loyaltyStatus {
        case "BRONZE":
            return LinearGradient(colors: [Color(red: 0.75, green: 0.5, blue: 0.25), Color(red: 0.85, green: 0.6, blue: 0.35)], startPoint: .leading, endPoint: .trailing)
        case "SILVER":
            return LinearGradient(colors: [Color(red: 0.7, green: 0.7, blue: 0.7), Color(red: 0.85, green: 0.85, blue: 0.9)], startPoint: .leading, endPoint: .trailing)
        case "GOLD":
            return Theme.darkGoldGradient
        default:
            return LinearGradient(colors: [Color(red: 0.85, green: 0.85, blue: 1.0), Color(red: 0.75, green: 0.75, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func smallActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14.5, weight: .black))
                Text(title.uppercased())
                    .font(.system(size: 12.6, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(LinearGradient(gradient: Gradient(colors: [color, color.opacity(0.85)]), startPoint: .topLeading, endPoint: .bottomTrailing))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Heat-map Color Helper
    private func currentHeatColor(for points: CGFloat) -> Color {
        // Define segments aligned with rewards
        let stops: [(threshold: CGFloat, color: Color)] = [
            (0, .orange),        // start
            (250, .red),         // 250 tier
            (450, .blue),        // 450 tier
            (500, .green),       // 500 tier
            (650, .purple),      // 650 tier
            (850, .pink),        // 850 tier
            (1500, .brown),      // 1500 tier
            (2000, Color(red: 1.0, green: 0.84, blue: 0.0)) // gold
        ]

        // Find surrounding stops
        var lower = stops[0]
        var upper = stops.last!
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if points >= a.threshold && points <= b.threshold {
                lower = a
                upper = b
                break
            }
        }

        let span = max(upper.threshold - lower.threshold, 1)
        let t = Double((points - lower.threshold) / span)
        return interpolateColor(from: lower.color, to: upper.color, progress: t)
    }

    private func interpolateColor(from: Color, to: Color, progress: Double) -> Color {
        let fromComponents = UIColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = UIColor(to).cgColor.components ?? [0, 0, 0, 1]
        let red = fromComponents[0] + (toComponents[0] - fromComponents[0]) * CGFloat(progress)
        let green = fromComponents[1] + (toComponents[1] - fromComponents[1]) * CGFloat(progress)
        let blue = fromComponents[2] + (toComponents[2] - fromComponents[2]) * CGFloat(progress)
        let alpha = fromComponents[3] + (toComponents[3] - fromComponents[3]) * CGFloat(progress)
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}

#if DEBUG
struct UnifiedGreetingPointsCard_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedGreetingPointsCard(
            animatedPoints: 750,
            animate: .constant(true),
            onOrder: {},
            onRedeem: {},
            onScan: {},
            onDirections: {},
            onRefer: {},
            onAdminOffice: nil
        )
        .environmentObject(UserViewModel())
        .preferredColorScheme(.dark)
    }
}
#endif




