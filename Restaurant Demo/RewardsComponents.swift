import SwiftUI
import FirebaseAuth

// MARK: - Circular Progress Ring for Reward Detail
struct RewardProgressRing: View {
    let progress: Double
    let isUnlocked: Bool
    let ringSize: CGFloat
    let lineWidth: CGFloat
    
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.white.opacity(0.2),
                    lineWidth: lineWidth
                )
            
            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    isUnlocked ?
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.3),
                            Color(red: 1.0, green: 0.7, blue: 0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: isUnlocked ? Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5) : Color.white.opacity(0.3), radius: 4, x: 0, y: 0)
        }
        .frame(width: ringSize, height: ringSize)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Frosted Glass Card Modifier
struct FrostedGlassCard: ViewModifier {
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Frosted glass effect
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

extension View {
    func frostedGlassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(FrostedGlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Reward Detail View (Premium Gift Card Style)
struct RewardDetailView: View {
    let reward: RewardOption
    let currentPoints: Int
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @StateObject private var redemptionService = RewardRedemptionService()
    
    @State private var showRedeemAnimation = false
    @State private var showConfetti = false
    @State private var showConfirmationDialog = false
    @State private var showItemSelection = false      // NEW: Item selection sheet
    @State private var selectedItem: RewardEligibleItem?  // NEW: Selected item
    @State private var showSuccessScreen = false
    @State private var redemptionSuccessData: RedemptionSuccessData?
    @State private var appearAnimation = false
    @State private var pulseAnimation = false
    @State private var showFullDescription = false
    
    var progress: Double {
        min(Double(currentPoints) / Double(reward.pointsRequired), 1.0)
    }
    
    var isUnlocked: Bool {
        progress >= 1.0
    }
    
    var pointsNeeded: Int {
        max(reward.pointsRequired - currentPoints, 0)
    }
    
    var body: some View {
        ZStack {
            // MARK: - Rich Gradient Background
            ZStack {
                // Simplified background for broader / more "native" appeal
                LinearGradient(
                    gradient: Gradient(colors: [
                        reward.color,
                        reward.color.opacity(0.85),
                        Color.black.opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle vignette for legibility (keeps attention on the content)
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.45)
                    ],
                    center: .center,
                    startRadius: 180,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()
            
            // MARK: - Main Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Close button
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.2))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // MARK: - Hero Section with Progress Ring
                    ZStack {
                        // Progress ring
                        RewardProgressRing(
                            progress: progress,
                            isUnlocked: isUnlocked,
                            ringSize: 200,
                            lineWidth: 8
                        )
                        
                        // Reward visual
                        VStack(spacing: 0) {
                            if let imageName = reward.imageName {
                                Image(imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 120, height: 120)
                                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                            } else {
                                Text(reward.icon)
                                    .font(.system(size: 72))
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            }
                        }
                        .scaleEffect(appearAnimation ? 1.0 : 0.8)
                        .opacity(appearAnimation ? 1.0 : 0)

                        // Single source of truth for progress (avoid repeating % / points in multiple places)
                        VStack(spacing: 4) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                        }
                        .padding(.top, 150)
                        
                        // Unlock badge
                        if isUnlocked {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.2, green: 0.8, blue: 0.4))
                                            .frame(width: 44, height: 44)
                                            .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.5), radius: 8, x: 0, y: 4)
                                        
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                }
                            }
                            .frame(width: 200, height: 200)
                            .offset(x: 20, y: 20)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    
                    // MARK: - Title & Description
                    VStack(spacing: 12) {
                        Text(reward.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                            .multilineTextAlignment(.center)
                        
                        VStack(spacing: 8) {
                            Text(reward.description)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                .multilineTextAlignment(.center)
                                .lineLimit(showFullDescription ? nil : 3)
                                .padding(.horizontal, 32)

                            // Only show the toggle when it might be helpful (keeps UI non-repetitive / uncluttered)
                            if reward.description.count > 90 {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showFullDescription.toggle()
                                    }
                                }) {
                                    Text(showFullDescription ? "Less" : "More details")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                        .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .offset(y: appearAnimation ? 0 : 20)
                    .opacity(appearAnimation ? 1.0 : 0)
                    
                    // MARK: - Frosted Glass Info Card
                    VStack(spacing: 24) {
                        // Points comparison
                        HStack(spacing: 0) {
                            // Your points
                            VStack(spacing: 6) {
                                Text("\(currentPoints)")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                
                                Text("Your Points")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Divider
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 1, height: 50)
                            
                            // Required points
                            VStack(spacing: 6) {
                                Text("\(reward.pointsRequired)")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                
                                Text("Required")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // One lightweight status line (avoid duplicating the progress shown in the ring)
                        if !isUnlocked {
                            Text("Need \(pointsNeeded) more points to redeem")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(24)
                    .frostedGlassCard(cornerRadius: 24)
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .offset(y: appearAnimation ? 0 : 30)
                    .opacity(appearAnimation ? 1.0 : 0)
                    
                    Spacer(minLength: 32)
                    
                    // MARK: - Redeem Button
                    Button(action: {
                        if isUnlocked {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showRedeemAnimation = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showConfirmationDialog = true
                                showRedeemAnimation = false
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: isUnlocked ? "gift.fill" : "lock.fill")
                                .font(.system(size: 20, weight: .semibold))
                            
                            if isUnlocked {
                                Text("Redeem Now")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            } else {
                                Text("Earn \(pointsNeeded) more points")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                            }
                        }
                        .foregroundColor(isUnlocked ? Color(red: 0.15, green: 0.1, blue: 0.0) : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            ZStack {
                                if isUnlocked {
                                    // Gold gradient for unlocked
                                    RoundedRectangle(cornerRadius: 16)
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
                                    
                                    // Glow effect
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            Color(red: 1.0, green: 0.85, blue: 0.4),
                                            lineWidth: 2
                                        )
                                        .blur(radius: pulseAnimation ? 6 : 3)
                                        .opacity(pulseAnimation ? 0.8 : 0.5)
                                } else {
                                    // Locked state
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                    
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                }
                            }
                        )
                        .shadow(
                            color: isUnlocked ? Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.4) : Color.clear,
                            radius: 16,
                            x: 0,
                            y: 8
                        )
                    }
                    .disabled(!isUnlocked)
                    .scaleEffect(showRedeemAnimation ? 0.95 : 1.0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .offset(y: appearAnimation ? 0 : 40)
                    .opacity(appearAnimation ? 1.0 : 0)
                    
                    // Single helper line (no redundancy with the ring + info card)
                    Text(isUnlocked ? "Code expires in 15 minutes" : "Earn points to unlock this reward")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .whiteTextShadow(opacity: 0.35, radius: 2, x: 0, y: 2)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            // Staggered entrance animation
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.1)) {
                appearAnimation = true
            }
            
            // Pulse animation for unlocked state
            if isUnlocked {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .sheet(isPresented: $showConfirmationDialog) {
            RedemptionConfirmationDialog(
                rewardData: RedemptionConfirmationData(
                    rewardTitle: reward.title,
                    rewardDescription: reward.description,
                    pointsRequired: reward.pointsRequired,
                    currentPoints: currentPoints,
                    rewardCategory: reward.category,
                    color: reward.color.description,
                    icon: reward.icon
                ),
                onConfirm: {
                    // Dismiss confirmation and show item selection
                    showConfirmationDialog = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showItemSelection = true
                    }
                },
                onCancel: {
                    showConfirmationDialog = false
                }
            )
        }
        .sheet(isPresented: $showItemSelection) {
            RewardItemSelectionView(
                reward: reward,
                currentPoints: currentPoints,
                onItemSelected: { item in
                    selectedItem = item
                    showItemSelection = false
                    Task {
                        await redeemReward(selectedItem: item)
                    }
                },
                onCancel: {
                    showItemSelection = false
                }
            )
        }
        .sheet(isPresented: $showSuccessScreen) {
            if let successData = redemptionSuccessData {
                RewardCardScreen(
                    userName: userVM.firstName.isEmpty ? "Your" : userVM.firstName,
                    successData: successData,
                    onDismiss: {
                        showSuccessScreen = false
                        dismiss()
                    }
                )
            }
        }
        .onChange(of: redemptionService.errorMessage) { _, errorMessage in
            if let error = errorMessage {
                print("❌ Redemption error: \(error)")
            }
        }
    }
    
    // MARK: - Redemption Logic
    private func redeemReward(selectedItem: RewardEligibleItem? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No user ID available for redemption")
            return
        }
        
        let result = await redemptionService.redeemReward(
            userId: userId,
            rewardTitle: reward.title,
            rewardDescription: reward.description,
            pointsRequired: reward.pointsRequired,
            rewardCategory: reward.category,
            selectedItemId: selectedItem?.itemId,
            selectedItemName: selectedItem?.itemName
        )
        
        await MainActor.run {
            switch result {
            case .success(let response):
                // Update user points
                userVM.points = response.newPointsBalance
                
                // Create success data with selected item name
                redemptionSuccessData = RedemptionSuccessData(
                    redemptionCode: response.redemptionCode,
                    rewardTitle: response.rewardTitle,
                    rewardDescription: reward.description,
                    newPointsBalance: response.newPointsBalance,
                    pointsDeducted: response.pointsDeducted,
                    expiresAt: response.expiresAt,
                    rewardColorHex: nil,
                    rewardIcon: reward.icon,
                    selectedItemName: response.selectedItemName
                )

                // Store active redemption in shared rewards view-model for countdown card
                // Use selected item name if available for the title
                let displayTitle = response.selectedItemName ?? response.rewardTitle
                rewardsVM.activeRedemption = ActiveRedemption(
                    rewardTitle: displayTitle,
                    redemptionCode: response.redemptionCode,
                    expiresAt: response.expiresAt
                )
                // Persist full success payload so we can reopen the reward card from the countdown later
                rewardsVM.lastSuccessData = redemptionSuccessData
                
                // Present success sheet after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSuccessScreen = true
                }
                
                print("✅ Reward redeemed successfully!")
                print("🔢 Code: \(response.redemptionCode)")
                print("💰 New balance: \(response.newPointsBalance)")
                if let selectedName = response.selectedItemName {
                    print("🍽️ Selected item: \(selectedName)")
                }
                
            case .failure(let error):
                print("❌ Redemption failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Dutch Bros Energy Reward Card (Optimized)
struct DiagonalRewardCard: View {
    let title: String
    let description: String
    let pointsRequired: Int
    let currentPoints: Int
    let color: Color
    let icon: String
    let category: String
    let imageName: String?
    // Compact mode is used for the smaller cards embedded on Home
    let compact: Bool
    
    init(
        title: String,
        description: String,
        pointsRequired: Int,
        currentPoints: Int,
        color: Color,
        icon: String,
        category: String,
        imageName: String?,
        compact: Bool = false
    ) {
        self.title = title
        self.description = description
        self.pointsRequired = pointsRequired
        self.currentPoints = currentPoints
        self.color = color
        self.icon = icon
        self.category = category
        self.imageName = imageName
        self.compact = compact
    }
    
    @State private var isPressed = false
    @State private var showDetailView = false
    
    var progress: Double {
        min(Double(currentPoints) / Double(pointsRequired), 1.0)
    }
    
    var isUnlocked: Bool {
        progress >= 1.0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            // Header with title and points
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: compact ? 18 : 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
                
                Spacer()
                
                // In compact mode (Home), we move the points label down next to the emoji/image
                if !compact {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(pointsRequired)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                        
                        Text("POINTS")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(1.2)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    }
                }
            }
            
            // Visual section (image or icon)
            HStack(spacing: 12) {
                if let imageName = imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: compact ? 72 : 88, height: compact ? 72 : 88)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                } else {
                    Text(icon)
                        .font(.system(size: compact ? 40 : 48, weight: .bold))
                        .foregroundColor(.white)
                }

                // Compact-only points label next to the emoji/image
                if compact {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pointsRequired)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                        Text("POINTS")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .tracking(1.0)
                            .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                    }
                }
                
                Spacer()
            }
            
