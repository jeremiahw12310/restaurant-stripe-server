import SwiftUI
import FirebaseAuth

// MARK: - Unified Rewards Screen
/// Premium Dutch Bros style rewards screen with energy and sophistication
struct UnifiedRewardsScreen: View {
    enum Mode {
        case tabRoot     // Used inside the tab-bar
        case modal       // Presented as a sheet / fullScreenCover
    }

    let mode: Mode

    // View-models injected from parent (same as existing views)
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    // Expired screen trigger
    @State private var showExpiredScreen = false
    
    // Points history sheet
    @State private var showPointsHistory = false
    @State private var showReferral = false
    
    // Reopen the active reward card
    @State private var showRedeemedCard = false
    
    // Animation states
    @State private var pointsScale: CGFloat = 1.0

    // Grid
    private let columns = [ GridItem(.flexible()), GridItem(.flexible()) ]

    // Filtered rewards helper
    private var filteredRewards: [RewardOption] {
        if rewardsVM.selectedCategory == "All" {
            return rewardsVM.rewardOptions
        } else {
            return rewardsVM.rewardOptions.filter { $0.category == rewardsVM.selectedCategory }
        }
    }
    
    // Almost there rewards (80%+ progress)
    private var almostThereRewards: [RewardOption] {
        rewardsVM.rewardOptions.filter { reward in
            let progress = Double(rewardsVM.userPoints) / Double(reward.pointsRequired)
            return progress >= 0.8 && progress < 1.0
        }
    }
    
    // Unlocked rewards
    private var unlockedRewards: [RewardOption] {
        rewardsVM.rewardOptions.filter { reward in
            rewardsVM.userPoints >= reward.pointsRequired
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                // Optimized static gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Theme.modernBackground,
                        Theme.modernCardSecondary,
                        Color(red: 0.15, green: 0.12, blue: 0.18)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Removed animated particles for performance

                ScrollView {
                    VStack(spacing: 0) {
                        // Hero header section
                        premiumHeaderView

                        // Active redeemed reward countdown card
                        if let active = rewardsVM.activeRedemption {
                            RedeemedRewardsCountdownCard(activeRedemption: active) {
                                // Trigger refund if we have the reward ID or code
                                if !active.rewardId.isEmpty {
                                    Task { @MainActor in
                                        await rewardsVM.refundExpiredReward(rewardId: active.rewardId)
                                    }
                                } else {
                                    Task { @MainActor in
                                        await rewardsVM.refundExpiredReward(redemptionCode: active.redemptionCode)
                                    }
                                }
                                rewardsVM.activeRedemption = nil
                                showExpiredScreen = true
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .contentShape(RoundedRectangle(cornerRadius: 22))
                            .onTapGesture { showRedeemedCard = true }
                        }
                        
                        // Gifted Rewards section (at top, before everything else)
                        if !rewardsVM.giftedRewards.isEmpty {
                            giftedRewardsSection
                        }
                        
                        // Lifetime Points section (moved from home)
                        lifetimePointsSection

                        // Unlocked rewards section (if any)
                        if !unlockedRewards.isEmpty {
                            unlockedRewardsSection
                        }
                        
                        // Almost there section (if any)
                        if !almostThereRewards.isEmpty {
                            almostThereSection
                        }

                        // Category filter
                        modernCategoryFilter
                        
                        // All rewards grid
                        rewardsGridView
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            rewardsVM.loadUserPoints(from: userVM)
            if let uid = Auth.auth().currentUser?.uid {
                rewardsVM.startGiftedRewardsListener(userId: uid)
            }
        }
        .alert("Points Refunded", isPresented: $rewardsVM.showRefundNotification) {
            Button("OK") {
                rewardsVM.showRefundNotification = false
            }
        } message: {
            Text(rewardsVM.refundNotificationMessage)
        }
        .onChange(of: userVM.points) { _, new in
            rewardsVM.updatePoints(new)
            // Animate points change
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                pointsScale = 1.2
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                pointsScale = 1.0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openRewardsHistory"))) { _ in
            showPointsHistory = true
        }
        .fullScreenCover(isPresented: $showExpiredScreen) {
            RewardExpiredScreen {
                showExpiredScreen = false
            }
        }
        .sheet(isPresented: $showPointsHistory) {
            PointsHistoryView()
        }
        .sheet(isPresented: $showReferral) {
            ReferralView(initialCode: nil)
                .environmentObject(userVM)
        }
        .sheet(isPresented: $showRedeemedCard) {
            if let success = rewardsVM.lastSuccessData {
                RewardCardScreen(
                    userName: userVM.firstName.isEmpty ? "Your" : userVM.firstName,
                    successData: success,
                    onDismiss: { showRedeemedCard = false }
                )
            } else {
                // Fallback: shouldn't normally happen, but avoid presenting a blank sheet
                VStack(spacing: 12) {
                    Text("Active Reward")
                        .font(.headline)
                    Text("No reward details available.")
                        .foregroundColor(.secondary)
                    Button("Close") { showRedeemedCard = false }
                }
                .padding()
            }
        }
    }

    // MARK: - Premium Hero Header
    private var premiumHeaderView: some View {
        VStack(spacing: 24) {
            // Top navigation bar
            HStack {
                if mode == .modal {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.darkGoldGradient)
                            .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                    }
                } else {
                    Spacer().frame(width: 32)
                }

                Spacer()

                // Refer button (left of History)
                Button(action: { showReferral = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16, weight: .black))
                        Text("REFER A FRIEND")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(LinearGradient(gradient: Gradient(colors: [Theme.energyBlue, Theme.energyBlue.opacity(0.85)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 8)

                Button(action: { showPointsHistory = true }) {
                    HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .black))
                        Text("HISTORY")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                        .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Theme.darkGoldGradient)
                            .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Hero points display with mascot (optimized)
            ZStack {
                // Simplified glass morphism container
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: Theme.goldShadow, radius: 12, x: 0, y: 6)
                
                HStack(spacing: 24) {
                    // Animated mascot (no glow, no sparkles)
                    Image("dumpaward")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .shadow(color: Theme.goldShadow, radius: 12, x: 0, y: 6)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR POINTS")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.gray.opacity(0.8))
                            .tracking(1.5)
                            .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 1)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(rewardsVM.userPoints)")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.darkGoldGradient)
                                .lineLimit(1)
                                .minimumScaleFactor(0.3)
                                .scaleEffect(pointsScale)
                                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: pointsScale)
                                .shadow(color: .white.opacity(0.3), radius: 3, x: 0, y: 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Theme.energyOrange)
                                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                                
                                Text("pts")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.gray.opacity(0.7))
                                    .shadow(color: .white.opacity(0.5), radius: 2, x: 0, y: 1)
                            }
                        }
                        
                        // Quick stats
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "gift.fill")
                                    .font(.system(size: 12))
                                Text("\(unlockedRewards.count) ready")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(Theme.energyGreen)
                            .shadow(color: .white.opacity(0.4), radius: 2, x: 0, y: 1)
                            
