import SwiftUI
import AVKit
import Kingfisher
import Firebase
import FirebaseAuth
import MapKit

// MARK: - Home Rewards Section (extracted from HomeView, UI unchanged)
struct HomeRewardsSection: View {
    @EnvironmentObject var sharedRewardsVM: RewardsViewModel
    @EnvironmentObject var userVM: UserViewModel

    // Show countdown & ability to reopen reward card
    @State private var showRedeemedCard = false


    // Controls from parent
    @Binding var showDetailedRewards: Bool
    @Binding var animate: Bool // corresponds to cardAnimations[1]

    // Animated points passed in so progress bars stay in sync with HomeView
    let animatedPoints: Double

    // Extracted large view builder to ease compiler load
    @ViewBuilder
    private var rewardsMainStack: some View {
        VStack(spacing: 5) {
            // Active countdown at top if a reward was recently redeemed
            if let active = sharedRewardsVM.activeRedemption {
                RedeemedRewardsCountdownCard(activeRedemption: active) {
                    sharedRewardsVM.activeRedemption = nil
                }
                .onTapGesture { showRedeemedCard = true }
                .padding(.bottom, 8)
            }
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Image("dumpaward")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 90, height: 90)
                            .shadow(color: Color.blue.opacity(0.4), radius: 12, x: 0, y: 6)
                            .scaleEffect(animate ? 1.5 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: animate)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REWARDS")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.25))
                            .opacity(animate ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.5).delay(0.3), value: animate)
                    }
                }
                Spacer()
                Button(action: { showDetailedRewards = true }) {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.8, green: 0.6, blue: 0.2),
                                        Color(red: 0.7, green: 0.5, blue: 0.1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(red: 0.8, green: 0.6, blue: 0.2).opacity(0.5), radius: 8, x: 0, y: 4)
                    )
                }
                .padding(.trailing, 4)
                .opacity(animate ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(0.5), value: animate)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(Array(sharedRewardsVM.rewardOptions.enumerated()), id: \.element.title) { index, reward in
                        DiagonalRewardCard(
                            title: reward.title,
                            description: reward.description,
                            pointsRequired: reward.pointsRequired,
                            currentPoints: Int(animatedPoints),
                            color: reward.color,
                            icon: reward.icon,
                            category: reward.category,
                            imageName: reward.imageName,
                            compact: true
                        )
                        .scaleEffect(animate ? 1.05 : 0.9)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6 + Double(index) * 0.1), value: animate)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .frame(height: 200)
        }
    }


    var body: some View {
        VStack(spacing: 12) {
            // Active countdown at top if a reward was recently redeemed
            if let active = sharedRewardsVM.activeRedemption {
                RedeemedRewardsCountdownCard(activeRedemption: active) {
                    sharedRewardsVM.activeRedemption = nil
                }
                .onTapGesture { showRedeemedCard = true }
                .padding(.bottom, 8)
            }
            
            // Dutch Bros style header
            HStack {
                HStack(spacing: 8) {
                    // Enhanced award icon with Dutch Bros energy - moved closer to text
                    ZStack {
                        Image("dumpaward")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 75, height: 75) // 50% bigger (50 * 1.5 = 75)
                            .scaleEffect(animate ? 1.0 : 0.0)
                            .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.3), value: animate)
                    }

                    Text("REWARDS")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .minimumScaleFactor(0.5) // Scale down to 50% if needed to fit
                        .lineLimit(1) // Ensure single line
                        .multilineTextAlignment(.leading) // Keep left alignment
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.4), value: animate)
                }

                Spacer()

                // Enhanced View All button with modern design
                Button(action: { showDetailedRewards = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        VStack(spacing: 1) {
                            Text("ALL")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .tracking(0.4)
                            Text("REWARDS")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.25)
                        }
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(animate ? 1.0 : 0.9)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).repeatForever(autoreverses: true), value: animate)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.3, blue: 0.1),
                                            Color(red: 0.8, green: 0.6, blue: 0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        }
                        .shadow(color: Color(red: 0.8, green: 0.6, blue: 0.2).opacity(0.45), radius: 8, x: 0, y: 4)
                    )
                }
                .opacity(animate ? 1.0 : 0.0)
                .scaleEffect(animate ? 1.0 : 0.9)
                .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.6), value: animate)
            }

            // Enhanced rewards scroll view (Home-only sizing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(sharedRewardsVM.rewardOptions.enumerated()), id: \.element.title) { index, reward in
                        DiagonalRewardCard(
                            title: reward.title,
                            description: reward.description,
                            pointsRequired: reward.pointsRequired,
                            currentPoints: Int(animatedPoints),
                            color: reward.color,
                            icon: reward.icon,
                            category: reward.category,
                            imageName: reward.imageName,
                            compact: true
                        )
                        // Slightly larger on Home so inner elements don’t feel tiny
                        .scaleEffect(animate ? 1.05 : 0.9)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.7 + Double(index) * 0.1), value: animate)
                    }
                }
                .padding(.horizontal, 24)
                // Slightly tighter top padding so cards sit closer to the header
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            // Match height to the updated reward card layout so nothing gets clipped
            .frame(height: 230)
        }
        // Allow a bit more room when a redeemed countdown is present so cards
        // don’t visually overlap the "REWARDS" header
        .frame(height: sharedRewardsVM.activeRedemption != nil ? 430 : 310)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
        .scaleEffect(animate ? 1.0 : 0.9)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: animate)
        .sheet(isPresented: $showRedeemedCard) {
            if let success = sharedRewardsVM.lastSuccessData {
                RewardCardScreen(
                    userName: userVM.firstName.isEmpty ? "Your" : userVM.firstName,
                    successData: success,
                    onDismiss: { showRedeemedCard = false }
                )
            }
        }
    }
}

