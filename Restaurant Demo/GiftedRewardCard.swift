import SwiftUI
import FirebaseAuth

// MARK: - Gifted Reward Card Component
struct GiftedRewardCard: View {
    let gift: GiftedReward
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @State private var showDetailView = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                showDetailView = true
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with GIFT badge
                HStack {
                    // GIFT badge
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("GIFT")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(1.0)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.3, blue: 0.5), Color(red: 1.0, green: 0.5, blue: 0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.3, blue: 0.5).opacity(0.4), radius: 4, x: 0, y: 2)
                    
                    Spacer()
                    
                    // FREE badge
                    Text("FREE")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.2, green: 0.8, blue: 0.4))
                        )
                }
                
                // Image or icon
                HStack(spacing: 12) {
                    if let imageURL = gift.imageURL, !imageURL.isEmpty {
                        // Custom image from URL
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 100, height: 100)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 100, height: 100)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if let imageName = gift.imageName, !imageName.isEmpty {
                        // Local asset image
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        // Default gift icon
                        Image(systemName: "gift.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 100, height: 100)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gift.rewardTitle)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text(gift.rewardDescription)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                }
                
                // Claim button
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("CLAIM NOW")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.9, blue: 0.5), Color(red: 1.0, green: 0.75, blue: 0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.4), radius: 6, x: 0, y: 3)
                    )
                    Spacer()
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.7, blue: 0.3),
                                Color(red: 1.0, green: 0.85, blue: 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color(red: 0.9, green: 0.7, blue: 0.3).opacity(0.4), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isPressed)
        .sheet(isPresented: $showDetailView) {
            GiftedRewardDetailView(gift: gift)
                .environmentObject(userVM)
                .environmentObject(rewardsVM)
        }
    }
}

// MARK: - Gifted Reward Detail View
struct GiftedRewardDetailView: View {
    let gift: GiftedReward
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @EnvironmentObject var menuVM: MenuViewModel
    @StateObject private var redemptionService = RewardRedemptionService()
    
    @State private var showItemSelection = false
    @State private var showToppingSelection = false
    @State private var showDumplingSelection = false
    @State private var showHalfAndHalfSelection = false
    @State private var showCookingMethodSelection = false
    @State private var showDrinkTypeSelection = false
    @State private var showComboDrinkCategorySelection = false
    @State private var showComboDrinkItemSelection = false
    @State private var isClaiming = false
    
    @State private var selectedItem: RewardEligibleItem?
    @State private var selectedTopping: RewardEligibleItem?
    @State private var selectedFlavor1: RewardEligibleItem?
    @State private var selectedFlavor2: RewardEligibleItem?
    @State private var selectedSingleDumpling: RewardEligibleItem?
    @State private var cookingMethod: String?
    @State private var selectedDrinkType: String?
    @State private var selectedComboDrinkCategory: String?
    @State private var comboDumplingItem: RewardEligibleItem?
    @State private var comboDrinkItem: RewardEligibleItem?
    @State private var comboCookingMethod: String?
    @State private var showIceSugarSelection = false
    @State private var selectedIceLevel: String = "Normal"
    @State private var selectedSugarLevel: String = "Normal"
    
    // Helper computed properties to detect reward type
    private var requiresTopping: Bool {
        let title = gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title == "Milk Tea" || title == "Fruit Tea" || title == "Lemonade or Soda" || title == "Coffee"
    }
    
