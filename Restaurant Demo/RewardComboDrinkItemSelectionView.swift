import SwiftUI

// MARK: - Reward Combo Drink Item Selection View
/// Displays drink items from a specific category for Full Combo selection
struct RewardComboDrinkItemSelectionView: View {
    let reward: RewardOption
    let drinkCategory: String // "Fruit Tea", "Milk Tea", "Lemonade", "Soda", "Coffee"
    let currentPoints: Int
    let onItemSelected: (RewardEligibleItem) -> Void
    let onCancel: () -> Void
    
    @StateObject private var redemptionService = RewardRedemptionService()
    @State private var eligibleItems: [RewardEligibleItem] = []
    @State private var selectedItem: RewardEligibleItem?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var appearAnimation = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            // Background with dark base and subtle reward color accent
            RewardSelectionBackground(rewardColor: reward.color)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if eligibleItems.isEmpty {
                    emptyStateView
                } else {
                    itemSelectionGrid
                }
                
                // Footer with buttons
                footerSection
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appearAnimation = true
            }
            Task {
                await loadItemsFromTier()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.2)))
                }
                
                Spacer()
                
                Text("Choose Your Drink")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Reward info
            VStack(spacing: 6) {
                Text(reward.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("\(drinkCategory) - \(reward.pointsRequired) Points")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 8)
        }
        .offset(y: appearAnimation ? 0 : -20)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
            Text("Loading drinks...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
            Text("Unable to load drinks")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task { await loadItemsFromTier() }
            }) {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("🧋")
                .font(.system(size: 60))
            
            Text("No drinks available")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text("No items found in \(drinkCategory)")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Item Selection Grid
    private var itemSelectionGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(eligibleItems) { item in
                    ItemSelectionCard(
                        item: item,
                        isSelected: selectedItem?.itemId == item.itemId,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedItem?.itemId == item.itemId {
                                    selectedItem = nil
                                } else {
                                    selectedItem = item
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .offset(y: appearAnimation ? 0 : 30)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 12) {
            // Selection summary
            if let selected = selectedItem {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Selected: \(selected.itemName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                )
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                
                // Continue button
                Button(action: {
                    if let item = selectedItem {
                        onItemSelected(item)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                        Text("Continue")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
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
                    )
                    .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(selectedItem == nil)
                .opacity(selectedItem == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .offset(y: appearAnimation ? 0 : 40)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Tier ID Mapping
    private func tierIdForCategory(_ category: String) -> String? {
        switch category {
        case "Fruit Tea": return "tier_drinks_fruit_tea_450"
        case "Milk Tea": return "tier_drinks_milk_tea_450"
        case "Lemonade": return "tier_drinks_lemonade_450"
        case "Soda": return "tier_drinks_lemonade_450" // Same tier as Lemonade
        case "Coffee": return "tier_drinks_coffee_450"
        default: return nil
        }
    }
    
    // MARK: - Load Items
    private func loadItemsFromTier() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        guard let tierId = tierIdForCategory(drinkCategory) else {
            await MainActor.run {
                errorMessage = "Invalid drink category: \(drinkCategory)"
                eligibleItems = []
                isLoading = false
            }
            return
        }
        
        let tierInfo = "Category: '\(drinkCategory)', TierId: '\(tierId)'"
        DebugLogger.debug("🧋 Loading drink items for Full Combo - \(tierInfo)", category: "Rewards")
        
        let result = await redemptionService.fetchEligibleItems(
            pointsRequired: 450, // All drink tiers use 450 points
            tierId: tierId
        )
        
        await MainActor.run {
            switch result {
            case .success(let items):
                eligibleItems = items
                DebugLogger.debug("✅ Loaded \(items.count) drink items for Full Combo - \(tierInfo)", category: "Rewards")
                
                if eligibleItems.isEmpty {
                    DebugLogger.debug("⚠️ Warning: Backend returned empty items array for tier. This tier may not be configured in Firestore 'rewardTierItems' collection.", category: "Rewards")
                }
                
                isLoading = false
            case .failure(let error):
                DebugLogger.debug("❌ Failed to load drink items for Full Combo - \(tierInfo): \(error.localizedDescription)", category: "Rewards")
                errorMessage = error.localizedDescription
                eligibleItems = []
                isLoading = false
            }
        }
    }
}