// MARK: - Home Header Section (Welcome + Logo) - Dutch Bros Style
struct HomeHeaderSection: View {
    @EnvironmentObject var userVM: UserViewModel
    @Binding var animate: Bool // cardAnimations[0]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                // Dutch Bros-style welcome message
                HStack(spacing: 6) {
                    Text("Hey there,")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.2), value: animate)
                    
                }

                // Bold name with Dutch Bros energy
                HStack(spacing: 12) {
                    Text(userVM.firstName)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.4), value: animate)
                        .scaleEffect(animate ? 1.0 : 0.8)
                        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.4), value: animate)

                    if userVM.isVerified {
                        ZStack {
                            Circle()
                                .fill(Theme.energyGradient)
                                .frame(width: 32, height: 32)
                                .shadow(color: Theme.energyOrange.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            Image("verified")
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        .opacity(animate ? 1.0 : 0.0)
                        .scaleEffect(animate ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.6), value: animate)
                    }
                }
                
                // Dutch Bros-style status line
                HStack(spacing: 8) {
                    Text("Ready to fuel up?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.5), value: animate)
                    
                    Spacer()
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            // Enhanced logo with Dutch Bros energy
            ZStack {
                
                // Logo with enhanced shadow
                Image("logo2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .scaleEffect(1.35) // Make the logo 25% smaller than 2.0
                    .shadow(color: Theme.goldShadow, radius: 12, x: 0, y: 6)
                    .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.4), value: animate)
            }
            .layoutPriority(2)
        }
        .frame(minHeight: 80, maxHeight: 120)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCard)
                .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 20)
        .scaleEffect(animate ? 1.0 : 0.95)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: animate)
    }
}

// MARK: - Points & Avatar Glass Card - Dutch Bros Style
struct HomePointsCardSection: View {
    @EnvironmentObject var userVM: UserViewModel
    // animated points number from parent
    let animatedPoints: Double
    // binding to parent progress animation bool (cardAnimations[0])
    @Binding var animate: Bool

