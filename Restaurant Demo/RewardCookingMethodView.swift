import SwiftUI

// MARK: - Reward Cooking Method Selection View
/// Allows user to select cooking method for a single dumpling selection
struct RewardCookingMethodView: View {
    let reward: RewardOption
    let selectedDumpling: RewardEligibleItem
    let currentPoints: Int
    let onCookingMethodSelected: (RewardEligibleItem, String) -> Void
    let onCancel: () -> Void
    
    @State private var cookingMethod: String = "Steamed"
    @State private var appearAnimation = false
    
    private let cookingMethods = ["Boiled", "Steamed", "Pan-fried"]
    
    var body: some View {
        ZStack {
            // Background with dark base and subtle reward color accent
            RewardSelectionBackground(rewardColor: reward.color)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Selected dumpling display
                        selectedDumplingSection
                        
                        // Cooking method selection
                        cookingMethodSection
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
                
                Text("Choose Cooking Method")
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
    
    // MARK: - Selected Dumpling Section
    private var selectedDumplingSection: some View {
        VStack(spacing: 12) {
            Text("Selected Dumpling")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDumpling.itemName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    if let categoryId = selectedDumpling.categoryId {
                        Text(categoryId)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .offset(y: appearAnimation ? 0 : 30)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Cooking Method Section
    private var cookingMethodSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            
            // Description for each method
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cookingMethods, id: \.self) { method in
                    if cookingMethod == method {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(methodDescription(for: method))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 8)
        }
        .offset(y: appearAnimation ? 0 : 30)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    private func methodDescription(for method: String) -> String {
        switch method {
        case "Boiled":
            return "Soft and tender, cooked in boiling water"
        case "Steamed":
            return "Light and fluffy, cooked with steam"
        case "Pan-fried":
            return "Crispy bottom, pan-seared to perfection"
        default:
            return ""
        }
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 12) {
            // Selection summary
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(selectedDumpling.itemName) - \(cookingMethod)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.3))
            )
            
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
                
                // Confirm button
                Button(action: {
                    onCookingMethodSelected(selectedDumpling, cookingMethod)
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
