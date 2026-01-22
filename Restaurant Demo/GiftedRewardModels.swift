import Foundation
import FirebaseFirestore

// MARK: - Gifted Reward Model
struct GiftedReward: Identifiable, Codable {
    let id: String
    let type: String // "broadcast" or "individual"
    let targetUserIds: [String]?
    let rewardTitle: String
    let rewardDescription: String
    let rewardCategory: String
    let pointsRequired: Int // Always 0 for gifts
    let imageName: String?
    let imageURL: String?
    let isCustom: Bool
    let sentAt: Date?
    let sentByAdminId: String
    let expiresAt: Date?
    let isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case targetUserIds
        case rewardTitle
        case rewardDescription
        case rewardCategory
        case pointsRequired
        case imageName
        case imageURL
        case isCustom
        case sentAt
        case sentByAdminId
        case expiresAt
        case isActive
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        targetUserIds = try container.decodeIfPresent([String].self, forKey: .targetUserIds)
        rewardTitle = try container.decode(String.self, forKey: .rewardTitle)
        rewardDescription = try container.decode(String.self, forKey: .rewardDescription)
        rewardCategory = try container.decode(String.self, forKey: .rewardCategory)
        pointsRequired = try container.decode(Int.self, forKey: .pointsRequired)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        isCustom = try container.decode(Bool.self, forKey: .isCustom)
        sentByAdminId = try container.decode(String.self, forKey: .sentByAdminId)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        
        // Handle Firestore timestamps
        if let sentAtTimestamp = try? container.decode(Timestamp.self, forKey: .sentAt) {
            sentAt = sentAtTimestamp.dateValue()
        } else if let sentAtString = try? container.decode(String.self, forKey: .sentAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            sentAt = formatter.date(from: sentAtString)
        } else {
            sentAt = nil
        }
        
        if let expiresAtTimestamp = try? container.decode(Timestamp.self, forKey: .expiresAt) {
            expiresAt = expiresAtTimestamp.dateValue()
        } else if let expiresAtString = try? container.decodeIfPresent(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiresAt = formatter.date(from: expiresAtString)
        } else {
            expiresAt = nil
        }
    }
    
    init(id: String, type: String, targetUserIds: [String]?, rewardTitle: String, rewardDescription: String, rewardCategory: String, pointsRequired: Int, imageName: String?, imageURL: String?, isCustom: Bool, sentAt: Date?, sentByAdminId: String, expiresAt: Date?, isActive: Bool) {
        self.id = id
        self.type = type
        self.targetUserIds = targetUserIds
        self.rewardTitle = rewardTitle
        self.rewardDescription = rewardDescription
        self.rewardCategory = rewardCategory
        self.pointsRequired = pointsRequired
        self.imageName = imageName
        self.imageURL = imageURL
        self.isCustom = isCustom
        self.sentAt = sentAt
        self.sentByAdminId = sentByAdminId
        self.expiresAt = expiresAt
        self.isActive = isActive
    }
    
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.id = document.documentID
        self.type = data["type"] as? String ?? "broadcast"
        self.targetUserIds = data["targetUserIds"] as? [String]
        self.rewardTitle = data["rewardTitle"] as? String ?? ""
        self.rewardDescription = data["rewardDescription"] as? String ?? ""
        self.rewardCategory = data["rewardCategory"] as? String ?? ""
        self.pointsRequired = data["pointsRequired"] as? Int ?? 0
        self.imageName = data["imageName"] as? String
        self.imageURL = data["imageURL"] as? String
        self.isCustom = data["isCustom"] as? Bool ?? false
        self.sentByAdminId = data["sentByAdminId"] as? String ?? ""
        self.isActive = data["isActive"] as? Bool ?? true
        
        // Handle Firestore timestamps
        if let sentAtTimestamp = data["sentAt"] as? Timestamp {
            self.sentAt = sentAtTimestamp.dateValue()
        } else {
            self.sentAt = nil
        }
        
        if let expiresAtTimestamp = data["expiresAt"] as? Timestamp {
            self.expiresAt = expiresAtTimestamp.dateValue()
        } else {
            self.expiresAt = nil
        }
    }
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt < Date()
    }
}