    // Helpers - Dutch Bros style loyalty tiers
    private var loyaltyStatus: String {
        switch userVM.lifetimePoints {
        case 0..<500: return "STARTER"
        case 500..<1500: return "REGULAR"
        case 1500..<4000: return "VIP"
        case 4000..<10000: return "LEGEND"
        case 10000..<25000: return "CHAMPION"
        default: return "ICON"
        }
    }
    private var loyaltyStatusColor: Color {
        switch userVM.lifetimePoints {
        case 0..<500: return Theme.modernSecondary
        case 500..<1500: return Theme.energyBlue
        case 1500..<4000: return Theme.energyGreen
        case 4000..<10000: return Theme.primaryGold
        case 10000..<25000: return Theme.energyOrange
        default: return Theme.energyRed
        }
    }
    private var loyaltyGradient: LinearGradient {
        switch userVM.lifetimePoints {
        case 0..<500: return LinearGradient(colors: [Theme.modernSecondary, Theme.modernSecondary.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case 500..<1500: return LinearGradient(colors: [Theme.energyBlue, Theme.energyBlue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case 1500..<4000: return LinearGradient(colors: [Theme.energyGreen, Theme.energyGreen.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case 4000..<10000: return Theme.darkGoldGradient
        case 10000..<25000: return LinearGradient(colors: [Theme.energyOrange, Theme.energyRed], startPoint: .leading, endPoint: .trailing)
        default: return LinearGradient(colors: [Theme.energyRed, Theme.energyOrange], startPoint: .leading, endPoint: .trailing)
        }
    }
    private var progressBarColor: Color {
        let points = Int(animatedPoints)
        
        // Use the same colors as reward cards for smooth transitions
        let colors: [Color] = [
            .orange,    // 250 pts - Peanut Sauce
            .blue,      // 450 pts - Fruit Tea, Milk Tea, Lemonade, Coffee
            .green,     // 500 pts - Small Appetizer
            .purple,    // 650 pts - Larger Appetizer
            .pink,      // 850 pts - Pizza Dumplings
            .indigo,    // 850 pts - Lunch Special
            .brown,     // 1500 pts - 12-Piece Dumplings
            Color(red: 1.0, green: 0.84, blue: 0.0)  // 2000 pts - Full Combo (gold)
        ]
        
        // Smooth color transitions based on points
        let maxPoints = 2000.0
        let progress = min(Double(points) / maxPoints, 1.0)
        let colorIndex = min(Int(progress * Double(colors.count - 1)), colors.count - 1)
        
        // Interpolate between colors for smooth transitions
        if colorIndex < colors.count - 1 {
            let currentColor = colors[colorIndex]
            let nextColor = colors[colorIndex + 1]
            let localProgress = (progress * Double(colors.count - 1)) - Double(colorIndex)
            
            return interpolateColor(from: currentColor, to: nextColor, progress: localProgress)
        } else {
            return colors[colorIndex]
        }
    }
    
    // Helper function to interpolate between colors
    private func interpolateColor(from: Color, to: Color, progress: Double) -> Color {
        let fromComponents = UIColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = UIColor(to).cgColor.components ?? [0, 0, 0, 1]
        
        let red = fromComponents[0] + (toComponents[0] - fromComponents[0]) * CGFloat(progress)
        let green = fromComponents[1] + (toComponents[1] - fromComponents[1]) * CGFloat(progress)
        let blue = fromComponents[2] + (toComponents[2] - fromComponents[2]) * CGFloat(progress)
        let alpha = fromComponents[3] + (toComponents[3] - fromComponents[3]) * CGFloat(progress)
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header with energy
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("POINTS BALANCE")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .tracking(1.2)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.2), value: animate)
                    
                    Text("Keep earning to unlock rewards!")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.3), value: animate)
                }
                
                Spacer()
                
                // Lifetime tier indicator in top-right corner
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(loyaltyStatus)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(0.3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(loyaltyGradient)
                                    .shadow(color: loyaltyStatusColor.opacity(0.4), radius: 6, x: 0, y: 3)
                            )
                            .onTapGesture {
                                // Navigate to lifetime points view
                                NotificationCenter.default.post(name: Notification.Name("showLifetimePoints"), object: nil)
                            }
                        
                        // Energy sparkle
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.energyOrange)
                            .opacity(animate ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.6).delay(0.6), value: animate)
                    }
                    
                    Text("Lifetime: \(userVM.lifetimePoints)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.7), value: animate)
                }
            }
            
            // Main content row
            HStack(spacing: 20) {
                // Enhanced avatar
                avatarView
                
                // Points counter with energy
                pointsCounterView
                
                Spacer()
            }
            
            // Enhanced progress bar
            progressBarView

            // Action buttons carousel (Order first, then Directions)
            actionsCarouselView
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
        .scaleEffect(animate ? 1.0 : 0.9)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: animate)
    }

    // MARK: - Enhanced Sub views with Dutch Bros energy
    private var avatarView: some View {
        ZStack {
            // Background glow effect
            Circle()
                .fill(Theme.lightGoldGradient)
                .frame(width: 90, height: 90)
                .opacity(0.3)
                .blur(radius: 8)
                .scaleEffect(animate ? 1.0 : 0.8)
                .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3), value: animate)
            
            if let profileImage = userVM.profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Theme.darkGoldGradient, lineWidth: 3)
                    )
                    .shadow(color: Theme.goldShadow, radius: 16, x: 0, y: 8)
                    .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
            } else {
                Circle()
                    .fill(Theme.darkGoldGradient)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text(userVM.avatarEmoji)
                            .font(.system(size: 40))
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                    .shadow(color: Theme.goldShadow, radius: 16, x: 0, y: 8)
                    .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
            }
        }
        .scaleEffect(animate ? 1.0 : 0.8)
        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.4), value: animate)
        .onTapGesture {
            // Route to the full-screen More tab instead of showing account overlays
            NotificationCenter.default.post(name: .switchToMoreTab, object: nil)
        }
    }


    private var pointsCounterView: some View {
        VStack(spacing: 8) {
            // Dutch Bros style points display with flexible width to accommodate large numbers
            HStack(alignment: .bottom, spacing: 4) {
                // Animated text with scaling to fit
                Text("\(Int(animatedPoints))")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3) // Scale down to 30% if needed to fit
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: animatedPoints)
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.6), value: animate)
                
                Text("pts")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .offset(y: -4)
            }
            
            Text("AVAILABLE")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .tracking(2.0)
                .opacity(animate ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.7), value: animate)
        }
        .frame(minWidth: 120, maxWidth: 180) // Flexible width with min/max bounds
        .scaleEffect(animate ? 1.0 : 0.8)
        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.6), value: animate)
    }

    private var progressBarView: some View {
        VStack(spacing: 12) {
            // Dutch Bros style progress bar
            ZStack(alignment: .leading) {
                // Background with energy
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.modernCardSecondary)
                    .frame(height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.darkGoldGradient, lineWidth: 2)
                    )
                
                // Dynamic progress bar with Dutch Bros energy
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Theme.energyOrange,
                                Theme.primaryGold,
                                Theme.energyOrange
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(CGFloat(animatedPoints / 2000.0) * (UIScreen.main.bounds.width - 160), UIScreen.main.bounds.width - 160)), height: 16)
                    .shadow(color: Theme.energyOrange.opacity(0.4), radius: 8, x: 0, y: 4)
                    .animation(.easeInOut(duration: 3.0), value: animatedPoints)
            }
            .animation(.easeInOut(duration: 3.0), value: animatedPoints)
            
            // Progress labels with Dutch Bros energy
            HStack {
                HStack(spacing: 4) {
                    Text("0")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    Text("START")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .tracking(1.0)
                }
                .opacity(animate ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.8), value: animate)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("2,000")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    Text("GOAL")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .tracking(1.0)
                }
                .opacity(animate ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.9), value: animate)
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            // Dutch Bros style card background
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
        }
    }

    // MARK: - Points Card Action Buttons Carousel
    @State private var carouselOffset: CGFloat = 0
    private var actionsCarouselView: some View {
        // Keep the existing button look, but render as fixed-width tiles in a looping marquee
        let buttonWidth: CGFloat = 220
        let buttonHeight: CGFloat = 56
        let spacing: CGFloat = 14

        // Order of items: ORDER NOW, then DIRECTIONS (swapped as requested)
        let items: [(title: String, icon: String, color: Color, action: () -> Void)] = [
            (
                title: "ORDER NOW",
                icon: "bag.fill",
                color: Theme.energyOrange,
                action: {
                    // Post a notification so parent can handle opening the order flow
                    NotificationCenter.default.post(name: Notification.Name("openOrder"), object: nil)
                }
            ),
            (
                title: "DIRECTIONS",
                icon: "location.fill",
                color: Theme.energyBlue,
                action: {
                    // Post a notification so parent can handle opening maps
                    NotificationCenter.default.post(name: Notification.Name("openDirections"), object: nil)
                }
            )
        ]

        // Total width of one sequence of buttons
        let sequenceWidth = (buttonWidth * CGFloat(items.count)) + (spacing * CGFloat(items.count - 1))

        return ZStack(alignment: .leading) {
            // First sequence
            HStack(spacing: spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    pointsActionButton(
                        title: items[index].title,
                        icon: items[index].icon,
                        color: items[index].color,
                        width: buttonWidth,
                        height: buttonHeight,
                        action: items[index].action
                    )
                }
            }
            .offset(x: carouselOffset)

            // Duplicated sequence for seamless infinite scroll
            HStack(spacing: spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    pointsActionButton(
                        title: items[index].title,
                        icon: items[index].icon,
                        color: items[index].color,
                        width: buttonWidth,
                        height: buttonHeight,
                        action: items[index].action
                    )
                }
            }
            .offset(x: carouselOffset + sequenceWidth + spacing)
        }
        .frame(height: buttonHeight)
        .clipped()
        .onAppear {
            carouselOffset = 0
            // Slow, continuous marquee motion
            withAnimation(.linear(duration: 12.0).repeatForever(autoreverses: false)) {
                carouselOffset = -(sequenceWidth + spacing)
            }
        }
        .padding(.top, 6)
    }

    // Keep styling consistent with actionButton while using fixed width for carousel tiles
    private func pointsActionButton(title: String, icon: String, color: Color, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)

                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(0.5)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color, color.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 6)
                    .shadow(color: Theme.buttonShadow, radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(animate ? 1.0 : 0.95)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6), value: animate)
    }
}