            // Footer block: full-width progress bar + status/points text
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 12)
                        
                        // Simplified progress fill
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                            .frame(width: geometry.size.width * progress, height: 12)
                    }
                }
                .frame(height: 12)
                
                HStack(spacing: 8) {
                    if isUnlocked {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 13, weight: .bold))
                            
                            Text("READY")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                        
                        Text("\(pointsRequired) pts")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    } else {
                        Text("\(currentPoints)/\(pointsRequired) pts")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    }
                    
                    Spacer()
                    
                    if !isUnlocked {
                        Text("\(Int(progress * 100))% there")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(20)
        .background(
            // Simplified background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.9, green: 0.7, blue: 0.3),
                    Color(red: 1.0, green: 0.85, blue: 0.45)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(color.opacity(0.15))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: Color(red: 0.9, green: 0.7, blue: 0.3).opacity(0.3), radius: 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .onTapGesture {
            isPressed = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                showDetailView = true
            }
        }
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .sheet(isPresented: $showDetailView) {
            RewardDetailView(
                reward: RewardOption(
                    title: title,
                    description: description,
                    pointsRequired: pointsRequired,
                    color: color,
                    icon: icon,
                    category: category,
                    imageName: imageName
                ),
                currentPoints: currentPoints
            )
        }
    }
}

