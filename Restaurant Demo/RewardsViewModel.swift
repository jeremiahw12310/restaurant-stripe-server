import SwiftUI
import FirebaseAuth
import Firebase

// MARK: - Active Redemption Model
struct ActiveRedemption: Identifiable, Equatable {
    /// Stable id for ForEach; use redemptionCode since it's unique per reward.
    var id: String { redemptionCode }
    let rewardId: String
    let rewardTitle: String
    let redemptionCode: String
    let expiresAt: Date
}

class RewardsViewModel: ObservableObject {
    init() {
        loadPersistedActiveReward()
        // Attach auth state listener once to automatically monitor active redemptions
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            if let user = user {
                self.startActiveRedemptionListener(userId: user.uid)
                self.startGiftedRewardsListener(userId: user.uid)
            } else {
                self.stopActiveRedemptionListener()
                self.stopGiftedRewardsListener()
                self.activeRedemptions = []
                self.lastSuccessData = nil
                self.successDataByCode = [:]
                self.giftedRewards = []
            }
        }
    }

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        stopActiveRedemptionListener()
        stopGiftedRewardsListener()
    }
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var activeListener: ListenerRegistration?
    private let storageKey = "persistedActiveReward"
    private let storageKeySuccessDataList = "persistedActiveRewardSuccessDataList"
    @Published var selectedCategory = "All"
    @Published var showConfetti = false
    @Published var userPoints: Int = 0
    @Published var isLoading = false
    /// All active (unused, non-expired) redemptions; multiple countdowns shown when > 1.
    @Published var activeRedemptions: [ActiveRedemption] = []
    @Published var lastSuccessData: RedemptionSuccessData? {
        didSet {
            persistActiveReward()
        }
    }
    /// Success data keyed by redemptionCode for showing RewardCardScreen when user taps a countdown card.
    @Published var successDataByCode: [String: RedemptionSuccessData] = [:]
    /// When set, Rewards tab presents the QR screen immediately (root-level presentation).
    @Published var pendingQRSuccess: RedemptionSuccessData?
    @Published var rewardJustUsed = false
    @Published var giftedRewards: [GiftedReward] = []
    @Published var showRefundNotification = false
    @Published var refundNotificationMessage: String = ""
    
    private var giftedRewardsListener: ListenerRegistration?
    private let categories = ["All", "Food", "Drinks", "Condiments", "Special"]

    // MARK: - Centralized Active Redemption Updates
    /// Record a successful redemption locally (upsert by redemptionCode) and persist it for continuity.
    /// The Firestore listener will reconcile `rewardId` once it sees the new document.
    @MainActor
    func recordRedemptionSuccess(_ success: RedemptionSuccessData, displayTitle: String, rewardId: String? = nil) {
        let code = success.redemptionCode

        // Upsert by code to avoid temporary duplicates.
        activeRedemptions.removeAll { $0.redemptionCode == code }
        let ar = ActiveRedemption(
            rewardId: rewardId ?? "",
            rewardTitle: displayTitle,
            redemptionCode: code,
            expiresAt: success.expiresAt
        )
        activeRedemptions.insert(ar, at: 0)

        successDataByCode[code] = success
        lastSuccessData = success
        persistActiveReward()
    }
    
    // MARK: - Lunch Special Availability Check
    private func isLunchSpecialAvailable() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentDay = calendar.component(.weekday, from: now) // 1=Sunday, 2=Monday, ..., 7=Saturday
        
        // Check if it's Monday-Friday (weekday 2-6)
        let isWeekday = currentDay >= 2 && currentDay <= 6
        
        // Check if it's between 11 AM and 4 PM (hours 11-15)
        let isLunchHours = currentHour >= 11 && currentHour < 16
        
        return isWeekday && isLunchHours
    }
    
    // MARK: - Reward Options - Updated to match exact pricing structure
    var rewardOptions: [RewardOption] {
        let allRewards = [
            // 250 pts tier
            RewardOption(title: "Free Peanut Sauce", description: "Any dipping sauce selection", pointsRequired: 250, color: .orange, icon: "🥫", category: "Condiments", imageName: "peanut", rewardTierId: "tier_sauce_250"),
            
            // 450 pts tier
            RewardOption(title: "Fruit Tea", description: "Fruit Tea with up to one free Topping option included", pointsRequired: 450, color: .blue, icon: "🧋", category: "Drinks", imageName: "fruittea", eligibleCategoryId: "Fruit Tea", rewardTierId: "tier_drinks_fruit_tea_450"),
            RewardOption(title: "Milk Tea", description: "Milk Tea with up to one free Topping option included", pointsRequired: 450, color: .blue, icon: "🧋", category: "Drinks", imageName: "milktea", eligibleCategoryId: "Milk Tea", rewardTierId: "tier_drinks_milk_tea_450"),
            RewardOption(title: "Lemonade or Soda", description: "Lemonade or Soda with up to one free Topping option included", pointsRequired: 450, color: .blue, icon: "🧋", category: "Drinks", imageName: "lemonade", rewardTierId: "tier_drinks_lemonade_450"),
            RewardOption(title: "Coffee", description: "Coffee with up to one free Topping option included", pointsRequired: 450, color: .blue, icon: "🧋", category: "Drinks", imageName: "milktea", eligibleCategoryId: "Coffee", rewardTierId: "tier_drinks_coffee_450"),
            
            // 500 pts tier
            RewardOption(title: "Small Appetizer", description: "Edamame, Tofu, or Rice", pointsRequired: 500, color: .green, icon: "🥜", category: "Food", imageName: "asianpic", rewardTierId: "tier_small_appetizer_500"),
            
            // 650 pts tier
            RewardOption(title: "Larger Appetizer", description: "Dumplings or Curry Rice", pointsRequired: 650, color: .purple, icon: "🥟", category: "Food", imageName: "peanutpo", rewardTierId: "tier_large_appetizer_650"),
            
            // 850 pts tier
            RewardOption(title: "Pizza Dumplings (6)", description: "6 Piece Pizza Dumplings", pointsRequired: 850, color: .pink, icon: "🥟", category: "Food", imageName: "pizza", rewardTierId: "tier_pizza_dumplings_850"),
            
            // 1,000 pts tier
            RewardOption(title: "6-Piece Lunch Special Dumplings", description: "6-Piece Lunch Special", pointsRequired: 850, color: .indigo, icon: "🍱", category: "Food", imageName: "porkshrimp", eligibleCategoryId: "Dumplings", rewardTierId: "tier_lunch_special_850"),
            
            // 1,500 pts tier
            RewardOption(title: "12-Piece Dumplings", description: "12-Piece Dumplings", pointsRequired: 1500, color: .brown, icon: "🥟", category: "Food", imageName: "porkshrimp", rewardTierId: "tier_12piece_1500"),
            
            // 2,000 pts tier
            RewardOption(title: "Full Combo", description: "Dumplings + Drink", pointsRequired: 2000, color: Color(red: 1.0, green: 0.84, blue: 0.0), icon: "🎉", category: "Special", rewardTierId: "tier_full_combo_2000")
        ]
        
        // Filter out lunch special if not available
        return allRewards.filter { reward in
            if reward.title == "6-Piece Lunch Special Dumplings" {
                return isLunchSpecialAvailable()
            }
            return true
        }
    }
    
    var availableCategories: [String] {
        return categories
    }
    
    // MARK: - Filtered Rewards
    var filteredRewards: [RewardOption] {
        if selectedCategory == "All" {
            return rewardOptions
        } else {
            return rewardOptions.filter { $0.category == selectedCategory }
        }
    }
    
    // MARK: - Available Rewards
    var availableRewards: [RewardOption] {
        filteredRewards.filter { $0.pointsRequired <= userPoints }
    }
    
    // MARK: - Unavailable Rewards
    var unavailableRewards: [RewardOption] {
        filteredRewards.filter { $0.pointsRequired > userPoints }
    }
    
    // MARK: - Firestore Listener for Active Redemption
    func startActiveRedemptionListener(userId: String) {
        // Avoid duplicate listeners
        activeListener?.remove()
        let db = Firestore.firestore()
        activeListener = db.collection("redeemedRewards")
            .whereField("userId", isEqualTo: userId)
            .whereField("isUsed", isEqualTo: false)
            .whereField("isExpired", isEqualTo: false)
            .order(by: "redeemedAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Active redemption listener error: \(error.localizedDescription)")
                    return
                }
                let docs = snapshot?.documents ?? []
                let hadActive = !self.activeRedemptions.isEmpty
                var active: [ActiveRedemption] = []
                var successByCode: [String: RedemptionSuccessData] = self.successDataByCode
                let now = Date()
                Task { @MainActor in
                    var seenCodes = Set<String>()
                    for doc in docs {
                        guard let reward = RedeemedReward(document: doc) else { continue }
                        if reward.expiresAt <= now {
                            await self.refundExpiredReward(rewardId: doc.documentID)
                            try? await doc.reference.updateData(["isExpired": true])
                            successByCode.removeValue(forKey: reward.redemptionCode)
                            continue
                        }
                        // Defensive: never surface duplicates for the same code.
                        guard !seenCodes.contains(reward.redemptionCode) else { continue }
                        seenCodes.insert(reward.redemptionCode)
                        let ar = ActiveRedemption(
                            rewardId: reward.id,
                            rewardTitle: reward.rewardTitle,
                            redemptionCode: reward.redemptionCode,
                            expiresAt: reward.expiresAt
                        )
                        active.append(ar)
                        let sd = RedemptionSuccessData(
                            redemptionCode: reward.redemptionCode,
                            rewardTitle: reward.rewardTitle,
                            rewardDescription: reward.rewardDescription,
                            newPointsBalance: self.userPoints,
                            pointsDeducted: reward.pointsRequired,
                            expiresAt: reward.expiresAt,
                            rewardColorHex: nil,
                            rewardIcon: nil,
                            selectedItemName: reward.selectedItemName
                        )
                        successByCode[reward.redemptionCode] = sd
                    }
                    self.activeRedemptions = active
                    self.successDataByCode = successByCode
                    if active.isEmpty && hadActive {
                        self.rewardJustUsed = true
                    }
                    if let first = active.first {
                        self.lastSuccessData = successByCode[first.redemptionCode]
                    } else {
                        self.lastSuccessData = nil
                    }
                    self.persistActiveReward()
                }
            }
    }

    func stopActiveRedemptionListener() {
        activeListener?.remove()
        activeListener = nil
    }

    // MARK: - Methods
    func loadUserPoints(from userVM: UserViewModel) {
        userPoints = userVM.points
    }
    
    func updatePoints(_ newPoints: Int) {
        userPoints = newPoints
    }
    
    // MARK: - Persistence
    private func persistActiveReward() {
        guard !activeRedemptions.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: storageKeySuccessDataList)
            return
        }
        if let first = activeRedemptions.first, let data = successDataByCode[first.redemptionCode] {
            if let encoded = try? JSONEncoder().encode(data) {
                UserDefaults.standard.set(encoded, forKey: storageKey)
            }
        }
        let list = activeRedemptions.compactMap { successDataByCode[$0.redemptionCode] }
        if !list.isEmpty, let encoded = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(encoded, forKey: storageKeySuccessDataList)
        }
    }
    
    private func loadPersistedActiveReward() {
        guard let saved = UserDefaults.standard.data(forKey: storageKeySuccessDataList),
              let list = try? JSONDecoder().decode([RedemptionSuccessData].self, from: saved) else {
            if let saved = UserDefaults.standard.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode(RedemptionSuccessData.self, from: saved),
               decoded.expiresAt > Date() {
                lastSuccessData = decoded
                activeRedemptions = [
                    ActiveRedemption(rewardId: "", rewardTitle: decoded.rewardTitle, redemptionCode: decoded.redemptionCode, expiresAt: decoded.expiresAt)
                ]
                successDataByCode = [decoded.redemptionCode: decoded]
            }
            return
        }
        let now = Date()
        var active: [ActiveRedemption] = []
        var byCode: [String: RedemptionSuccessData] = [:]
        for data in list where data.expiresAt > now {
            let ar = ActiveRedemption(rewardId: "", rewardTitle: data.rewardTitle, redemptionCode: data.redemptionCode, expiresAt: data.expiresAt)
            active.append(ar)
            byCode[data.redemptionCode] = data
        }
        if !active.isEmpty {
            activeRedemptions = active
            successDataByCode = byCode
            lastSuccessData = active.first.flatMap { byCode[$0.redemptionCode] }
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.removeObject(forKey: storageKeySuccessDataList)
        }
    }

    func triggerConfetti() {
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showConfetti = false
        }
    }
    
    // MARK: - Gifted Rewards
    
    func startGiftedRewardsListener(userId: String) {
        // Stop any existing listener
        stopGiftedRewardsListener()
        
        // Load gifted rewards from API (not Firestore directly, as we need server-side filtering)
        Task {
            await loadGiftedRewards()
        }
    }
    
    func stopGiftedRewardsListener() {
        giftedRewardsListener?.remove()
        giftedRewardsListener = nil
    }
    
    @MainActor
    func loadGiftedRewards() async {
        guard let user = Auth.auth().currentUser else {
            giftedRewards = []
            return
        }
        
        do {
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            let url = URL(string: "\(Config.backendURL)/me/gifted-rewards")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "RewardsViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Failed to load gifted rewards"
                print("❌ Error loading gifted rewards: \(errorMessage)")
                return
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let giftsArray = json?["gifts"] as? [[String: Any]] ?? []
            
            // Parse gifts
            let decoder = JSONDecoder()
            var parsedGifts: [GiftedReward] = []
            
            for giftDict in giftsArray {
                // Convert to JSON data for decoding
                if let giftData = try? JSONSerialization.data(withJSONObject: giftDict),
                   let gift = try? decoder.decode(GiftedReward.self, from: giftData) {
                    parsedGifts.append(gift)
                }
            }
            
            self.giftedRewards = parsedGifts
            print("✅ Loaded \(parsedGifts.count) gifted rewards")
            
        } catch {
            print("❌ Error loading gifted rewards: \(error.localizedDescription)")
            self.giftedRewards = []
        }
    }
    
    /// Call when a countdown card's timer hits zero: refund that reward and remove it from active list.
    func handleActiveRedemptionExpired(_ active: ActiveRedemption) {
        Task { @MainActor in
            if !active.rewardId.isEmpty {
                await refundExpiredReward(rewardId: active.rewardId)
            } else {
                await refundExpiredReward(redemptionCode: active.redemptionCode)
            }
            activeRedemptions.removeAll { $0.redemptionCode == active.redemptionCode }
            successDataByCode.removeValue(forKey: active.redemptionCode)
            if let first = activeRedemptions.first {
                lastSuccessData = successDataByCode[first.redemptionCode]
            } else {
                lastSuccessData = nil
            }
            persistActiveReward()
        }
    }

    // MARK: - Refund Expired Reward

    @MainActor
    func refundExpiredReward(rewardId: String? = nil, redemptionCode: String? = nil) async {
        guard let user = Auth.auth().currentUser else {
            print("❌ No authenticated user for refund")
            return
        }
        
        guard rewardId != nil || redemptionCode != nil else {
            print("❌ Must provide either rewardId or redemptionCode")
            return
        }
        
        do {
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            let url = URL(string: "\(Config.backendURL)/refund-expired-reward")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            var requestBody: [String: Any] = [:]
            if let rewardId = rewardId {
                requestBody["rewardId"] = rewardId
            }
            if let redemptionCode = redemptionCode {
                requestBody["redemptionCode"] = redemptionCode
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            if let rewardId = rewardId {
                print("💰 Requesting refund for expired reward ID: \(rewardId)")
            } else if let code = redemptionCode {
                print("💰 Requesting refund for expired reward code: \(code)")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "RewardsViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if httpResponse.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let pointsRefunded = json?["pointsRefunded"] as? Int ?? 0
                let newPointsBalance = json?["newPointsBalance"] as? Int ?? userPoints
                let alreadyRefunded = json?["alreadyRefunded"] as? Bool ?? false
                
                if alreadyRefunded {
                    print("✅ Points already refunded for this reward")
                    return
                }
                
                // Update local points balance
                userPoints = newPointsBalance
                
                // Show notification
                refundNotificationMessage = "\(pointsRefunded) points refunded - reward expired"
                showRefundNotification = true
                
                // Hide notification after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.showRefundNotification = false
                }
                
                print("✅ Refund successful: \(pointsRefunded) points refunded, new balance: \(newPointsBalance)")
            } else {
                let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Failed to refund reward"
                print("❌ Error refunding reward: \(errorMessage)")
                
                // Still show a notification even if refund failed (might have been refunded server-side)
                refundNotificationMessage = "Reward expired - checking refund status"
                showRefundNotification = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.showRefundNotification = false
                }
            }
            
        } catch {
            print("❌ Error refunding expired reward: \(error.localizedDescription)")
            
            // Show notification about expiration
            refundNotificationMessage = "Reward expired"
            showRefundNotification = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.showRefundNotification = false
            }
        }
    }
} 
