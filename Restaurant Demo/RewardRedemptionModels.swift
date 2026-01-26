import Foundation
import FirebaseFirestore

// MARK: - Reward Eligible Item (for item selection)
struct RewardEligibleItem: Identifiable, Codable, Equatable {
    var id: String { itemId }
    let itemId: String
    let itemName: String
    let categoryId: String?
    let imageURL: String?
    
    enum CodingKeys: String, CodingKey {
        case itemId
        case itemName
        case categoryId
        case imageURL
    }
}

// MARK: - Reward Tier Items Response
struct RewardTierItemsResponse: Codable {
    let pointsRequired: Int
    let tierName: String?
    let eligibleItems: [RewardEligibleItem]
}

// MARK: - Redeemed Reward Model
struct RedeemedReward: Identifiable, Codable {
    let id: String
    let userId: String
    let rewardTitle: String
    let rewardDescription: String
    let rewardCategory: String
    let pointsRequired: Int
    let redemptionCode: String
    let redeemedAt: Date
    let expiresAt: Date
    let isExpired: Bool
    let isUsed: Bool
    let selectedItemId: String?      // Selected item ID
    let selectedItemName: String?    // Selected item name
    let selectedToppingId: String?   // NEW: Topping ID (for drink rewards)
    let selectedToppingName: String? // NEW: Topping name (for drink rewards)
    let selectedItemId2: String?     // NEW: Second item ID (for half-and-half)
    let selectedItemName2: String?   // NEW: Second item name (for half-and-half)
    let cookingMethod: String?       // NEW: Cooking method (for dumpling rewards)
    let drinkType: String?           // NEW: Drink type (Lemonade or Soda)
    let selectedDrinkItemId: String? // NEW: Drink item ID (for Full Combo)
    let selectedDrinkItemName: String? // NEW: Drink item name (for Full Combo)
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case rewardTitle
        case rewardDescription
        case rewardCategory
        case pointsRequired
        case redemptionCode
        case redeemedAt
        case expiresAt
        case isExpired
        case isUsed
        case selectedItemId
        case selectedItemName
        case selectedToppingId
        case selectedToppingName
        case selectedItemId2
        case selectedItemName2
        case cookingMethod
        case drinkType
        case selectedDrinkItemId
        case selectedDrinkItemName
    }
    
    init(id: String, userId: String, rewardTitle: String, rewardDescription: String, rewardCategory: String, pointsRequired: Int, redemptionCode: String, redeemedAt: Date, expiresAt: Date, isExpired: Bool, isUsed: Bool, selectedItemId: String? = nil, selectedItemName: String? = nil, selectedToppingId: String? = nil, selectedToppingName: String? = nil, selectedItemId2: String? = nil, selectedItemName2: String? = nil, cookingMethod: String? = nil, drinkType: String? = nil, selectedDrinkItemId: String? = nil, selectedDrinkItemName: String? = nil) {
        self.id = id
        self.userId = userId
        self.rewardTitle = rewardTitle
        self.rewardDescription = rewardDescription
        self.rewardCategory = rewardCategory
        self.pointsRequired = pointsRequired
        self.redemptionCode = redemptionCode
        self.redeemedAt = redeemedAt
        self.expiresAt = expiresAt
        self.isExpired = isExpired
        self.isUsed = isUsed
        self.selectedItemId = selectedItemId
        self.selectedItemName = selectedItemName
        self.selectedToppingId = selectedToppingId
        self.selectedToppingName = selectedToppingName
        self.selectedItemId2 = selectedItemId2
        self.selectedItemName2 = selectedItemName2
        self.cookingMethod = cookingMethod
        self.drinkType = drinkType
        self.selectedDrinkItemId = selectedDrinkItemId
        self.selectedDrinkItemName = selectedDrinkItemName
    }
    
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.id = document.documentID
        self.userId = data["userId"] as? String ?? ""
        self.rewardTitle = data["rewardTitle"] as? String ?? ""
        self.rewardDescription = data["rewardDescription"] as? String ?? ""
        self.rewardCategory = data["rewardCategory"] as? String ?? ""
        self.pointsRequired = data["pointsRequired"] as? Int ?? 0
        self.redemptionCode = data["redemptionCode"] as? String ?? ""
        
        // Handle Firestore timestamps
        if let redeemedAtTimestamp = data["redeemedAt"] as? Timestamp {
            self.redeemedAt = redeemedAtTimestamp.dateValue()
        } else {
            self.redeemedAt = Date()
        }
        
        if let expiresAtTimestamp = data["expiresAt"] as? Timestamp {
            self.expiresAt = expiresAtTimestamp.dateValue()
        } else {
            self.expiresAt = Date().addingTimeInterval(15 * 60) // 15 minutes from now
        }
        
        self.isExpired = data["isExpired"] as? Bool ?? false
        self.isUsed = data["isUsed"] as? Bool ?? false
        self.selectedItemId = data["selectedItemId"] as? String
        self.selectedItemName = data["selectedItemName"] as? String
        self.selectedToppingId = data["selectedToppingId"] as? String
        self.selectedToppingName = data["selectedToppingName"] as? String
        self.selectedItemId2 = data["selectedItemId2"] as? String
        self.selectedItemName2 = data["selectedItemName2"] as? String
        self.cookingMethod = data["cookingMethod"] as? String
        self.drinkType = data["drinkType"] as? String
        self.selectedDrinkItemId = data["selectedDrinkItemId"] as? String
        self.selectedDrinkItemName = data["selectedDrinkItemName"] as? String
    }
}