// MARK: - Enhanced Detailed Rewards View
struct DetailedRewardsView: View {
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    private var filteredRewards: [RewardOption] {
        if rewardsVM.selectedCategory == "All" {
            return rewardsVM.rewardOptions
        } else {
            return rewardsVM.rewardOptions.filter { $0.category == rewardsVM.selectedCategory }
        }
    }
    
    var body: some View {
        NavigationView {
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
                    // Header with points display
                    VStack(spacing: 20) {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Image("dumpawarddark")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                
                                Text("Rewards")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            Button(action: {}) {
                                Image(systemName: "questionmark.circle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Points display
                        VStack(spacing: 8) {
                            Text("\(rewardsVM.userPoints)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Total Points")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.3, blue: 0.1),
                                            Color(red: 0.6, green: 0.5, blue: 0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    // Category filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(rewardsVM.availableCategories, id: \.self) { category in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        rewardsVM.selectedCategory = category
                                    }
                                }) {
                                    Text(category)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(rewardsVM.selectedCategory == category ? .white : .white.opacity(0.6))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(rewardsVM.selectedCategory == category ? 
                                                      Color(red: 0.6, green: 0.5, blue: 0.2) : 
                                                      Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                    
                    // Rewards grid
                    ScrollView {
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
                            imageName: reward.imageName
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            rewardsVM.loadUserPoints(from: userVM)
        }
        .onChange(of: userVM.points) { _, newPoints in
            rewardsVM.updatePoints(newPoints)
        }
    }
}

// MARK: - Reward Option Model
struct RewardOption {
    let title: String
    let description: String
    let pointsRequired: Int
    let color: Color
    let icon: String
    let category: String
    let imageName: String?
    let eligibleCategoryId: String?
    let rewardTierId: String?

    init(title: String,
         description: String,
         pointsRequired: Int,
         color: Color,
         icon: String,
         category: String,
         imageName: String? = nil,
         eligibleCategoryId: String? = nil,
         rewardTierId: String? = nil) {
        self.title = title
        self.description = description
        self.pointsRequired = pointsRequired
        self.color = color
        self.icon = icon
        self.category = category
        self.imageName = imageName
        self.eligibleCategoryId = eligibleCategoryId
        self.rewardTierId = rewardTierId
    }
} 