                            if !almostThereRewards.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 12))
                                    Text("\(almostThereRewards.count) close")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(Theme.energyOrange)
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, rewardsVM.activeRedemption != nil ? 16 : 0)
        }
    }
    
    // Removed compact header for performance

    // MARK: - Gifted Rewards Section
    private var giftedRewardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.5))
                
                Text("YOU HAVE A GIFT!")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(rewardsVM.giftedRewards.count)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.3, blue: 0.5))
                    )
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(rewardsVM.giftedRewards, id: \.id) { gift in
                        GiftedRewardCard(gift: gift)
                            .frame(width: 320)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Lifetime Points Section
    private var lifetimePointsSection: some View {
        HStack {
            Text("LIFETIME POINTS")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Theme.darkGoldGradient)
            
            // Lifetime tier badge pill
            Text(lifetimeTier)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(lifetimeGradient))
            
            Spacer()
            
            Text("\(userVM.lifetimePoints)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.darkGoldGradient)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var lifetimeTier: String {
        switch userVM.lifetimePoints {
        case 0..<1000: return "BRONZE"
        case 1000..<5000: return "SILVER"
        case 5000..<15000: return "GOLD"
        default: return "PLATINUM"
        }
    }

    private var lifetimeGradient: LinearGradient {
        switch lifetimeTier {
        case "BRONZE": return LinearGradient(colors: [Color(red: 0.75, green: 0.5, blue: 0.25), Color(red: 0.85, green: 0.6, blue: 0.35)], startPoint: .leading, endPoint: .trailing)
        case "SILVER": return LinearGradient(colors: [Color(red: 0.7, green: 0.7, blue: 0.7), Color(red: 0.85, green: 0.85, blue: 0.9)], startPoint: .leading, endPoint: .trailing)
        case "GOLD": return Theme.darkGoldGradient
        default: return LinearGradient(colors: [Color(red: 0.85, green: 0.85, blue: 1.0), Color(red: 0.75, green: 0.75, blue: 0.95)], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Unlocked Rewards Section
    private var unlockedRewardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Theme.energyGreen)
                
                Text("READY TO REDEEM!")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(unlockedRewards.count)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.energyGreen)
                    )
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(unlockedRewards, id: \.title) { reward in
                        CompactRewardCard(
                            reward: reward,
                            currentPoints: rewardsVM.userPoints,
                            isUnlocked: true
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Almost There Section
    private var almostThereSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(Theme.energyOrange)
                
                Text("ALMOST THERE!")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .tracking(0.5)
                
                Spacer()
                
                Text("80%+")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.energyOrange)
                    )
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(almostThereRewards, id: \.title) { reward in
                        CompactRewardCard(
                            reward: reward,
                            currentPoints: rewardsVM.userPoints,
                            isUnlocked: false
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Modern Category Filter
    private var modernCategoryFilter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(Theme.primaryGold)
                
                Text("ALL REWARDS")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .tracking(0.5)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(rewardsVM.availableCategories, id: \.self) { category in
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                rewardsVM.selectedCategory = category
                            }
                        }) {
                            HStack(spacing: 8) {
                                // Category icon
                                Text(categoryIcon(for: category))
                                    .font(.system(size: 18))
                                
                        Text(category)
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .tracking(0.3)
                            }
                            .foregroundColor(rewardsVM.selectedCategory == category ? .white : Theme.modernSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                ZStack {
                                    if rewardsVM.selectedCategory == category {
                                        Capsule()
                                            .fill(Theme.darkGoldGradient)
                                            .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                                    } else {
                                        Capsule()
                                            .fill(Theme.modernCard)
                                            .overlay(
                                                Capsule()
                                                    .stroke(Theme.modernSecondary.opacity(0.3), lineWidth: 1.5)
                                            )
                                    }
                                }
                            )
                        }
                        .scaleEffect(rewardsVM.selectedCategory == category ? 1.05 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: rewardsVM.selectedCategory)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }
    
    // Helper for category icons
    private func categoryIcon(for category: String) -> String {
        switch category {
        case "All": return "🎁"
        case "Drinks": return "🥤"
        case "Food": return "🥟"
        case "Combos": return "🍱"
        default: return "⭐"
        }
    }

    // MARK: - Rewards Grid (optimized)
    private var rewardsGridView: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredRewards, id: \.title) { reward in
                DiagonalRewardCard(
                    title: reward.title,
                    description: reward.description,
                    pointsRequired: reward.pointsRequired,
                    currentPoints: rewardsVM.userPoints,
                    color: reward.color,
                    icon: reward.icon,
                    category: reward.category,
                    imageName: reward.imageName,
                    eligibleCategoryId: reward.eligibleCategoryId,
                    rewardTierId: reward.rewardTierId
                )
            }
        }
        .padding()
    }

    // MARK: - Helpers
    // Removed presentPointsHistory() function as it's no longer needed
}

