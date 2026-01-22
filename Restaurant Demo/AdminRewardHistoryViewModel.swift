import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Reward History Models

struct RewardHistoryMonth: Identifiable, Codable {
    let id: String // month string (YYYY-MM)
    let month: String
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case month
        case count
    }
    
    init(month: String, count: Int) {
        self.id = month
        self.month = month
        self.count = count
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.month = try container.decode(String.self, forKey: .month)
        self.count = try container.decode(Int.self, forKey: .count)
        self.id = month
    }
}

struct RewardHistoryMonthsResponse: Codable {
    let months: [RewardHistoryMonth]
}

struct RewardHistorySummary: Codable {
    let totalRewards: Int
    let totalPointsRedeemed: Int
    let uniqueUsers: Int
}

struct RewardHistoryItem: Identifiable, Codable {
    let id: String
    let userFirstName: String
    let rewardTitle: String
    let rewardDescription: String
    let rewardCategory: String
    let selectedItemName: String?
    let selectedItemName2: String?
    let selectedToppingName: String?
    let cookingMethod: String?
    let drinkType: String?
    let pointsRequired: Int
    let redemptionCode: String
    let usedAt: String?
    
    // Computed property for display name
    var displayName: String {
        // Check for half-and-half (has second item)
        if let itemName = selectedItemName, let itemName2 = selectedItemName2 {
            var display = "Half and Half: \(itemName) + \(itemName2)"
            if let method = cookingMethod {
                display += " (\(method))"
            }
            return display
        }
        
        // Check for single dumpling with cooking method
        if let itemName = selectedItemName,
           selectedItemName2 == nil,
           let method = cookingMethod {
            return "\(itemName) (\(method))"
        }
        
        // Check for drink with topping
        if let itemName = selectedItemName, let toppingName = selectedToppingName {
            if let drinkType = drinkType {
                return "\(itemName) (\(drinkType)) with \(toppingName)"
            }
            return "\(itemName) with \(toppingName)"
        }
        
        // Check for drink with drink type but no topping
        if let itemName = selectedItemName, let drinkType = drinkType {
            return "\(itemName) (\(drinkType))"
        }
        
        // Check for drink without topping
        if let itemName = selectedItemName {
            return itemName
        }
        
        // Fallback to reward title
        return rewardTitle
    }
}

struct RewardHistoryResponse: Codable {
    let month: String
    let summary: RewardHistorySummary
    let rewards: [RewardHistoryItem]
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - Admin Reward History ViewModel

@MainActor
class AdminRewardHistoryViewModel: ObservableObject {
    @Published var availableMonths: [RewardHistoryMonth] = []
    @Published var selectedMonth: String?
    @Published var currentRewards: [RewardHistoryItem] = []
    @Published var summary: RewardHistorySummary?
    @Published var isLoadingMonths: Bool = false
    @Published var isLoadingRewards: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    
    // Pagination state
    private var hasMore: Bool = false
    private var nextCursor: String?
    private var currentMonth: String?
    
    // MARK: - Load Available Months
    
    func loadAvailableMonths() async {
        guard !isLoadingMonths else { return }
        isLoadingMonths = true
        errorMessage = nil
        
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view reward history."
                isLoadingMonths = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history/months") else {
                errorMessage = "Invalid months URL."
                isLoadingMonths = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                isLoadingMonths = false
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to load months (\(http.statusCode)). \(body)"
                isLoadingMonths = false
                return
            }
            
            let decoded = try JSONDecoder().decode(RewardHistoryMonthsResponse.self, from: data)
            availableMonths = decoded.months
            
            // Auto-select most recent month if none selected
            if selectedMonth == nil, let firstMonth = decoded.months.first {
                selectedMonth = firstMonth.month
                await loadRewardsForMonth(firstMonth.month)
            }
            
            isLoadingMonths = false
            
        } catch {
            errorMessage = "Failed to load months: \(error.localizedDescription)"
            isLoadingMonths = false
        }
    }
    
    // MARK: - Load Rewards for Month
    
    func loadRewardsForMonth(_ month: String) async {
        guard !isLoadingRewards else { return }
        isLoadingRewards = true
        errorMessage = nil
        currentMonth = month
        currentRewards = []
        summary = nil
        nextCursor = nil
        hasMore = false
        
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view reward history."
                isLoadingRewards = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history?month=\(month)") else {
                errorMessage = "Invalid history URL."
                isLoadingRewards = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                isLoadingRewards = false
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to load rewards (\(http.statusCode)). \(body)"
                isLoadingRewards = false
                return
            }
            
            let decoded = try JSONDecoder().decode(RewardHistoryResponse.self, from: data)
            currentRewards = decoded.rewards
            summary = decoded.summary
            hasMore = decoded.hasMore
            nextCursor = decoded.nextCursor
            
            isLoadingRewards = false
            
        } catch {
            errorMessage = "Failed to load rewards: \(error.localizedDescription)"
            isLoadingRewards = false
        }
    }
    
    // MARK: - Load More Rewards (Pagination)
    
    func loadMoreRewards() async {
        guard !isLoadingMore, hasMore, let cursor = nextCursor, let month = currentMonth else { return }
        isLoadingMore = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isLoadingMore = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history?month=\(month)&startAfter=\(cursor)") else {
                isLoadingMore = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                isLoadingMore = false
                return
            }
            
            let decoded = try JSONDecoder().decode(RewardHistoryResponse.self, from: data)
            currentRewards.append(contentsOf: decoded.rewards)
            hasMore = decoded.hasMore
            nextCursor = decoded.nextCursor
            
            isLoadingMore = false
            
        } catch {
            isLoadingMore = false
            // Silently fail for pagination - user can retry by scrolling
        }
    }
    
    // MARK: - Refresh
    
    func refresh() {
        Task {
            if let month = selectedMonth {
                await loadRewardsForMonth(month)
            } else {
                await loadAvailableMonths()
            }
        }
    }
    
    // MARK: - Format Month Display
    
    func formatMonth(_ month: String) -> String {
        let components = month.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let monthNum = Int(components[1]) else {
            return month
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = monthNum
        dateComponents.day = 1
        
        if let date = Calendar.current.date(from: dateComponents) {
            return dateFormatter.string(from: date)
        }
        
        return month
    }
}
