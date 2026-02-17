import SwiftUI
import FirebaseAuth

// MARK: - Admin Stats Model

struct AdminStats: Codable {
    let totalUsers: Int
    let newUsersToday: Int
    let newUsersThisWeek: Int
    let totalReceipts: Int
    let receiptsToday: Int
    let receiptsThisWeek: Int
    let totalRewardsRedeemed: Int
    let rewardsRedeemedToday: Int
    let totalPointsDistributed: Int
}

// MARK: - Admin Overview ViewModel

@MainActor
class AdminOverviewViewModel: ObservableObject {
    @Published var stats: AdminStats?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var pendingReservationsCount: Int = 0

    func loadStats() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view admin stats."
                isLoading = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/stats") else {
                errorMessage = "Invalid admin stats URL."
                isLoading = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                isLoading = false
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to load stats (\(http.statusCode)). \(body)"
                isLoading = false
                return
            }
            
            let decoded = try JSONDecoder().decode(AdminStats.self, from: data)
            stats = decoded
            isLoading = false
            await loadPendingReservationsCount()

        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func refresh() {
        Task {
            await loadStats()
        }
    }

    func loadPendingReservationsCount() async {
        guard let user = Auth.auth().currentUser else {
            pendingReservationsCount = 0
            return
        }
        do {
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/reservations?status=pending&limit=50") else {
                pendingReservationsCount = 0
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["reservations"] as? [[String: Any]] else {
                pendingReservationsCount = 0
                return
            }
            pendingReservationsCount = list.count
        } catch {
            pendingReservationsCount = 0
        }
    }
}