// MARK: - Compact Reward Card (Optimized for horizontal scrolling)
struct CompactRewardCard: View {
    let reward: RewardOption
    let currentPoints: Int
    let isUnlocked: Bool
    
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @State private var showDetailView = false
    @State private var isPressed = false
    
    var progress: Double {
        min(Double(currentPoints) / Double(reward.pointsRequired), 1.0)
    }
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                showDetailView = true
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and title
                HStack(alignment: .top, spacing: 12) {
                    if let imageName = reward.imageName {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        Text(reward.icon)
                            .font(.system(size: 28))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reward.title)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        HStack(spacing: 4) {
                            Text("\(reward.pointsRequired)")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                            Text("pts")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Theme.darkGoldGradient)
                    }
                }
                
                // Simplified progress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isUnlocked ? Theme.energyGreen : Theme.energyOrange)
                        .frame(width: 148 * progress, height: 6)
                }
                .frame(height: 6)
                
                // Status badge
                HStack {
                    if isUnlocked {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("READY!")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .tracking(0.3)
                        }
                        .foregroundColor(Theme.energyGreen)
                    } else {
                        Text("\(Int(progress * 100))% there")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(Theme.energyOrange)
                    }
                    
                    Spacer()
                }
            }
            .padding(16)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.modernCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                    )
                    .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .sheet(isPresented: $showDetailView) {
            RewardDetailView(reward: reward, currentPoints: currentPoints)
                .environmentObject(userVM)
                .environmentObject(rewardsVM)
                .environmentObject(MenuViewModel())
        }
    }
}

// MARK: - Preview
struct UnifiedRewardsScreen_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedRewardsScreen(mode: .tabRoot)
            .environmentObject(UserViewModel())
            .environmentObject(RewardsViewModel())
            .preferredColorScheme(.dark)
    }
} 
