import SwiftUI

// MARK: - Reward Topping Selection View
/// Displays toppings from the toppings category and allows user to select one
struct RewardToppingSelectionView: View {
    let reward: RewardOption
    let drinkName: String
    let currentPoints: Int
    let onToppingSelected: (RewardEligibleItem?) -> Void
    let onCancel: () -> Void
    
    @EnvironmentObject var menuVM: MenuViewModel
    @State private var selectedTopping: RewardEligibleItem?
    @State private var appearAnimation = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private var availableToppings: [RewardEligibleItem] {
        guard let toppingsCategory = menuVM.toppingsCategory else {
            return []
        }
        
        // Convert MenuItems from toppings category to RewardEligibleItems
        let items = toppingsCategory.items ?? []
        return items.map { item in
            RewardEligibleItem(
                itemId: item.id,
                itemName: item.id, // Use id as name for toppings
                categoryId: toppingsCategory.id,
                imageURL: item.imageURL
            )
        }
    }
    
    var body: some View {
        ZStack {
            // Background with dark base and subtle reward color accent
            RewardSelectionBackground(rewardColor: reward.color)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                if availableToppings.isEmpty {
                    emptyStateView
                } else {
                    toppingSelectionGrid
                }
                
                // Footer with buttons
                footerSection
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appearAnimation = true
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
                
                Text("Choose Your Topping")
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
                Text(drinkName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Select one topping")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 8)
        }
        .offset(y: appearAnimation ? 0 : -20)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("🧋")
                .font(.system(size: 60))
            
            Text("No toppings available")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text("You can continue without a topping")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Topping Selection Grid
    private var toppingSelectionGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(availableToppings) { topping in
                    ItemSelectionCard(
                        item: topping,
                        isSelected: selectedTopping?.itemId == topping.itemId,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedTopping?.itemId == topping.itemId {
                                    selectedTopping = nil
                                } else {
                                    selectedTopping = topping
                                }
                            }
                        },
                        showImage: false // Toppings should not show images
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
            // Selected topping indicator
            if let selected = selectedTopping {
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
                // Skip button (optional topping)
                Button(action: {
                    onToppingSelected(nil)
                }) {
                    Text("Skip Topping")
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
                Button(action: {
                    onToppingSelected(selectedTopping)
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
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .offset(y: appearAnimation ? 0 : 40)
        .opacity(appearAnimation ? 1 : 0)
    }
}
