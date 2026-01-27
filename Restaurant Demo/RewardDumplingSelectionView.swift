import SwiftUI

// MARK: - Reward Dumpling Selection View
/// Displays eligible dumplings from tier and allows user to select one OR choose half-and-half
struct RewardDumplingSelectionView: View {
    let reward: RewardOption
    let currentPoints: Int
    let onSingleDumplingSelected: (RewardEligibleItem) -> Void
    let onHalfAndHalfSelected: () -> Void
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
                
                Text("Choose Your Dumplings")
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
            Text("Loading dumplings...")
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
            Text("Unable to load dumplings")
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
            
            Text("🥟")
                .font(.system(size: 60))
            
            if let tierId = reward.rewardTierId {
                Text("No dumplings configured for this reward tier")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text("This reward tier may need to be configured with items. Please contact support.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Text("No specific items configured")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Item Selection Grid
    private var itemSelectionGrid: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
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
            VStack(spacing: 12) {
                // Half & Half button (always visible when items are loaded)
                if !isLoading && !eligibleItems.isEmpty {
                    Button(action: {
                        onHalfAndHalfSelected()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.split.2x2")
                                .font(.system(size: 16, weight: .bold))
                            Text("Half & Half")
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
                
                // Bottom row: Cancel and Confirm buttons
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
                    
                    // Confirm button (only enabled when item is selected)
                    if selectedItem != nil {
                        Button(action: {
                            if let selected = selectedItem {
                                onSingleDumplingSelected(selected)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
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
        DebugLogger.debug("🥟 Loading eligible dumplings - \(tierInfo)", category: "Rewards")
        
        let result = await redemptionService.fetchEligibleItems(
            pointsRequired: reward.pointsRequired,
            tierId: reward.rewardTierId
        )
        
        await MainActor.run {
            switch result {
            case .success(let items):
                eligibleItems = items
                DebugLogger.debug("✅ Loaded \(items.count) dumpling items - \(tierInfo)", category: "Rewards")
                
                if eligibleItems.isEmpty {
                    DebugLogger.debug("⚠️ Warning: Backend returned empty items array for tier. This tier may not be configured in Firestore 'rewardTierItems' collection.", category: "Rewards")
                }
                
                isLoading = false
            case .failure(let error):
                DebugLogger.debug("❌ Failed to load dumplings - \(tierInfo): \(error.localizedDescription)", category: "Rewards")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
