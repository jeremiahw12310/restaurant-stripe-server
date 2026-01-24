import Foundation
import FirebaseFirestore

// MARK: - Points Transaction Types
enum PointsTransactionType: String, CaseIterable, Codable {
    case unknown = "unknown"
    case welcome = "welcome"
    case receiptScan = "receipt_scan"
    case rewardRedeemed = "reward_redeemed"
    case rewardExpirationRefund = "reward_expiration_refund"
    case adminAdjustment = "admin_adjustment"
    case bonus = "bonus"
    case referral = "referral"
    
    var displayName: String {
        switch self {
        case .unknown: return "Transaction"
        case .welcome: return "Welcome Points"
        case .receiptScan: return "Receipt Scan"
        case .rewardRedeemed: return "Reward Redeemed"
        case .rewardExpirationRefund: return "Reward Refund"
        case .adminAdjustment: return "Points Adjustment"
        case .bonus: return "Bonus Points"
        case .referral: return "Referral Bonus"
        }
    }
    
    var icon: String {
        switch self {
        case .unknown: return "rectangle.stack"
        case .welcome: return "gift.fill"
        case .receiptScan: return "doc.text.viewfinder"
        case .rewardRedeemed: return "cart.badge.minus"
        case .rewardExpirationRefund: return "arrow.uturn.backward.circle.fill"
        case .adminAdjustment: return "person.crop.circle.badge.checkmark"
        case .bonus: return "star.fill"
        case .referral: return "person.2.fill"
        }
    }
    
    var color: String {
        switch self {
        case .unknown: return "gray"
        case .welcome, .receiptScan, .bonus, .referral, .rewardExpirationRefund: return "green"
        case .rewardRedeemed: return "red"
        case .adminAdjustment: return "blue"
        }
    }
}

// MARK: - Points Transaction Model
struct PointsTransaction: Identifiable {
    let id: String
    let userId: String
    let type: PointsTransactionType
    let amount: Int // Positive for earned, negative for spent
    let description: String
    let timestamp: Date
    let metadata: [String: Any]?
    
    // MARK: - Computed Properties
    var isEarned: Bool {
        return amount > 0
    }
    
    var isSpent: Bool {
        return amount < 0
    }
    
    var absoluteAmount: Int {
        return abs(amount)
    }
    
    var formattedAmount: String {
        let sign = isEarned ? "+" : "-"
        return "\(sign)\(absoluteAmount)"
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    // Use a best-effort inference when type is unknown, based on description keywords.
    var effectiveType: PointsTransactionType {
        if type != .unknown { return type }
        let lower = description.lowercased()
        if lower.contains("refund") && lower.contains("expired") { return .rewardExpirationRefund }
        if lower.contains("redeemed") { return .rewardRedeemed }
        if lower.contains("receipt") { return .receiptScan }
        if lower.contains("welcome") { return .welcome }
        if lower.contains("admin") { return .adminAdjustment }
        if lower.contains("bonus") { return .bonus }
        if lower.contains("referral") { return .referral }
        return .unknown
    }
    
    init(id: String = UUID().uuidString,
         userId: String,
         type: PointsTransactionType,
         amount: Int,
         description: String,
         timestamp: Date = Date(),
         metadata: [String: Any]? = nil) {
        self.id = id
        self.userId = userId
        self.type = type
        self.amount = amount
        self.description = description
        self.timestamp = timestamp
        self.metadata = metadata
    }
    
    // MARK: - Firestore Conversion
    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "type": type.rawValue,
            "amount": amount,
            "description": description,
            "timestamp": timestamp
        ]
        
        if let metadata = metadata {
            data["metadata"] = metadata
        }
        
        return data
    }
    
    static func fromFirestore(_ document: DocumentSnapshot) -> PointsTransaction? {
        guard let data = document.data() else { return nil }
        
        let id = document.documentID
        let userId = data["userId"] as? String ?? ""
        let typeRaw = data["type"] as? String ?? ""
        let type = PointsTransactionType(rawValue: typeRaw) ?? .unknown
        let amount = data["amount"] as? Int ?? 0
        let description = data["description"] as? String ?? ""
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        let metadata = data["metadata"] as? [String: Any]
        
        return PointsTransaction(
            id: id,
            userId: userId,
            type: type,
            amount: amount,
            description: description,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}

// MARK: - Points History Summary
struct PointsHistorySummary {
    let totalEarned: Int
    let totalSpent: Int
    let currentBalance: Int
    let transactionCount: Int
    let lastTransactionDate: Date?
    
    var netPoints: Int {
        totalEarned + totalSpent // totalSpent is negative
    }
    
    var formattedTotalEarned: String {
        return "+\(totalEarned)"
    }
    
    var formattedTotalSpent: String {
        return "\(totalSpent)" // totalSpent is already negative
    }
    
    var formattedNetPoints: String {
        let sign = netPoints >= 0 ? "+" : ""
        return "\(sign)\(netPoints)"
    }
} 