// MARK: - Reward Redemption Request
struct RewardRedemptionRequest: Codable {
    let userId: String
    let rewardTitle: String
    let rewardDescription: String
    let pointsRequired: Int
    let rewardCategory: String
    let selectedItemId: String?      // Optional selected item ID
    let selectedItemName: String?    // Optional selected item name
    let selectedToppingId: String?   // NEW: Optional topping ID (for drink rewards)
    let selectedToppingName: String? // NEW: Optional topping name (for drink rewards)
    let selectedItemId2: String?     // NEW: Optional second item ID (for half-and-half)
    let selectedItemName2: String?   // NEW: Optional second item name (for half-and-half)
    let cookingMethod: String?       // NEW: Optional cooking method (for dumpling rewards)
    let drinkType: String?           // NEW: Optional drink type (Lemonade or Soda)
    let selectedDrinkItemId: String? // NEW: Optional drink item ID (for Full Combo)
    let selectedDrinkItemName: String? // NEW: Optional drink item name (for Full Combo)
    
    init(userId: String, rewardTitle: String, rewardDescription: String, pointsRequired: Int, rewardCategory: String, selectedItemId: String? = nil, selectedItemName: String? = nil, selectedToppingId: String? = nil, selectedToppingName: String? = nil, selectedItemId2: String? = nil, selectedItemName2: String? = nil, cookingMethod: String? = nil, drinkType: String? = nil, selectedDrinkItemId: String? = nil, selectedDrinkItemName: String? = nil) {
        self.userId = userId
        self.rewardTitle = rewardTitle
        self.rewardDescription = rewardDescription
        self.pointsRequired = pointsRequired
        self.rewardCategory = rewardCategory
        self.selectedItemId = selectedItemId
        self.selectedItemName = selectedItemName
        self.selectedToppingId = selectedToppingId
        self.selectedToppingName = selectedToppingName
        self.selectedItemId2 = selectedItemId2
        self.selectedItemName2 = selectedItemName2
        self.cookingMethod = cookingMethod
        self.drinkType = drinkType
        self.selectedDrinkItemId = selectedDrinkItemId
        self.selectedDrinkItemName = selectedDrinkItemName
    }
}

