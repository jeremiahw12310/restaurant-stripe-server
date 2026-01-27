import SwiftUI

// MARK: - Reward Item Selection View
/// Displays eligible menu items for a reward tier and allows user to select one
struct RewardItemSelectionView: View {
    let reward: RewardOption
    let currentPoints: Int
    let onItemSelected: (RewardEligibleItem?) -> Void
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
                await loadEligibleItems()
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
                
                Text("Choose Your Item")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Spacer for balance
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Reward info
            VStack(spacing: 6) {
                Text(reward.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("\(reward.pointsRequired) Points")
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
            Text("Loading options...")
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
            Text("Unable to load items")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task { await loadEligibleItems() }
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
            
            Text(reward.icon)
                .font(.system(size: 60))
            
            if let tierId = reward.rewardTierId {
                Text("No items configured for this reward tier")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text("This reward tier may need to be configured with items. You can skip and proceed with the generic reward.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Text("No specific items configured")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text("You'll receive a \(reward.title)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
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
            // Selected item indicator
            if let selected = selectedItem {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Selected: \(selected.itemName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                )
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Skip button (use generic reward)
                Button(action: {
                    onItemSelected(nil)
                }) {
                    Text(eligibleItems.isEmpty ? "Continue" : "Skip Selection")
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
                
                // Confirm button
                if selectedItem != nil {
                    Button(action: {
                        onItemSelected(selectedItem)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text("Confirm")
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
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .offset(y: appearAnimation ? 0 : 40)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Load Eligible Items
    private func loadEligibleItems() async {
        isLoading = true
        errorMessage = nil
        
        let tierId = reward.rewardTierId ?? "none"
        let tierInfo = "Reward: '\(reward.title)', TierId: '\(tierId)', Points: \(reward.pointsRequired)"
        DebugLogger.debug("🎁 Loading eligible items - \(tierInfo)", category: "Rewards")
        
        let result = await redemptionService.fetchEligibleItems(
            pointsRequired: reward.pointsRequired,
            tierId: reward.rewardTierId
        )
        
        await MainActor.run {
            switch result {
            case .success(let items):
                let originalCount = items.count
                eligibleItems = filteredItemsForReward(items)
                let filteredCount = eligibleItems.count
                
                DebugLogger.debug("✅ Loaded items - \(tierInfo): \(originalCount) items from backend, \(filteredCount) items after filtering", category: "Rewards")
                
                if eligibleItems.isEmpty && originalCount > 0 {
                    DebugLogger.debug("⚠️ Warning: All items were filtered out. Category filter: '\(reward.eligibleCategoryId ?? "none")'", category: "Rewards")
                } else if eligibleItems.isEmpty {
                    DebugLogger.debug("⚠️ Warning: Backend returned empty items array for tier. This tier may not be configured in Firestore 'rewardTierItems' collection.", category: "Rewards")
                }
                
                isLoading = false
            case .failure(let error):
                DebugLogger.debug("❌ Failed to load items - \(tierInfo): \(error.localizedDescription)", category: "Rewards")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func filteredItemsForReward(_ items: [RewardEligibleItem]) -> [RewardEligibleItem] {
        guard let categoryFilter = reward.eligibleCategoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !categoryFilter.isEmpty else {
            // No category filter - return all items as-is
            DebugLogger.debug("📋 No category filter applied, showing all \(items.count) items from backend", category: "Rewards")
            return items
        }
        
        // Filter by category
        let filtered = items.filter { item in
            guard let categoryId = item.categoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !categoryId.isEmpty else {
                return false
            }
            return categoryId.caseInsensitiveCompare(categoryFilter) == .orderedSame
        }
        
        DebugLogger.debug("📋 Filtered \(items.count) items to \(filtered.count) items matching category '\(categoryFilter)'", category: "Rewards")
        return filtered
    }
}

// MARK: - Item Selection Card
struct ItemSelectionCard: View {
    let item: RewardEligibleItem
    let isSelected: Bool
    let onSelect: () -> Void
    let showImage: Bool // Whether to show images (false for toppings)
    
    init(item: RewardEligibleItem, isSelected: Bool, onSelect: @escaping () -> Void, showImage: Bool = true) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.showImage = showImage
    }
    
    private var hasImage: Bool {
        if !showImage {
            return false // Force text-only if showImage is false
        }
        if let imageURL = item.imageURL {
            return !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
    
    var body: some View {
        Button(action: onSelect) {
            Group {
                if hasImage {
                    imageCardContent
                } else {
                    textOnlyCardContent
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.25) : Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color.white.opacity(0.2),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
            .shadow(
                color: isSelected ? Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3) : Color.clear,
                radius: 8,
                x: 0,
                y: 4
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var imageCardContent: some View {
        VStack(spacing: 10) {
            // Image placeholder or async image
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 80)
                
                if let imageURL = item.imageURL {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 70)
                        case .failure:
                            itemPlaceholder
                        @unknown default:
                            itemPlaceholder
                        }
                    }
                } else {
                    itemPlaceholder
                }
            }
            
            // Item name
            Text(item.itemName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 36)
        }
    }
    
    private var textOnlyCardContent: some View {
        VStack(spacing: 8) {
            Text(item.itemName)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
            
            if let categoryId = item.categoryId, !categoryId.isEmpty {
                Text(categoryId)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    )
            }
        }
        .frame(minHeight: 116)
    }
    
    private var itemPlaceholder: some View {
        Image(systemName: "takeoutbag.and.cup.and.straw")
            .font(.system(size: 32))
            .foregroundColor(.white.opacity(0.5))
    }
}

// MARK: - Preview
struct RewardItemSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        RewardItemSelectionView(
            reward: RewardOption(
                title: "Fruit Tea",
                description: "Any fruit tea with one topping",
                pointsRequired: 450,
                color: .blue,
                icon: "🧋",
                category: "Drinks"
            ),
            currentPoints: 500,
            onItemSelected: { _ in },
            onCancel: {}
        )
    }
}
