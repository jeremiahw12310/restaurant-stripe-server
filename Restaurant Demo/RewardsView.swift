import SwiftUI
import FirebaseAuth

/// Wraps RedemptionSuccessData for sheet(item:) when showing reward detail from countdown tap.
private struct RewardsViewIdentifiableSuccess: Identifiable {
    let id: String
    let data: RedemptionSuccessData
    init(_ d: RedemptionSuccessData) { id = d.redemptionCode; data = d }
}

struct RewardsView: View {
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var showExpiredScreen = false
    @State private var sheetSuccessData: RewardsViewIdentifiableSuccess?
    
    // Points history sheet
    @State private var showPointsHistory = false
    
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
                // Background gradient - same as DetailedRewardsView
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
                    // Header with points display - same as DetailedRewardsView
                    VStack(spacing: 20) {
                        HStack {
                            // Empty space for left side
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
                            
                            // Points History Button
                            Button(action: { showPointsHistory = true }) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.1))
                                    )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Points display - same as DetailedRewardsView
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
                                            Color(red: 0.8, green: 0.6, blue: 0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .padding(.horizontal)

                    // Redeemed countdown card(s) if active
                    ForEach(rewardsVM.activeRedemptions) { active in
                        RedeemedRewardsCountdownCard(activeRedemption: active) {
                            rewardsVM.handleActiveRedemptionExpired(active)
                            showExpiredScreen = true
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                        .onTapGesture {
                            if let sd = rewardsVM.successDataByCode[active.redemptionCode] {
                                sheetSuccessData = RewardsViewIdentifiableSuccess(sd)
                            }
                        }
                    }
                }
                .padding(.top)
                .alert("Points Refunded", isPresented: $rewardsVM.showRefundNotification) {
                    Button("OK") {
                        rewardsVM.showRefundNotification = false
                    }
                } message: {
                    Text(rewardsVM.refundNotificationMessage)
                }
                
                // Category filter - same as DetailedRewardsView
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
                                                  Color(red: 0.8, green: 0.6, blue: 0.2) : 
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
                
                // Rewards grid - same as DetailedRewardsView
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
                                imageName: reward.imageName,
                                eligibleCategoryId: reward.eligibleCategoryId,
                                rewardTierId: reward.rewardTierId
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
            // Ensure user points and active redemption listener are in sync when Rewards tab opens
            rewardsVM.loadUserPoints(from: userVM)
        }
        .onChange(of: userVM.points) { _, newPoints in
            rewardsVM.updatePoints(newPoints)
        }
        .fullScreenCover(isPresented: $showExpiredScreen) {
            RewardExpiredScreen {
                showExpiredScreen = false
            }
        }
        .sheet(isPresented: $showPointsHistory) {
            PointsHistoryView()
        }
        .sheet(item: $sheetSuccessData) { wrapper in
            RewardCardScreen(
                userName: userVM.firstName.isEmpty ? "Your" : userVM.firstName,
                successData: wrapper.data,
                onDismiss: { sheetSuccessData = nil }
            )
        }
    }
} 