// MARK: - Reward Redemption Response
struct RewardRedemptionResponse: Codable {
    let success: Bool
    let redemptionCode: String
    let newPointsBalance: Int
    let pointsDeducted: Int
    let rewardTitle: String
    let selectedItemName: String?    // Selected item name
    let selectedToppingName: String? // NEW: Selected topping name (for drink rewards)
    let selectedItemName2: String?   // NEW: Selected second item name (for half-and-half)
    let cookingMethod: String?       // NEW: Cooking method (for dumpling rewards)
    let drinkType: String?           // NEW: Drink type (Lemonade or Soda)
    let selectedDrinkItemId: String? // NEW: Drink item ID (for Full Combo)
    let selectedDrinkItemName: String? // NEW: Drink item name (for Full Combo)
    let expiresAt: Date
    let message: String
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case redemptionCode
        case newPointsBalance
        case pointsDeducted
        case rewardTitle
        case selectedItemName
        case selectedToppingName
        case selectedItemName2
        case cookingMethod
        case drinkType
        case selectedDrinkItemId
        case selectedDrinkItemName
        case expiresAt
        case message
        case error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.success = try container.decode(Bool.self, forKey: .success)
        self.redemptionCode = try container.decode(String.self, forKey: .redemptionCode)
        self.newPointsBalance = try container.decode(Int.self, forKey: .newPointsBalance)
        self.pointsDeducted = try container.decode(Int.self, forKey: .pointsDeducted)
        self.rewardTitle = try container.decode(String.self, forKey: .rewardTitle)
        self.selectedItemName = try container.decodeIfPresent(String.self, forKey: .selectedItemName)
        self.selectedToppingName = try container.decodeIfPresent(String.self, forKey: .selectedToppingName)
        self.selectedItemName2 = try container.decodeIfPresent(String.self, forKey: .selectedItemName2)
        self.cookingMethod = try container.decodeIfPresent(String.self, forKey: .cookingMethod)
        self.drinkType = try container.decodeIfPresent(String.self, forKey: .drinkType)
        self.selectedDrinkItemId = try container.decodeIfPresent(String.self, forKey: .selectedDrinkItemId)
        self.selectedDrinkItemName = try container.decodeIfPresent(String.self, forKey: .selectedDrinkItemName)
        self.message = try container.decode(String.self, forKey: .message)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        
        // Handle date decoding
        if let expiresAtString = try? container.decode(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            // Support fractional seconds (e.g., "2023-11-02T11:47:32.135Z")
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: expiresAtString) {
                self.expiresAt = date
            } else if let timestamp = TimeInterval(expiresAtString) { // fallback numeric string
                self.expiresAt = Date(timeIntervalSince1970: timestamp)
            } else {
                // Default to 15-minute window if parsing fails
                self.expiresAt = Date().addingTimeInterval(15 * 60)
            }
        } else if let secondsSince1970 = try? container.decode(Double.self, forKey: .expiresAt) {
            // Sometimes backend may send raw seconds
            self.expiresAt = Date(timeIntervalSince1970: secondsSince1970)
        } else {
            self.expiresAt = Date().addingTimeInterval(15 * 60)
        }
    }
}

// MARK: - Redemption Confirmation Dialog Data
struct RedemptionConfirmationData {
    let rewardTitle: String
    let rewardDescription: String
    let pointsRequired: Int
    let currentPoints: Int
    let rewardCategory: String
    let color: String
    let icon: String
}

// MARK: - Redemption Success Data
struct RedemptionSuccessData: Codable {
    let redemptionCode: String
    let rewardTitle: String
    let rewardDescription: String
    let newPointsBalance: Int
    let pointsDeducted: Int
    let expiresAt: Date
    let rewardColorHex: String?
    let rewardIcon: String?
    let selectedItemName: String?    // NEW: Selected item name for display
    
    init(redemptionCode: String, rewardTitle: String, rewardDescription: String, newPointsBalance: Int, pointsDeducted: Int, expiresAt: Date, rewardColorHex: String? = nil, rewardIcon: String? = nil, selectedItemName: String? = nil) {
        self.redemptionCode = redemptionCode
        self.rewardTitle = rewardTitle
        self.rewardDescription = rewardDescription
        self.newPointsBalance = newPointsBalance
        self.pointsDeducted = pointsDeducted
        self.expiresAt = expiresAt
        self.rewardColorHex = rewardColorHex
        self.rewardIcon = rewardIcon
        self.selectedItemName = selectedItemName
    }
    
    /// Display name - shows selected item if available, otherwise reward title
    var displayName: String {
        selectedItemName ?? rewardTitle
    }
} 

extension RedemptionSuccessData: Identifiable {
    var id: String { redemptionCode }
}