// MARK: - Location & Actions Section (Map + Call/Directions/Order)
import MapKit

struct HomeLocationSection: View {
    // Map camera from parent to maintain position state
    @Binding var mapCameraPosition: MapCameraPosition
    // Coordinate constant supplied by parent
    let locationCoordinate: CLLocationCoordinate2D
    // Animation flag from parent (cardAnimations[3])
    @Binding var animate: Bool
    // Action closures supplied by parent
    let makeCall: () -> Void
    let openDirections: () -> Void
    let openOrder: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Dutch Bros style header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VISIT US")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .tracking(1.2)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.2), value: animate)
                    
                    Text("2117 Belcourt Ave")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.6).delay(0.3), value: animate)
                }
                
                Spacer()
                
                // Restaurant status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRestaurantCurrentlyOpen() ? Theme.energyGreen : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isRestaurantCurrentlyOpen() ? "OPEN" : "CLOSED")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(isRestaurantCurrentlyOpen() ? Theme.energyGreen : Color.red)
                }
                .opacity(animate ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.4), value: animate)
            }
            
            // Enhanced map with Dutch Bros energy
            ZStack {
                Map(position: $mapCameraPosition, interactionModes: []) {
                    Marker("Dumpling House", coordinate: locationCoordinate)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .onTapGesture {
                    // Open Apple Maps directly when map is tapped
                    let coordinate = locationCoordinate
                    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    mapItem.name = "Dumpling House"
                    mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                    ])
                }

            }

            // Dutch Bros style action buttons
            HStack(spacing: 16) {
                actionButton(title: "CALL US", icon: "phone.fill", color: Theme.energyGreen, action: makeCall)
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0.0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.6), value: animate)

                actionButton(title: "DIRECTIONS", icon: "location.fill", color: Theme.energyBlue, action: openDirections)
                    .scaleEffect(animate ? 1.0 : 0.8)
                    .opacity(animate ? 1.0 : 0.0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.7), value: animate)
            }

            // Enhanced order button with Dutch Bros energy
            GeometryReader { geometry in
                actionButton(title: "ORDER NOW", icon: "bag.fill", color: Theme.energyOrange) {
                    openOrder()
                }
                .scaleEffect(animate ? 1.0 : 0.8)
                .opacity(animate ? 1.0 : 0.0)
                .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.8), value: animate)
            }
            .frame(height: 60)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
        .scaleEffect(animate ? 1.0 : 0.9)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: animate)
    }

    // MARK: - Dutch Bros Style Action Button
    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)

                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color, color.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 6)
                    .shadow(color: Theme.buttonShadow, radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Restaurant Hours Logic
    private func isRestaurantCurrentlyOpen() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentDay = calendar.component(.weekday, from: now) - 1 // Convert to 0-6 (Sunday = 0)
        
        // Convert current time to decimal hours
        let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
        
        // Restaurant hours logic:
        // Sunday-Thursday: 11:30 AM - 9:00 PM (11.5 - 21)
        // Friday-Saturday: 11:30 AM - 10:00 PM (11.5 - 22)
        
        let isWeekend = currentDay == 5 || currentDay == 6 // Friday = 5, Saturday = 6
        let closingHour = isWeekend ? 22.0 : 21.0
        
        // Convert 11:30 AM to 11.5 for comparison
        return currentTimeDecimal >= 11.5 && currentTimeDecimal < closingHour
    }
}

