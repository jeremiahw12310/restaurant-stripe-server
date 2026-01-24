import SwiftUI

// MARK: - Reward Drink Category Selection View
/// Allows user to select a drink category (Fruit Tea, Milk Tea, Lemonade, Soda) for Full Combo
struct RewardDrinkCategorySelectionView: View {
    let reward: RewardOption
    let currentPoints: Int
    let onCategorySelected: (String) -> Void
    let onCancel: () -> Void
    
    @State private var selectedCategory: String?
    @State private var appearAnimation = false
    
    private let drinkCategories = [
        ("Fruit Tea", "🍑", Color(red: 1.0, green: 0.5, blue: 0.5)),
        ("Milk Tea", "🧋", Color(red: 0.6, green: 0.4, blue: 0.2)),
        ("Lemonade", "🍋", Color(red: 1.0, green: 0.9, blue: 0.0)),
        ("Soda", "🥤", Color(red: 0.0, green: 0.7, blue: 1.0))
    ]
    
    var body: some View {
        ZStack {
            // Background with dark base and subtle reward color accent
            RewardSelectionBackground(rewardColor: reward.color)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(drinkCategories, id: \.0) { category in
                            categoryCard(category: category.0, icon: category.1, color: category.2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
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
                
                Text("Choose Drink Category")
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
    
    // MARK: - Category Card
    private func categoryCard(category: String, icon: String, color: Color) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedCategory = category
            }
        }) {
            HStack(spacing: 16) {
                // Icon
                Text(icon)
                    .font(.system(size: 40))
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(color.opacity(0.2))
                    )
                
                // Category name
                Text(category)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Selection indicator
                if selectedCategory == category {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(color)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedCategory == category ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                selectedCategory == category ? color : Color.white.opacity(0.15),
                                lineWidth: selectedCategory == category ? 2 : 1
                            )
                    )
            )
            .shadow(
                color: selectedCategory == category ? color.opacity(0.3) : Color.clear,
                radius: 8,
                x: 0,
                y: 4
            )
            .scaleEffect(selectedCategory == category ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .offset(y: appearAnimation ? 0 : 30)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 12) {
            // Selection summary
            if let selected = selectedCategory {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Selected: \(selected)")
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
                    if let category = selectedCategory {
                        onCategorySelected(category)
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
                .disabled(selectedCategory == nil)
                .opacity(selectedCategory == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .offset(y: appearAnimation ? 0 : 40)
        .opacity(appearAnimation ? 1 : 0)
    }
}
