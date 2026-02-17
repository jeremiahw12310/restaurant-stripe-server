import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Time Period Enum

enum TimePeriod: String, CaseIterable {
    case thisMonth = "this-month"
    case thisYear = "this-year"
    case allTime = "all-time"
    
    var displayName: String {
        switch self {
        case .thisMonth: return "This Month"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        }
    }
}

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

struct DeletedRewardsResponse: Codable {
    let rewards: [RewardHistoryItem]
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - Admin Reward History ViewModel

@MainActor
class AdminRewardHistoryViewModel: ObservableObject {
    @Published var availableMonths: [RewardHistoryMonth] = []
    @Published var selectedMonth: String?
    @Published var selectedTimePeriod: TimePeriod = .thisMonth
    @Published var currentRewards: [RewardHistoryItem] = []
    @Published var summary: RewardHistorySummary?
    @Published var allTimeSummary: RewardHistorySummary?
    @Published var isLoadingMonths: Bool = false
    @Published var isLoadingRewards: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var isLoadingAllTimeSummary: Bool = false
    @Published var errorMessage: String?
    
    // Deleted section state
    @Published var showDeletedSection: Bool = false
    @Published var deletedRewards: [RewardHistoryItem] = []
    @Published var selectedDeletedIds: Set<String> = []
    @Published var isLoadingDeleted: Bool = false
    @Published var isSoftDeleting: Bool = false
    @Published var isPermanentlyDeleting: Bool = false
    
    // Pagination state
    private var hasMore: Bool = false
    private var nextCursor: String?
    private var currentMonth: String?
    
    // MARK: - Load All-Time Summary
    
    func loadAllTimeSummary() async {
        guard !isLoadingAllTimeSummary else { return }
        isLoadingAllTimeSummary = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isLoadingAllTimeSummary = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history/all-time-summary") else {
                isLoadingAllTimeSummary = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                isLoadingAllTimeSummary = false
                return
            }
            
