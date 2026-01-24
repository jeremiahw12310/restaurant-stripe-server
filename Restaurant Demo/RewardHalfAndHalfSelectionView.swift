import SwiftUI

// MARK: - Reward Half and Half Selection View
/// Displays dumpling items and allows user to select two flavors + cooking method
struct RewardHalfAndHalfSelectionView: View {
    let reward: RewardOption
    let currentPoints: Int
    let onSelectionComplete: (RewardEligibleItem?, RewardEligibleItem?, String?) -> Void
    let onCancel: () -> Void
    
    @StateObject private var redemptionService = RewardRedemptionService()
    @State private var eligibleItems: [RewardEligibleItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFlavor1: RewardEligibleItem?
    @State private var selectedFlavor2: RewardEligibleItem?
    @State private var cookingMethod: String = "Steamed"
    @State private var appearAnimation = false
    
    private let cookingMethods = ["Boiled", "Steamed", "Pan-fried"]
    
    private var availableDumplings: [RewardEligibleItem] {
        eligibleItems
    }
    
    private var isValid: Bool {
        selectedFlavor1 != nil && 
        selectedFlavor2 != nil && 
        selectedFlavor1?.itemId != selectedFlavor2?.itemId
    }
    
    var body: some View {
        ZStack {
            // Background with dark base and subtle reward color accent
            RewardSelectionBackground(rewardColor: reward.color)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Show loading state while items are loading
                    if isLoading {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if !availableDumplings.isEmpty {
                        // First Flavor Selection
                        flavorSelectionSection(
                            title: "First Flavor",
                            selectedItem: selectedFlavor1,
                            disabledItemId: selectedFlavor2?.itemId,
                            onSelect: { item in
                                selectedFlavor1 = item
                            }
                        )
                        
                        // Second Flavor Selection
                        flavorSelectionSection(
                            title: "Second Flavor",
                            selectedItem: selectedFlavor2,
                            disabledItemId: selectedFlavor1?.itemId,
                            onSelect: { item in
                                selectedFlavor2 = item
                            }
                        )
                        
                        // Cooking Method Selection
                        cookingMethodSection
                    } else {
                        emptyStateView
                    }
                    
                    // Continue Button (only show when items are loaded and valid selections)
                    if !isLoading {
                        continueButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
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
                
                Text("Half and Half")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.top, 16)
            
            Text("Choose 2 different dumpling flavors")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .offset(y: appearAnimation ? 0 : -20)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Flavor Selection Section
    private func flavorSelectionSection(
        title: String,
        selectedItem: RewardEligibleItem?,
        disabledItemId: String?,
        onSelect: @escaping (RewardEligibleItem) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(availableDumplings) { dumpling in
                    RewardFlavorSelectionCard(
                        item: dumpling,
                        isSelected: selectedItem?.itemId == dumpling.itemId,
                        isDisabled: dumpling.itemId == disabledItemId
                    ) {
                        onSelect(dumpling)
                    }
                }
            }
        }
        .offset(y: appearAnimation ? 0 : 30)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Cooking Method Section
    private var cookingMethodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cooking Method")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Picker("Cooking Method", selection: $cookingMethod) {
                ForEach(cookingMethods, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .offset(y: appearAnimation ? 0 : 30)
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
        .padding(.vertical, 40)
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
        .padding(.vertical, 40)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("🥟")
                .font(.system(size: 60))
            
            Text("No dumplings available")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            if let tierId = reward.rewardTierId {
                Text("This reward tier may not be configured with items. Please contact support.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            } else {
                Text("No dumplings found. Please contact support if this is unexpected.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Load Eligible Items
    private func loadEligibleItems() async {
        isLoading = true
        errorMessage = nil
        
        let tierId = reward.rewardTierId ?? "none"
        let tierInfo = "Reward: '\(reward.title)', TierId: '\(tierId)', Points: \(reward.pointsRequired)"
        print("🥟 Loading eligible dumplings for half-and-half - \(tierInfo)")
        
        let result = await redemptionService.fetchEligibleItems(
            pointsRequired: reward.pointsRequired,
            tierId: reward.rewardTierId
        )
        
        await MainActor.run {
            switch result {
            case .success(let items):
                eligibleItems = items
                print("✅ Loaded \(items.count) dumpling items for half-and-half - \(tierInfo)")
                
                if eligibleItems.isEmpty {
                    print("⚠️ Warning: Backend returned empty items array for tier. This tier may not be configured in Firestore 'rewardTierItems' collection.")
                }
                
                isLoading = false
            case .failure(let error):
                print("❌ Failed to load dumplings for half-and-half - \(tierInfo): \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    // MARK: - Continue Button
    private var continueButton: some View {
        VStack(spacing: 12) {
            // Selection summary
            if isValid {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Selected: \(selectedFlavor1?.itemName ?? "") + \(selectedFlavor2?.itemName ?? "")")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text("Cooking: \(cookingMethod)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                )
            }
            
            // Continue button
            Button(action: {
                if isValid {
                    onSelectionComplete(selectedFlavor1, selectedFlavor2, cookingMethod)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text(isValid ? "Continue" : "Select 2 Different Flavors")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(isValid ? Color(red: 0.15, green: 0.1, blue: 0.0) : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            isValid ?
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.9, blue: 0.5),
                                    Color(red: 1.0, green: 0.75, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(
                    color: isValid ? Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .disabled(!isValid)
        }
        .padding(.top, 20)
        .offset(y: appearAnimation ? 0 : 40)
        .opacity(appearAnimation ? 1 : 0)
    }
}

// MARK: - Reward Flavor Selection Card
struct RewardFlavorSelectionCard: View {
    let item: RewardEligibleItem
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(item.itemName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isDisabled ? .white.opacity(0.4) : .white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
                
                if let categoryId = item.categoryId, !categoryId.isEmpty {
                    Text(categoryId)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(isDisabled ? .white.opacity(0.3) : .white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                }
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                }
            }
            .frame(minHeight: 116)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected ? Color.white.opacity(0.25) :
                        isDisabled ? Color.black.opacity(0.1) :
                        Color.black.opacity(0.2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color(red: 1.0, green: 0.85, blue: 0.4) :
                                isDisabled ? Color.white.opacity(0.1) :
                                Color.white.opacity(0.2),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .disabled(isDisabled)
        .buttonStyle(PlainButtonStyle())
    }
}