// MARK: - Admin Office Section
struct HomeAdminSection: View {
    @EnvironmentObject var userVM: UserViewModel
    // Binding for animation (cardAnimations[4])
    @Binding var animate: Bool
    // Closure to open admin office
    let openAdminOffice: () -> Void
    // Closure to open rewards scan flow
    let openRewardsScan: () -> Void
    // Closure to open reward tier admin (NEW)
    var openRewardTierAdmin: (() -> Void)? = nil
    // Closure to open admin notifications (NEW)
    var openAdminNotifications: (() -> Void)? = nil

    var body: some View {
        // Only render if user is admin or employee
        if userVM.isAdmin || userVM.isEmployee {
            VStack(spacing: 20) {
                // Header
                HStack {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.purple, .blue]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                                .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)

                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .scaleEffect(animate ? 1.0 : 0.0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: animate)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Admin Office")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .opacity(animate ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.5).delay(0.3), value: animate)

                            Text("Manage user accounts")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black)
                                .opacity(animate ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.5).delay(0.4), value: animate)
                        }
                    }
                    Spacer()
                }

                VStack(spacing: 12) {
                    // Admin Office Button (admin only)
                    if userVM.isAdmin {
                        Button(action: openAdminOffice) {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)

                                Text("Enter Admin Office")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.purple, .blue]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                            )
                        }
                        
                        // Reward Tier Admin Button (admin only)
                        if let openRewardTierAdmin = openRewardTierAdmin {
                            Button(action: openRewardTierAdmin) {
                                HStack(spacing: 12) {
                                    Image(systemName: "gift.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)

                                    Text("Reward Item Config")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.green, .teal]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                                )
                            }
                        }
                        
                        // Send Notifications Button (admin only)
                        if let openAdminNotifications = openAdminNotifications {
                            Button(action: openAdminNotifications) {
                                HStack(spacing: 12) {
                                    Image(systemName: "bell.badge.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)

                                    Text("Send Notifications")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [.orange, .red]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                                )
                            }
                        }
                    }

                    // Rewards Scan Button (admin or employee)
                    Button(action: openRewardsScan) {
                        HStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.white)

                            Text("Rewards Scan")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Theme.primaryGold, Theme.energyOrange]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Theme.primaryGold.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                    }
                }
                .scaleEffect(animate ? 1.0 : 0.8)
                .opacity(animate ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5), value: animate)
            }
            .padding(25)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Theme.darkGoldGradient, lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .padding(.horizontal, 20)
            .scaleEffect(animate ? 1.0 : 0.8)
            .opacity(animate ? 1.0 : 0.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animate)
        }
    }
}

