import Foundation
import Firebase

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
                url = URL(string: "\(baseURL)/reward-tier-items/by-id/\(tierId)")!
            } else {
                url = URL(string: "\(baseURL)/reward-tier-items/\(pointsRequired)")!
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "GET"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let tierId, !tierId.isEmpty {
                print("🎁 Fetching eligible items for tier \(tierId)")
            } else {
                print("🎁 Fetching eligible items for \(pointsRequired) point tier")
            }
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            print("📥 Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let tierResponse = try JSONDecoder().decode(RewardTierItemsResponse.self, from: data)
                let itemCount = tierResponse.eligibleItems.count
                
                if let tierId = tierId, !tierId.isEmpty {
                    print("✅ Fetched \(itemCount) eligible items for tier \(tierId)")
                } else {
                    print("✅ Fetched \(itemCount) eligible items for \(pointsRequired) point tier")
                }
                
                if itemCount == 0 {
                    if let tierId = tierId, !tierId.isEmpty {
                        print("⚠️ WARNING: Tier '\(tierId)' returned 0 items. This tier may not be configured in Firestore 'rewardTierItems' collection.")
                    } else {
                        print("⚠️ WARNING: \(pointsRequired) point tier returned 0 items. This tier may not be configured in Firestore 'rewardTierItems' collection.")
                    }
                }
                
                return .success(tierResponse.eligibleItems)
            } else {
                let errorData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = errorData?["error"] as? String ?? "Unknown error occurred"
                
                if let tierId = tierId, !tierId.isEmpty {
                    print("❌ Error fetching tier \(tierId): \(errorMessage)")
                } else {
                    print("❌ Error fetching \(pointsRequired) point tier: \(errorMessage)")
                }
                
                throw NetworkError.serverError(errorMessage)
            }
            
        } catch {
            print("❌ Error fetching eligible items: \(error.localizedDescription)")
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
            
            let url = URL(string: "\(baseURL)/redeem-reward")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let jsonData = try JSONEncoder().encode(request)
            urlRequest.httpBody = jsonData
            
            print("🎁 Redeeming reward: \(rewardTitle) for \(pointsRequired) points")
            if let selectedName = selectedItemName {
                print("🍽️ Selected item: \(selectedName)")
            }
            if let toppingName = selectedToppingName {
                print("🧋 Selected topping: \(toppingName)")
            }
            if let itemName2 = selectedItemName2 {
                print("🥟 Second item: \(itemName2)")
            }
            if let method = cookingMethod {
                print("🔥 Cooking method: \(method)")
            }
            if let type = drinkType {
                print("🥤 Drink type: \(type)")
            }
            print("📡 API URL: \(url)")
            print("📦 Request data: \(String(data: jsonData, encoding: .utf8) ?? "")")
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            print("📥 Response status: \(httpResponse.statusCode)")
            print("📥 Response data: \(String(data: data, encoding: .utf8) ?? "")")
            
            if httpResponse.statusCode == 200 {
                let redemptionResponse = try JSONDecoder().decode(RewardRedemptionResponse.self, from: data)
                
                await MainActor.run {
                    isLoading = false
                }
                
                print("✅ Reward redeemed successfully!")
                print("🔢 Redemption code: \(redemptionResponse.redemptionCode)")
                print("💰 New balance: \(redemptionResponse.newPointsBalance)")
                if let selectedName = redemptionResponse.selectedItemName {
                    print("🍽️ Selected item: \(selectedName)")
                }
                if let toppingName = redemptionResponse.selectedToppingName {
                    print("🧋 Selected topping: \(toppingName)")
                }
                if let itemName2 = redemptionResponse.selectedItemName2 {
                    print("🥟 Second item: \(itemName2)")
                }
                if let method = redemptionResponse.cookingMethod {
                    print("🔥 Cooking method: \(method)")
                }
                if let type = redemptionResponse.drinkType {
                    print("🥤 Drink type: \(type)")
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
                
                print("❌ Redemption failed: \(errorMessage)")
                throw NetworkError.serverError(errorMessage)
            }
            
        } catch {
            await MainActor.run {
                isLoading = false
                self.errorMessage = error.localizedDescription
            }
            
            print("❌ Redemption error: \(error.localizedDescription)")
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
                .getDocuments()
            
            let redeemedRewards = snapshot.documents.compactMap { document in
                RedeemedReward(document: document)
            }
            
            print("📋 Fetched \(redeemedRewards.count) redeemed rewards for user \(userId)")
            return .success(redeemedRewards)
            
        } catch {
            print("❌ Error fetching redeemed rewards: \(error.localizedDescription)")
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
        }
    }
} 