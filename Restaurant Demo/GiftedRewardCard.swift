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
                                    .frame(width: 80, height: 80)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 80, height: 80)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if let imageName = gift.imageName, !imageName.isEmpty {
                        // Local asset image
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        // Default gift icon
                        Image(systemName: "gift.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 80, height: 80)
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
    @StateObject private var redemptionService = RewardRedemptionService()
    
    @State private var showItemSelection = false
    @State private var showToppingSelection = false
    @State private var showDumplingSelection = false
    @State private var showHalfAndHalfSelection = false
    @State private var showCookingMethodSelection = false
    @State private var showDrinkTypeSelection = false
    @State private var showComboDrinkCategorySelection = false
    @State private var showComboDrinkItemSelection = false
    @State private var showSuccessScreen = false
    @State private var redemptionSuccessData: RedemptionSuccessData?
    
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
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
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
                        // Check if reward needs item selection
                        // For now, claim directly - we can add selection logic later if needed
                        Task {
                            await claimGift()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Claim Gift")
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
    }
    
    private func claimGift() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No user ID available for claiming gift")
            return
        }
        
        let request = GiftRewardClaimRequest(
            giftedRewardId: gift.id,
            selectedItemId: selectedItem?.itemId,
            selectedItemName: selectedItem?.itemName,
            selectedToppingId: selectedTopping?.itemId,
            selectedToppingName: selectedTopping?.itemName,
            selectedItemId2: selectedFlavor2?.itemId,
            selectedItemName2: selectedFlavor2?.itemName,
            cookingMethod: cookingMethod,
            drinkType: selectedDrinkType,
            selectedDrinkItemId: comboDrinkItem?.itemId,
            selectedDrinkItemName: comboDrinkItem?.itemName
        )
        
        do {
            let url = URL(string: "\(Config.backendURL)/rewards/claim-gift")!
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
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let claimResponse = try JSONDecoder().decode(GiftRewardClaimResponse.self, from: data)
                
                // Build display name
                var displayName = claimResponse.rewardTitle
                if let itemName = claimResponse.selectedItemName {
                    displayName = itemName
                    if let toppingName = claimResponse.selectedToppingName {
                        displayName += " with \(toppingName)"
                    }
                }
                
                // Create success data
                redemptionSuccessData = RedemptionSuccessData(
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
                
                // Store active redemption
                rewardsVM.activeRedemption = ActiveRedemption(
                    rewardTitle: displayName,
                    redemptionCode: claimResponse.redemptionCode,
                    expiresAt: claimResponse.expiresAt
                )
                rewardsVM.lastSuccessData = redemptionSuccessData
                
                // Refresh gifted rewards list
                await rewardsVM.loadGiftedRewards()
                
                // Show success screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showSuccessScreen = true
                }
                
                print("✅ Gift claimed successfully!")
            } else {
                let errorData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Unknown error occurred"
                print("❌ Claim failed: \(errorMessage)")
            }
        } catch {
            print("❌ Error claiming gift: \(error.localizedDescription)")
        }
    }
}
