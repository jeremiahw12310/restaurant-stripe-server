import Foundation
import Firebase
import FirebaseAuth

class RewardRedemptionService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let baseURL: String
    
    init() {
        // Use the same configuration as other services
        switch Config.currentEnvironment {
        case .localNetwork:
            self.baseURL = Config.localNetworkBackendURL
        case .production:
            self.baseURL = Config.productionBackendURL
        }
    }
    
    // MARK: - Fetch Eligible Items for Reward Tier
    func fetchEligibleItems(pointsRequired: Int, tierId: String? = nil) async -> Result<[RewardEligibleItem], Error> {
        do {
            let url: URL
            if let tierId, !tierId.isEmpty {
                guard let tierURL = URL(string: "\(baseURL)/reward-tier-items/by-id/\(tierId)") else {
                    return .failure(NetworkError.invalidURL)
                }
                url = tierURL
            } else {
                guard let pointsURL = URL(string: "\(baseURL)/reward-tier-items/\(pointsRequired)") else {
                    return .failure(NetworkError.invalidURL)
                }
                url = pointsURL
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "GET"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let tierId, !tierId.isEmpty {
                DebugLogger.debug("🎁 Fetching eligible items for tier \(tierId)", category: "Rewards")
            } else {
                DebugLogger.debug("🎁 Fetching eligible items for \(pointsRequired) point tier", category: "Rewards")
            }
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            DebugLogger.debug("📥 Response status: \(httpResponse.statusCode)", category: "Rewards")
            
            if httpResponse.statusCode == 200 {
                let tierResponse = try JSONDecoder().decode(RewardTierItemsResponse.self, from: data)
                let itemCount = tierResponse.eligibleItems.count
                
                if let tierId = tierId, !tierId.isEmpty {
                    DebugLogger.debug("✅ Fetched \(itemCount) eligible items for tier \(tierId)", category: "Rewards")
                } else {
                    DebugLogger.debug("✅ Fetched \(itemCount) eligible items for \(pointsRequired) point tier", category: "Rewards")
                }
                
                if itemCount == 0 {
                    if let tierId = tierId, !tierId.isEmpty {
                        DebugLogger.debug("⚠️ WARNING: Tier '\(tierId)' returned 0 items. This tier may not be configured in Firestore 'rewardTierItems' collection.", category: "Rewards")
                    } else {
                        DebugLogger.debug("⚠️ WARNING: \(pointsRequired) point tier returned 0 items. This tier may not be configured in Firestore 'rewardTierItems' collection.", category: "Rewards")
                    }
                }
                
                return .success(tierResponse.eligibleItems)
            } else {
                let errorData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Unknown error occurred"
                
                if let tierId = tierId, !tierId.isEmpty {
                    DebugLogger.debug("❌ Error fetching tier \(tierId): \(errorMessage)", category: "Rewards")
                } else {
                    DebugLogger.debug("❌ Error fetching \(pointsRequired) point tier: \(errorMessage)", category: "Rewards")
                }
                
                throw NetworkError.serverError(errorMessage)
            }
            
        } catch {
            DebugLogger.debug("❌ Error fetching eligible items: \(error.localizedDescription)", category: "Rewards")
            return .failure(error)
        }
    }
    
    // MARK: - Redeem Reward
    func redeemReward(
        userId: String,
        rewardTitle: String,
        rewardDescription: String,
        pointsRequired: Int,
        rewardCategory: String,
        selectedItemId: String? = nil,
        selectedItemName: String? = nil,
        selectedToppingId: String? = nil,
        selectedToppingName: String? = nil,
        selectedItemId2: String? = nil,
        selectedItemName2: String? = nil,
        cookingMethod: String? = nil,
        drinkType: String? = nil,
        selectedDrinkItemId: String? = nil,
        selectedDrinkItemName: String? = nil
    ) async -> Result<RewardRedemptionResponse, Error> {
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            guard let user = Auth.auth().currentUser else {
                throw NetworkError.unauthorized
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            let idempotencyKey = UUID().uuidString
            
            let request = RewardRedemptionRequest(
                userId: userId,
                rewardTitle: rewardTitle,
                rewardDescription: rewardDescription,
                pointsRequired: pointsRequired,
                rewardCategory: rewardCategory,
                idempotencyKey: idempotencyKey,
                selectedItemId: selectedItemId,
                selectedItemName: selectedItemName,
                selectedToppingId: selectedToppingId,
                selectedToppingName: selectedToppingName,
                selectedItemId2: selectedItemId2,
                selectedItemName2: selectedItemName2,
                cookingMethod: cookingMethod,
                drinkType: drinkType,
                selectedDrinkItemId: selectedDrinkItemId,
                selectedDrinkItemName: selectedDrinkItemName
            )
            
            guard let url = URL(string: "\(baseURL)/redeem-reward") else {
                throw NetworkError.invalidURL
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData
            
            DebugLogger.debug("🎁 Redeeming reward: \(rewardTitle) for \(pointsRequired) points", category: "Rewards")
            if let selectedName = selectedItemName {
                DebugLogger.debug("🍽️ Selected item: \(selectedName)", category: "Rewards")
            }
            if let toppingName = selectedToppingName {
                DebugLogger.debug("🧋 Selected topping: \(toppingName)", category: "Rewards")
            }
            if let itemName2 = selectedItemName2 {
                DebugLogger.debug("🥟 Second item: \(itemName2)", category: "Rewards")
            }
            if let method = cookingMethod {
                DebugLogger.debug("🔥 Cooking method: \(method)", category: "Rewards")
            }
            if let type = drinkType {
                DebugLogger.debug("🥤 Drink type: \(type)", category: "Rewards")
            }
            DebugLogger.debug("📡 API URL: \(url)", category: "Rewards")
            DebugLogger.debug("📦 Request data: \(String(data: jsonData, encoding: .utf8) ?? "")", category: "Rewards")
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            DebugLogger.debug("📥 Response status: \(httpResponse.statusCode)", category: "Rewards")
            DebugLogger.debug("📥 Response data: \(String(data: data, encoding: .utf8) ?? "")", category: "Rewards")
            
            if httpResponse.statusCode == 200 {
                let redemptionResponse = try JSONDecoder().decode(RewardRedemptionResponse.self, from: data)
                
                await MainActor.run {
                    isLoading = false
                }
                
                DebugLogger.debug("✅ Reward redeemed successfully!", category: "Rewards")
                DebugLogger.debug("🔢 Redemption code: \(redemptionResponse.redemptionCode)", category: "Rewards")
                DebugLogger.debug("💰 New balance: \(redemptionResponse.newPointsBalance)", category: "Rewards")
                if let selectedName = redemptionResponse.selectedItemName {
                    DebugLogger.debug("🍽️ Selected item: \(selectedName)", category: "Rewards")
                }
                if let toppingName = redemptionResponse.selectedToppingName {
                    DebugLogger.debug("🧋 Selected topping: \(toppingName)", category: "Rewards")
                }
                if let itemName2 = redemptionResponse.selectedItemName2 {
                    DebugLogger.debug("🥟 Second item: \(itemName2)", category: "Rewards")
                }
                if let method = redemptionResponse.cookingMethod {
                    DebugLogger.debug("🔥 Cooking method: \(method)", category: "Rewards")
                }
                if let type = redemptionResponse.drinkType {
                    DebugLogger.debug("🥤 Drink type: \(type)", category: "Rewards")
                }
                
                return .success(redemptionResponse)
                
            } else {
                // Handle error response
                let errorData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Unknown error occurred"
                
                await MainActor.run {
                    isLoading = false
                    self.errorMessage = errorMessage
                }
                
                DebugLogger.debug("❌ Redemption failed: \(errorMessage)", category: "Rewards")
                throw NetworkError.serverError(errorMessage)
            }
            
        } catch {
            await MainActor.run {
                isLoading = false
                self.errorMessage = error.localizedDescription
            }
            
            DebugLogger.debug("❌ Redemption error: \(error.localizedDescription)", category: "Rewards")
            return .failure(error)
        }
    }
    
    // MARK: - Fetch User's Redeemed Rewards
    func fetchRedeemedRewards(userId: String) async -> Result<[RedeemedReward], Error> {
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("redeemedRewards")
                .whereField("userId", isEqualTo: userId)
                .order(by: "redeemedAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            
            let redeemedRewards = snapshot.documents.compactMap { document in
                RedeemedReward(document: document)
            }
            
            DebugLogger.debug("📋 Fetched \(redeemedRewards.count) redeemed rewards for user \(userId)", category: "Rewards")
            return .success(redeemedRewards)
            
        } catch {
            DebugLogger.debug("❌ Error fetching redeemed rewards: \(error.localizedDescription)", category: "Rewards")
            return .failure(error)
        }
    }
    
    // MARK: - Check if Reward is Expired
    func isRewardExpired(_ reward: RedeemedReward) -> Bool {
        return Date() > reward.expiresAt || reward.isExpired
    }
    
    // MARK: - Format Expiration Time
    func formatExpirationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Get Time Remaining
    func getTimeRemaining(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSince(Date())
        
        if timeInterval <= 0 {
            return "Expired"
        }
        
        let minutes = Int(timeInterval / 60)
        let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Network Error
enum NetworkError: Error, LocalizedError {
    case invalidResponse
    case serverError(String)
    case decodingError
    case unauthorized
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return message
        case .decodingError:
            return "Failed to decode response"
        case .unauthorized:
            return "You need to sign in to redeem rewards"
        case .invalidURL:
            return "Invalid URL configuration"
        }
    }
} 