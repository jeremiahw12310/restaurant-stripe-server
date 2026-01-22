import SwiftUI
import Foundation
import FirebaseAuth

class AdminOfficeViewModel: ObservableObject {
    @Published var users: [UserAccount] = []
    @Published var filteredUsers: [UserAccount] = []
    @Published var isLoading = false
    @Published var isPageLoading = false
    @Published var hasMore = true
    @Published var sortOption: SortOption = .name
    @Published var sortOrder: SortOrder = .ascending
    @Published var errorMessage: String?
    
    // Cleanup state
    @Published var isCleaningUp = false
    @Published var cleanupResult: CleanupResult?
    
    struct CleanupResult {
        let checkedCount: Int
        let deletedCount: Int
        let message: String
    }
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case email = "Email"
        case phone = "Phone"
        case points = "Points"
        case dateCreated = "Date Created"
        case status = "Status"
    }
    
    enum SortOrder: String, CaseIterable {
        case ascending = "Ascending"
        case descending = "Descending"
    }
    
    private let pageSize = 50
    private var nextCursor: String?
    private var activeSearchQuery: String = ""
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var currentRequestId: UUID?
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // Support fractional seconds (e.g., "2023-11-02T11:47:32.135Z")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    func loadUsers() {
        // Initial load resets paging
        isLoading = true
        hasMore = true
        nextCursor = nil
        activeSearchQuery = ""
        errorMessage = nil
        users.removeAll()
        filteredUsers.removeAll()
        fetchNextPage()
    }

    func fetchNextPage() {
        guard hasMore, !isPageLoading else { return }
        fetchUsersPage(query: activeSearchQuery, isReset: false)
    }
    
    func searchUsers(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeSearchQuery = trimmed
        searchDebounceWorkItem?.cancel()
        
        if trimmed.isEmpty {
            // Exit search -> go back to normal paging list
            loadUsers()
            return
        }
        
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fetchUsersPage(query: trimmed, isReset: true)
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    func refreshUsers() {
        loadUsers()
    }
    
    func sortUsers() {
        filteredUsers.sort { user1, user2 in
            let result: Bool
            
            switch sortOption {
            case .name:
                result = user1.firstName.localizedCaseInsensitiveCompare(user2.firstName) == .orderedAscending
            case .email:
                result = user1.email.localizedCaseInsensitiveCompare(user2.email) == .orderedAscending
            case .phone:
                result = user1.phoneNumber.localizedCaseInsensitiveCompare(user2.phoneNumber) == .orderedAscending
            case .points:
                result = user1.points > user2.points
            case .dateCreated:
                result = user1.accountCreatedDate > user2.accountCreatedDate
            case .status:
                let status1 = user1.isAdmin ? 2 : (user1.isVerified ? 1 : 0)
                let status2 = user2.isAdmin ? 2 : (user2.isVerified ? 1 : 0)
                result = status1 > status2
            }
            
            return sortOrder == .ascending ? result : !result
        }
    }
    
    private func updateFilteredUsers() {
        // Update filtered users to reflect changes in the main users array
        // This is called when profile images are loaded
        filteredUsers = users
        sortUsers()
    }
    
    // MARK: - Backend-driven user fetching
    
    private func fetchUsersPage(query: String, isReset: Bool) {
        if isReset {
            isLoading = true
            isPageLoading = false
            hasMore = true
            nextCursor = nil
            users.removeAll()
            filteredUsers.removeAll()
        } else {
            isPageLoading = true
        }
        
        errorMessage = nil
        
        guard let currentUser = Auth.auth().currentUser else {
            isLoading = false
            isPageLoading = false
            errorMessage = "Not authenticated. Please log in again."
            return
        }
        
        let requestId = UUID()
        currentRequestId = requestId
        
        // Timeout safeguard
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, self.currentRequestId == requestId else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                self.isPageLoading = false
                self.errorMessage = "Loading timed out. Please check your connection and try again."
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem)
        
        currentUser.getIDToken { [weak self] token, error in
            guard let self else { return }
            
            if self.currentRequestId != requestId { return }
            
            guard let token else {
                timeoutWorkItem.cancel()
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isPageLoading = false
                    self.errorMessage = "Failed to get auth token: \(error?.localizedDescription ?? "unknown")"
                }
                return
            }
            
            var components = URLComponents(string: "\(Config.backendURL)/admin/users")
            var items: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "\(self.pageSize)")
            ]
            if let cursor = self.nextCursor, !cursor.isEmpty, !isReset {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
            if !query.isEmpty {
                items.append(URLQueryItem(name: "q", value: query))
            }
            components?.queryItems = items
            
            guard let url = components?.url else {
                timeoutWorkItem.cancel()
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isPageLoading = false
                    self.errorMessage = "Invalid server URL"
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data, response, networkError in
                timeoutWorkItem.cancel()
                
                DispatchQueue.main.async {
                    guard self.currentRequestId == requestId else { return }
                    
                    self.isLoading = false
                    self.isPageLoading = false
                    
                    if let networkError {
                        self.errorMessage = "Network error: \(networkError.localizedDescription)"
                        return
                    }
                    
                    guard let http = response as? HTTPURLResponse else {
                        self.errorMessage = "Invalid response"
                        return
                    }
                    
                    guard let data else {
                        self.errorMessage = "No data returned"
                        return
                    }
                    
                    guard http.statusCode == 200 else {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let msg = json["error"] as? String {
                            self.errorMessage = msg
                        } else {
                            self.errorMessage = "Failed to load users (status \(http.statusCode))"
                        }
                        return
                    }
                    
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.errorMessage = "Failed to parse server response"
                        return
                    }
                    
                    let hasMore = json["hasMore"] as? Bool ?? false
                    let nextCursor = json["nextCursor"] as? String
                    let rawUsers = json["users"] as? [[String: Any]] ?? []
                    
                    let parsed: [UserAccount] = rawUsers.map { u in
                        let id = u["id"] as? String ?? UUID().uuidString
                        let firstName = u["firstName"] as? String ?? "Unknown"
                        let email = u["email"] as? String ?? "No email"
                        let phone = u["phone"] as? String ?? ""
                        let points = u["points"] as? Int ?? 0
                        let lifetimePoints = u["lifetimePoints"] as? Int ?? 0
                        let avatarEmoji = u["avatarEmoji"] as? String ?? "👤"
                        let avatarColorName = (u["avatarColor"] as? String) ?? (u["avatarColorName"] as? String) ?? "gray"
                        let profilePhotoURL = u["profilePhotoURL"] as? String
                        let isVerified = u["isVerified"] as? Bool ?? false
                        let isAdmin = u["isAdmin"] as? Bool ?? false
                        let isEmployee = u["isEmployee"] as? Bool ?? false
                        let isBanned = u["isBanned"] as? Bool ?? false
                        
                        var createdAt = Date()
                        if let iso = u["accountCreatedDate"] as? String,
                           let d = Self.isoFormatter.date(from: iso) {
                            createdAt = d
                        }
                        
                        return UserAccount(
                            id: id,
                            firstName: firstName,
                            email: email,
                            phoneNumber: phone,
                            points: points,
                            lifetimePoints: lifetimePoints,
                            avatarEmoji: avatarEmoji,
                            avatarColorName: avatarColorName,
                            profilePhotoURL: profilePhotoURL,
                            isVerified: isVerified,
                            isAdmin: isAdmin,
                            isEmployee: isEmployee,
                            isBanned: isBanned,
                            accountCreatedDate: createdAt,
                            profileImage: nil
                        )
                    }
                    
                    if isReset {
                        self.users = parsed
                    } else {
                        self.users.append(contentsOf: parsed)
                    }
                    
                    self.filteredUsers = self.users
                    self.hasMore = hasMore
                    self.nextCursor = nextCursor
                    self.sortUsers()
                }
            }.resume()
        }
    }
    
    // MARK: - Cleanup Orphaned Accounts
    
    func cleanupOrphanedAccounts() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "Not authenticated. Please log in again."
            return
        }
        
        isCleaningUp = true
        cleanupResult = nil
        errorMessage = nil
        
        currentUser.getIDToken { [weak self] token, error in
            guard let self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isCleaningUp = false
                    self.errorMessage = "Failed to get auth token: \(error.localizedDescription)"
                }
                return
            }
            
            guard let token else {
                DispatchQueue.main.async {
                    self.isCleaningUp = false
                    self.errorMessage = "Failed to get auth token"
                }
                return
            }
            
            guard let url = URL(string: "\(Config.backendURL)/admin/users/cleanup-orphans") else {
                DispatchQueue.main.async {
                    self.isCleaningUp = false
                    self.errorMessage = "Invalid server URL"
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            URLSession.shared.dataTask(with: request) { data, response, networkError in
                DispatchQueue.main.async {
                    self.isCleaningUp = false
                    
                    if let networkError = networkError {
                        self.errorMessage = "Network error: \(networkError.localizedDescription)"
                        return
                    }
                    
                    guard let http = response as? HTTPURLResponse else {
                        self.errorMessage = "Invalid response"
                        return
                    }
                    
                    guard let data else {
                        self.errorMessage = "No data returned"
                        return
                    }
                    
                    guard http.statusCode == 200 else {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let msg = json["error"] as? String {
                            self.errorMessage = msg
                        } else {
                            self.errorMessage = "Cleanup failed (status \(http.statusCode))"
                        }
                        return
                    }
                    
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.errorMessage = "Failed to parse server response"
                        return
                    }
                    
                    let checkedCount = json["checkedCount"] as? Int ?? 0
                    let deletedCount = json["deletedCount"] as? Int ?? 0
                    let message = json["message"] as? String ?? "Cleanup completed"
                    
                    self.cleanupResult = CleanupResult(
                        checkedCount: checkedCount,
                        deletedCount: deletedCount,
                        message: message
                    )
                    
                    // Refresh users list after cleanup
                    self.loadUsers()
                }
            }.resume()
        }
    }
}

struct UserAccount: Identifiable {
    let id: String
    let firstName: String
    let email: String
    let phoneNumber: String
    let points: Int
    let lifetimePoints: Int
    let avatarEmoji: String
    let avatarColorName: String
    let profilePhotoURL: String?
    let isVerified: Bool
    let isAdmin: Bool
    let isEmployee: Bool
    let isBanned: Bool
    let accountCreatedDate: Date
    var profileImage: UIImage?
    
    var avatarColor: Color {
        switch avatarColorName.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        default: return .gray
        }
    }
} 