// MARK: - Gifted Reward Claim Model
struct GiftedRewardClaim: Identifiable, Codable {
    let id: String
    let giftedRewardId: String
    let userId: String
    let claimedAt: Date
    let redeemedRewardId: String?
    let isUsed: Bool
    let usedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case giftedRewardId
        case userId
        case claimedAt
        case redeemedRewardId
        case isUsed
        case usedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        giftedRewardId = try container.decode(String.self, forKey: .giftedRewardId)
        userId = try container.decode(String.self, forKey: .userId)
        redeemedRewardId = try container.decodeIfPresent(String.self, forKey: .redeemedRewardId)
        isUsed = try container.decode(Bool.self, forKey: .isUsed)
        
        // Handle Firestore timestamps
        if let claimedAtTimestamp = try? container.decode(Timestamp.self, forKey: .claimedAt) {
            claimedAt = claimedAtTimestamp.dateValue()
        } else if let claimedAtString = try? container.decode(String.self, forKey: .claimedAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            claimedAt = formatter.date(from: claimedAtString) ?? Date()
        } else {
            claimedAt = Date()
        }
        
        if let usedAtTimestamp = try? container.decodeIfPresent(Timestamp.self, forKey: .usedAt) {
            usedAt = usedAtTimestamp.dateValue()
        } else if let usedAtString = try? container.decodeIfPresent(String.self, forKey: .usedAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            usedAt = formatter.date(from: usedAtString)
        } else {
            usedAt = nil
        }
    }
    
    init(id: String, giftedRewardId: String, userId: String, claimedAt: Date, redeemedRewardId: String?, isUsed: Bool, usedAt: Date?) {
        self.id = id
        self.giftedRewardId = giftedRewardId
        self.userId = userId
        self.claimedAt = claimedAt
        self.redeemedRewardId = redeemedRewardId
        self.isUsed = isUsed
        self.usedAt = usedAt
    }
    
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.id = document.documentID
        self.giftedRewardId = data["giftedRewardId"] as? String ?? ""
        self.userId = data["userId"] as? String ?? ""
        self.redeemedRewardId = data["redeemedRewardId"] as? String
        self.isUsed = data["isUsed"] as? Bool ?? false
        
        // Handle Firestore timestamps
        if let claimedAtTimestamp = data["claimedAt"] as? Timestamp {
            self.claimedAt = claimedAtTimestamp.dateValue()
        } else {
            self.claimedAt = Date()
        }
        
        if let usedAtTimestamp = data["usedAt"] as? Timestamp {
            self.usedAt = usedAtTimestamp.dateValue()
        } else {
            self.usedAt = nil
        }
    }
}

// MARK: - Gift Reward Claim Request
struct GiftRewardClaimRequest: Codable {
    let giftedRewardId: String
    let selectedItemId: String?
    let selectedItemName: String?
    let selectedToppingId: String?
    let selectedToppingName: String?
    let selectedItemId2: String?
    let selectedItemName2: String?
    let cookingMethod: String?
    let drinkType: String?
    let selectedDrinkItemId: String?
    let selectedDrinkItemName: String?
}

// MARK: - Gift Reward Claim Response
struct GiftRewardClaimResponse: Codable {
    let success: Bool
    let redemptionCode: String
    let newPointsBalance: Int
    let pointsDeducted: Int
    let rewardTitle: String
    let selectedItemName: String?
    let selectedToppingName: String?
    let selectedItemName2: String?
    let cookingMethod: String?
    let drinkType: String?
    let selectedDrinkItemId: String?
    let selectedDrinkItemName: String?
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
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: expiresAtString) {
                self.expiresAt = date
            } else {
                self.expiresAt = Date().addingTimeInterval(15 * 60)
            }
        } else {
            self.expiresAt = Date().addingTimeInterval(15 * 60)
        }
    }
}