            let decoded = try JSONDecoder().decode(RewardHistorySummary.self, from: data)
            allTimeSummary = decoded
            isLoadingAllTimeSummary = false
            
        } catch {
            isLoadingAllTimeSummary = false
            // Silently fail - all-time summary is nice-to-have
        }
    }
    
    // MARK: - Load Available Months
    
    func loadAvailableMonths() async {
        // Only load months when This Month is selected
        guard selectedTimePeriod == .thisMonth else { return }
        
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
            
            let (data, response) = try await URLSession.configured.data(for: request)
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
                await loadRewardsForPeriod(.thisMonth)
            }
            
            isLoadingMonths = false
            
        } catch {
            errorMessage = "Failed to load months: \(error.localizedDescription)"
            isLoadingMonths = false
        }
    }
    
    // MARK: - Load Rewards for Period
    
    func loadRewardsForPeriod(_ period: TimePeriod) async {
        guard !isLoadingRewards else { return }
        isLoadingRewards = true
        errorMessage = nil
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
            let url: URL
            
            switch period {
            case .thisMonth:
                // Use selected month if available, otherwise use current month
                let monthString: String
                if let selectedMonth = selectedMonth {
                    monthString = selectedMonth
                } else {
                    let now = Date()
                    let calendar = Calendar.current
                    let year = calendar.component(.year, from: now)
                    let month = calendar.component(.month, from: now)
                    monthString = String(format: "%04d-%02d", year, month)
                    selectedMonth = monthString
                }
                currentMonth = monthString
                guard let monthUrl = URL(string: "\(Config.backendURL)/admin/rewards/history?month=\(monthString)") else {
                    errorMessage = "Invalid history URL."
                    isLoadingRewards = false
                    return
                }
                url = monthUrl
                
            case .thisYear:
                guard let yearUrl = URL(string: "\(Config.backendURL)/admin/rewards/history/this-year") else {
                    errorMessage = "Invalid history URL."
                    isLoadingRewards = false
                    return
                }
                url = yearUrl
                
            case .allTime:
                guard let allTimeUrl = URL(string: "\(Config.backendURL)/admin/rewards/history/all-time") else {
                    errorMessage = "Invalid history URL."
                    isLoadingRewards = false
                    return
                }
                url = allTimeUrl
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.configured.data(for: request)
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
    
    // MARK: - Load Rewards for Month (kept for backward compatibility)
    
    func loadRewardsForMonth(_ month: String) async {
        currentMonth = month
        selectedTimePeriod = .thisMonth
        await loadRewardsForPeriod(.thisMonth)
    }
    
    // MARK: - Load More Rewards (Pagination)
    
    func loadMoreRewards() async {
        guard !isLoadingMore, hasMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isLoadingMore = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            let url: URL
            
            switch selectedTimePeriod {
            case .thisMonth:
                guard let month = currentMonth,
                      let monthUrl = URL(string: "\(Config.backendURL)/admin/rewards/history?month=\(month)&startAfter=\(cursor)") else {
                    isLoadingMore = false
                    return
                }
                url = monthUrl
                
            case .thisYear:
                guard let yearUrl = URL(string: "\(Config.backendURL)/admin/rewards/history/this-year?startAfter=\(cursor)") else {
                    isLoadingMore = false
                    return
                }
                url = yearUrl
                
            case .allTime:
                guard let allTimeUrl = URL(string: "\(Config.backendURL)/admin/rewards/history/all-time?startAfter=\(cursor)") else {
                    isLoadingMore = false
                    return
                }
                url = allTimeUrl
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.configured.data(for: request)
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
    
    // MARK: - Deleted Section
    
    func loadDeletedRewards() async {
        guard !isLoadingDeleted else { return }
        isLoadingDeleted = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isLoadingDeleted = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history/deleted") else {
                isLoadingDeleted = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                isLoadingDeleted = false
                return
            }
            
            let decoded = try JSONDecoder().decode(DeletedRewardsResponse.self, from: data)
            deletedRewards = decoded.rewards
            isLoadingDeleted = false
            
        } catch {
            isLoadingDeleted = false
        }
    }
    
    func softDeleteReward(id: String) async {
        guard !isSoftDeleting else { return }
        isSoftDeleting = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isSoftDeleting = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history/\(id)/soft-delete") else {
                isSoftDeleting = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (_, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                isSoftDeleting = false
                return
            }
            
            let pointsRemoved = currentRewards.first { $0.id == id }?.pointsRequired ?? 0
            currentRewards.removeAll { $0.id == id }
            if let s = summary {
                summary = RewardHistorySummary(
                    totalRewards: max(0, s.totalRewards - 1),
                    totalPointsRedeemed: max(0, s.totalPointsRedeemed - pointsRemoved),
                    uniqueUsers: s.uniqueUsers
                )
            }
            await loadAllTimeSummary()
            if showDeletedSection {
                await loadDeletedRewards()
            }
            isSoftDeleting = false
            
        } catch {
            isSoftDeleting = false
        }
    }
    
    func toggleDeletedSelection(id: String) {
        if selectedDeletedIds.contains(id) {
            selectedDeletedIds.remove(id)
        } else {
            selectedDeletedIds.insert(id)
        }
    }
    
    func selectAllDeleted() {
        selectedDeletedIds = Set(deletedRewards.map { $0.id })
    }
    
    func deselectAllDeleted() {
        selectedDeletedIds = []
    }
    
    func permanentlyDeleteSelected() async {
        guard !isPermanentlyDeleting, !selectedDeletedIds.isEmpty else { return }
        isPermanentlyDeleting = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isPermanentlyDeleting = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/history/deleted") else {
                isPermanentlyDeleting = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["rewardIds": Array(selectedDeletedIds)])
            
            let (_, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                isPermanentlyDeleting = false
                return
            }
            
            deletedRewards.removeAll { selectedDeletedIds.contains($0.id) }
            selectedDeletedIds = []
            isPermanentlyDeleting = false
            
        } catch {
            isPermanentlyDeleting = false
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        await loadAllTimeSummary()
        if selectedTimePeriod == .thisMonth {
            await loadAvailableMonths()
            // loadAvailableMonths will auto-load the selected month
        } else {
            await loadRewardsForPeriod(selectedTimePeriod)
        }
        if showDeletedSection {
            await loadDeletedRewards()
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