    private var requiresDrinkTypeSelection: Bool {
        gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines) == "Lemonade or Soda"
    }
    
    private var requiresDumplingSelection: Bool {
        gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines) == "12-Piece Dumplings"
    }
    
    private var requiresCookingMethodSelection: Bool {
        let title = gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title == "6-Piece Lunch Special Dumplings" || title == "Pizza Dumplings (6)"
    }
    
    private var isFullComboReward: Bool {
        gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines) == "Full Combo"
    }
    
    private var requiresIceSugarSelection: Bool {
        let title = gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title == "Milk Tea" || title == "Fruit Tea" || title == "Coffee" || title == "Lemonade or Soda"
    }
    
    // Create a RewardOption from GiftedReward for selection views
    private var rewardOption: RewardOption {
        // Try to find matching reward by title to get correct tier info
        let matchingReward = rewardsVM.rewardOptions.first { 
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == 
            gift.rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return RewardOption(
            title: gift.rewardTitle,
            description: gift.rewardDescription,
            pointsRequired: gift.pointsRequired,
            color: matchingReward?.color ?? Color(red: 0.9, green: 0.7, blue: 0.3),
            icon: matchingReward?.icon ?? "🎁",
            category: gift.rewardCategory,
            imageName: matchingReward?.imageName ?? gift.imageName,
            eligibleCategoryId: matchingReward?.eligibleCategoryId,
            rewardTierId: matchingReward?.rewardTierId
        )
    }
    
    /// For Full Combo, dumpling selection uses the 12-piece tier (same as earned flow). Otherwise use rewardOption.
    private var dumplingRewardOption: RewardOption {
        if isFullComboReward {
            return RewardOption(
                title: gift.rewardTitle,
                description: gift.rewardDescription,
                pointsRequired: 1500,
                color: rewardOption.color,
                icon: rewardOption.icon,
                category: gift.rewardCategory,
                imageName: rewardOption.imageName,
                eligibleCategoryId: rewardOption.eligibleCategoryId,
                rewardTierId: "tier_12piece_1500"
            )
        }
        return rewardOption
    }
    
    // Determine button text based on reward type
    private var claimButtonText: String {
        if gift.isCustom {
            return "Claim Gift"
        } else if isFullComboReward {
            return "Select Your Combo"
        } else if requiresDumplingSelection {
            return "Select Your Dumplings"
        } else if requiresTopping {
            return "Select Your Item"
        } else {
            return "Claim Gift"
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.9, green: 0.7, blue: 0.3),
                    Color(red: 1.0, green: 0.85, blue: 0.45),
                    Color.black.opacity(0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
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
                    
                    // Image
                    VStack(spacing: 16) {
                        if let imageURL = gift.imageURL, !imageURL.isEmpty {
                            AsyncImage(url: URL(string: imageURL)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 150, height: 150)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 150, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 24))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 24)
                                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.6))
                                        .frame(width: 150, height: 150)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else if let imageName = gift.imageName, !imageName.isEmpty {
                            Image(imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 150, height: 150)
                                .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                        } else {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 150, height: 150)
                        }
                        
                        // GIFT badge
                        HStack(spacing: 6) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("FREE GIFT")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .tracking(1.0)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.3, blue: 0.5), Color(red: 1.0, green: 0.5, blue: 0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: Color(red: 1.0, green: 0.3, blue: 0.5).opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    
                    // Title & Description
                    VStack(spacing: 12) {
                        Text(gift.rewardTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text(gift.rewardDescription)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 32)
                    
                    // Claim button
                    Button(action: {
                        if gift.isCustom {
                            // Custom rewards: claim directly
                            Task {
                                await claimGift()
                            }
                        } else {
                            // Regular rewards: start selection flow
                            startSelectionFlow()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: gift.isCustom ? "gift.fill" : "hand.tap.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text(claimButtonText)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
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
                                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.4), radius: 12, x: 0, y: 6)
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showItemSelection) {
            RewardItemSelectionView(
                reward: rewardOption,
                currentPoints: rewardsVM.userPoints,
                onItemSelected: { item in
                    selectedItem = item
                    showItemSelection = false
                    
                    if item == nil {
                        // User skipped selection, proceed with generic reward
                        Task {
                            await claimGift()
                        }
                        return
                    }
                    
                    // Chain to next selection based on reward type
                    if requiresDrinkTypeSelection, let drinkItem = item {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showDrinkTypeSelection = true
                        }
                    } else if requiresIceSugarSelection, let drinkItem = item {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showIceSugarSelection = true
                        }
                    } else if requiresCookingMethodSelection, let dumplingItem = item {
                        selectedSingleDumpling = dumplingItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCookingMethodSelection = true
                        }
                    } else {
                        // Proceed with redemption
                        Task {
                            await claimGift()
                        }
                    }
                },
                onCancel: {
                    showItemSelection = false
                }
            )
        }
        .sheet(isPresented: $showToppingSelection) {
            RewardToppingSelectionView(
                reward: rewardOption,
                drinkName: (isFullComboReward ? comboDrinkItem : selectedItem)?.itemName ?? gift.rewardTitle,
                currentPoints: rewardsVM.userPoints,
                onToppingSelected: { topping in
                    selectedTopping = topping
                    showToppingSelection = false
                    
                    if isFullComboReward {
                        // Full Combo: Redeem with all selections
                        if let flavor1 = selectedFlavor1, let flavor2 = selectedFlavor2 {
                            // Half-and-half Full Combo
                            Task {
                                await claimGift()
                            }
                        } else {
                            // Single dumpling Full Combo
                            Task {
                                await claimGift()
                            }
                        }
                    } else {
                        // Regular drink reward
                        Task {
                            await claimGift()
                        }
                    }
                },
                onCancel: {
                    showToppingSelection = false
                }
            )
        }
        .sheet(isPresented: $showDumplingSelection) {
            RewardDumplingSelectionView(
                reward: dumplingRewardOption,
                currentPoints: rewardsVM.userPoints,
                onSingleDumplingSelected: { dumpling in
                    selectedFlavor1 = dumpling
                    if isFullComboReward {
                        comboDumplingItem = dumpling
                    }
                    showDumplingSelection = false
                    
                    if isFullComboReward {
                        // Full Combo: show cooking method first, then drink category (same as earned flow)
                        selectedSingleDumpling = dumpling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCookingMethodSelection = true
                        }
                    } else if requiresCookingMethodSelection {
                        // 6-piece dumplings: show cooking method
                        selectedSingleDumpling = dumpling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCookingMethodSelection = true
                        }
                    } else {
                        // 12-piece: proceed to half-and-half option or claim
                        Task {
                            await claimGift()
                        }
                    }
                },
                onHalfAndHalfSelected: {
                    showDumplingSelection = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showHalfAndHalfSelection = true
                    }
                },
                onCancel: {
                    showDumplingSelection = false
                }
            )
        }
        .sheet(isPresented: $showHalfAndHalfSelection) {
            RewardHalfAndHalfSelectionView(
                reward: dumplingRewardOption,
                currentPoints: rewardsVM.userPoints,
                onSelectionComplete: { flavor1, flavor2, cookingMethod in
                    selectedFlavor1 = flavor1
                    selectedFlavor2 = flavor2
                    if let method = cookingMethod {
                        self.cookingMethod = method
                        if isFullComboReward {
                            comboCookingMethod = method
                        }
                    }
                    showHalfAndHalfSelection = false
                    
                    if isFullComboReward {
                        // Full Combo: proceed to drink category
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showComboDrinkCategorySelection = true
                        }
                    } else if requiresCookingMethodSelection && cookingMethod == nil {
                        // Show cooking method for half-and-half if not already selected
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCookingMethodSelection = true
                        }
                    } else {
                        // Claim directly
                        Task {
                            await claimGift()
                        }
                    }
                },
                onCancel: {
                    showHalfAndHalfSelection = false
                }
            )
        }
        .sheet(isPresented: $showCookingMethodSelection) {
            if let dumpling = selectedSingleDumpling ?? selectedFlavor1 {
                RewardCookingMethodView(
                    reward: rewardOption,
                    selectedDumpling: dumpling,
                    currentPoints: rewardsVM.userPoints,
                    onCookingMethodSelected: { dumpling, method in
                        cookingMethod = method
                        if isFullComboReward {
                            comboCookingMethod = method
                        }
                        showCookingMethodSelection = false
                        
                        if isFullComboReward {
                            // Full Combo: proceed to drink category
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showComboDrinkCategorySelection = true
                            }
                        } else {
                            // Claim directly
                            Task {
                                await claimGift()
                            }
                        }
                    },
                    onCancel: {
                        showCookingMethodSelection = false
                    }
                )
            }
        }
        .sheet(isPresented: $showDrinkTypeSelection) {
            if let item = selectedItem {
                RewardDrinkTypeSelectionView(
                    reward: rewardOption,
                    selectedItem: item,
                    currentPoints: rewardsVM.userPoints,
                    onDrinkTypeSelected: { item, drinkType in
                        selectedDrinkType = drinkType
                        showDrinkTypeSelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showIceSugarSelection = true
                        }
                    },
                    onCancel: {
                        showDrinkTypeSelection = false
                    }
                )
            }
        }
        .sheet(isPresented: $showIceSugarSelection) {
            RewardIceSugarSelectionView(
                reward: rewardOption,
                drinkName: selectedItem?.itemName ?? gift.rewardTitle,
                currentPoints: rewardsVM.userPoints,
                onSelectionComplete: { ice, sugar in
                    selectedIceLevel = ice
                    selectedSugarLevel = sugar
                    showIceSugarSelection = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showToppingSelection = true
                    }
                },
                onCancel: {
                    showIceSugarSelection = false
                }
            )
        }
        .sheet(isPresented: $showComboDrinkCategorySelection) {
            RewardDrinkCategorySelectionView(
                reward: rewardOption,
                currentPoints: rewardsVM.userPoints,
                onCategorySelected: { category in
                    selectedComboDrinkCategory = category
                    showComboDrinkCategorySelection = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showComboDrinkItemSelection = true
                    }
                },
                onCancel: {
                    showComboDrinkCategorySelection = false
                }
            )
        }
        .sheet(isPresented: $showComboDrinkItemSelection) {
            RewardComboDrinkItemSelectionView(
                reward: rewardOption,
                drinkCategory: selectedComboDrinkCategory ?? "",
                currentPoints: rewardsVM.userPoints,
                onItemSelected: { drinkItem in
                    comboDrinkItem = drinkItem
                    showComboDrinkItemSelection = false
                    
                    let category = selectedComboDrinkCategory ?? ""
                    if isFullComboReward {
                        // Full Combo: branch on selected drink category (same as earned flow)
                        if category == "Lemonade" || category == "Soda" {
                            selectedItem = drinkItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showDrinkTypeSelection = true
                            }
                        } else if category == "Milk Tea" || category == "Fruit Tea" || category == "Coffee" {
                            selectedItem = drinkItem
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showIceSugarSelection = true
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showToppingSelection = true
                            }
                        }
                    } else if requiresDrinkTypeSelection {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showDrinkTypeSelection = true
                        }
                    } else if requiresIceSugarSelection {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showIceSugarSelection = true
                        }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showToppingSelection = true
                        }
                    }
                },
                onCancel: {
                    showComboDrinkItemSelection = false
                }
            )
        }
    }
    
    // Start the selection flow based on reward type
    private func startSelectionFlow() {
        if isFullComboReward {
            // Full Combo: Start with dumpling selection
            showDumplingSelection = true
        } else if requiresDumplingSelection {
            // 12-Piece Dumplings: Show dumpling selection
            showDumplingSelection = true
        } else if requiresCookingMethodSelection {
            // 6-piece dumplings: Show item selection first
            showItemSelection = true
        } else if requiresTopping || requiresDrinkTypeSelection {
            // Drinks: Show item selection
            showItemSelection = true
        } else {
            // No selection needed, claim directly
            Task {
                await claimGift()
            }
        }
    }
    
    private func claimGift() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            DebugLogger.debug("❌ No user ID available for claiming gift", category: "Rewards")
            return
        }

        let alreadyClaiming = await MainActor.run { isClaiming }
        guard !alreadyClaiming else {
            DebugLogger.debug("⚠️ Claim already in progress; ignoring duplicate request", category: "Rewards")
            return
        }
        await MainActor.run { isClaiming = true }
        defer {
            Task { @MainActor in
                isClaiming = false
            }
        }
        
        // Determine which item to use based on selection flow
        let primaryItem: RewardEligibleItem?
        if isFullComboReward {
            // For Full Combo, use selectedFlavor1 (dumpling) as primary item
            primaryItem = selectedFlavor1 ?? comboDumplingItem
        } else if requiresDumplingSelection {
            // For dumpling rewards, use selectedFlavor1 or selectedSingleDumpling
            primaryItem = selectedFlavor1 ?? selectedSingleDumpling
        } else {
            // For other rewards, use selectedItem
            primaryItem = selectedItem
        }
        
        let request = GiftRewardClaimRequest(
            giftedRewardId: gift.id,
            selectedItemId: primaryItem?.itemId,
            selectedItemName: primaryItem?.itemName,
            selectedToppingId: selectedTopping?.itemId,
            selectedToppingName: selectedTopping?.itemName,
            selectedItemId2: selectedFlavor2?.itemId,
            selectedItemName2: selectedFlavor2?.itemName,
            cookingMethod: comboCookingMethod ?? cookingMethod,
            drinkType: selectedDrinkType,
            selectedDrinkItemId: comboDrinkItem?.itemId,
            selectedDrinkItemName: comboDrinkItem?.itemName,
            iceLevel: selectedIceLevel,
            sugarLevel: selectedSugarLevel
        )
        
        do {
            guard let url = URL(string: "\(Config.backendURL)/rewards/claim-gift") else {
                throw NetworkError.invalidURL
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add auth token
            if let user = Auth.auth().currentUser {
                let token = try await user.getIDTokenResult(forcingRefresh: false).token
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData
            
            let (data, response) = try await URLSession.configured.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let claimResponse = try JSONDecoder().decode(GiftRewardClaimResponse.self, from: data)
                
                // Build display name from response
                var displayName = claimResponse.rewardTitle
                if let itemName = claimResponse.selectedItemName {
                    displayName = itemName
                    if let itemName2 = claimResponse.selectedItemName2 {
                        // Half-and-half
                        displayName = "\(itemName) & \(itemName2)"
                    }
                    if let toppingName = claimResponse.selectedToppingName {
                        displayName += " with \(toppingName)"
                    }
                    if let cookingMethod = claimResponse.cookingMethod {
                        displayName += " (\(cookingMethod))"
                    }
                    if let drinkType = claimResponse.drinkType {
                        displayName += " (\(drinkType))"
                    }
                } else if let drinkItemName = claimResponse.selectedDrinkItemName {
                    // Full Combo drink item
                    displayName = drinkItemName
                    if let toppingName = claimResponse.selectedToppingName {
                        displayName += " with \(toppingName)"
                    }
                }
                
                // Create success data
                let successData = RedemptionSuccessData(
                    redemptionCode: claimResponse.redemptionCode,
                    rewardTitle: claimResponse.rewardTitle,
                    rewardDescription: gift.rewardDescription,
                    newPointsBalance: claimResponse.newPointsBalance,
                    pointsDeducted: claimResponse.pointsDeducted,
                    expiresAt: claimResponse.expiresAt,
                    rewardColorHex: nil,
                    rewardIcon: "🎁",
                    selectedItemName: displayName
                )
                
                // Upsert into active redemptions; Firestore listener will reconcile when it sees the new doc
                rewardsVM.recordRedemptionSuccess(successData, displayTitle: displayName, rewardId: nil)
                
                // Refresh gifts list and present the QR screen from the Rewards root.
                Task { await rewardsVM.loadGiftedRewards() }
                await MainActor.run { dismiss() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    rewardsVM.stagedQRSuccess = successData
                }
                
                DebugLogger.debug("✅ Gift claimed successfully!", category: "Rewards")
            } else {
                let errorData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Unknown error occurred"
                DebugLogger.debug("❌ Claim failed: \(errorMessage)", category: "Rewards")
            }
        } catch {
            DebugLogger.debug("❌ Error claiming gift: \(error.localizedDescription)", category: "Rewards")
        }
    }
}