// MARK: - Priority Rewards Scanner Card (staff only)
struct RewardsScannerPriorityCard: View {
    let rewardTitle: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.primaryGold, Theme.energyOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                        .shadow(color: Theme.primaryGold.opacity(0.35), radius: 10, x: 0, y: 6)

                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rewards Scanner")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text(rewardTitle ?? "A customer is ready to redeem")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("OPEN")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(0.5)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [Theme.energyRed, Theme.energyOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Theme.cardShadow, radius: 14, x: 0, y: 8)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Rewards scanner")
    }
}




// Preview helper for design-time
#if DEBUG
struct HomeRewardsSection_Previews: PreviewProvider {
    static var previews: some View {
        HomeRewardsSection(showDetailedRewards: .constant(false), animate: .constant(true), animatedPoints: 750)
            .environmentObject(UserViewModel())
            .environmentObject(RewardsViewModel())
    }
}

struct HomeHeaderSection_Previews: PreviewProvider {
    static var previews: some View {
        HomeHeaderSection(animate: .constant(true))
            .environmentObject(UserViewModel())
    }
}
#endif

#if DEBUG
struct HomePointsCardSection_Previews: PreviewProvider {
    static var previews: some View {
        HomePointsCardSection(animatedPoints: 750, animate: .constant(true))
            .environmentObject(UserViewModel())
    }
}
#endif

// MARK: - Date Extension
extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
} 
