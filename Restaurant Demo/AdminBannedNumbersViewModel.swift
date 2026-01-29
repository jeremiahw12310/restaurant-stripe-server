import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Banned Number Model

struct BannedNumber: Identifiable, Codable {
    let id: String // phone number
    let phone: String
    let bannedAt: String?
    let bannedByEmail: String
    let originalUserId: String?
    let originalUserName: String?
    let reason: String?
    
    enum CodingKeys: String, CodingKey {
        case phone
        case bannedAt
        case bannedByEmail
        case originalUserId
        case originalUserName
        case reason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.phone = try container.decode(String.self, forKey: .phone)
        self.id = phone
        self.bannedAt = try container.decodeIfPresent(String.self, forKey: .bannedAt)
        self.bannedByEmail = try container.decode(String.self, forKey: .bannedByEmail)
        self.originalUserId = try container.decodeIfPresent(String.self, forKey: .originalUserId)
        self.originalUserName = try container.decodeIfPresent(String.self, forKey: .originalUserName)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

struct BannedNumbersResponse: Codable {
    let bannedNumbers: [BannedNumber]
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - Admin Banned Numbers ViewModel

@MainActor
class AdminBannedNumbersViewModel: ObservableObject {
    @Published var bannedNumbers: [BannedNumber] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    
    // Pagination state
    private var hasMore: Bool = false
    private var nextCursor: String?
    
    // MARK: - Load Banned Numbers
    
    func loadBannedNumbers() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        bannedNumbers = []
        nextCursor = nil
        hasMore = false
        
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view banned numbers."
                isLoading = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/banned-numbers") else {
                errorMessage = "Invalid banned numbers URL."
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
                errorMessage = "Failed to load banned numbers (\(http.statusCode)). \(body)"
                isLoading = false
                return
            }
            
            let decoded = try JSONDecoder().decode(BannedNumbersResponse.self, from: data)
            bannedNumbers = decoded.bannedNumbers
            hasMore = decoded.hasMore
            nextCursor = decoded.nextCursor
            
            isLoading = false
            
        } catch {
            errorMessage = "Failed to load banned numbers: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // MARK: - Load More (Pagination)
    
    func loadMore() async {
        guard !isLoadingMore, hasMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        
        do {
            guard let user = Auth.auth().currentUser else {
                isLoadingMore = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/banned-numbers?startAfter=\(cursor)") else {
                isLoadingMore = false
                return
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
            
            let decoded = try JSONDecoder().decode(BannedNumbersResponse.self, from: data)
            bannedNumbers.append(contentsOf: decoded.bannedNumbers)
            hasMore = decoded.hasMore
            nextCursor = decoded.nextCursor
            
            isLoadingMore = false
            
        } catch {
            isLoadingMore = false
            // Silently fail for pagination
        }
    }
    
    // MARK: - Ban Phone Number
    
    @Published var isBanningPhone: Bool = false
    @Published var banPhoneError: String?
    @Published var showBanSuccess: Bool = false
    @Published var banSuccessMessage: String = ""
    
    struct BanPhoneResponse: Codable {
        let success: Bool
        let phone: String
        let existingAccountFound: Bool
        let bannedUserId: String?
        let bannedUserName: String?
    }
    
    func banPhoneNumber(phone: String, reason: String?) async {
        guard !isBanningPhone else { return }
        isBanningPhone = true
        banPhoneError = nil
        
        do {
            guard let user = Auth.auth().currentUser else {
                banPhoneError = "You must be signed in to ban phone numbers"
                isBanningPhone = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/ban-phone") else {
                banPhoneError = "Invalid server URL"
                isBanningPhone = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = ["phone": phone]
            if let reason = reason, !reason.isEmpty {
                body["reason"] = reason
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                banPhoneError = "Unexpected response from server"
                isBanningPhone = false
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                banPhoneError = "Failed to ban phone number (\(http.statusCode)). \(bodyText)"
                isBanningPhone = false
                return
            }
            
            let decoded = try JSONDecoder().decode(BanPhoneResponse.self, from: data)
            
            // Build success message
            if decoded.existingAccountFound, let userName = decoded.bannedUserName {
                banSuccessMessage = "Phone number banned. Existing account for \(userName) has been banned."
            } else {
                banSuccessMessage = "Phone number banned. No existing account found - future signups with this number will be blocked."
            }
            
            showBanSuccess = true
            isBanningPhone = false
            
            // Refresh the banned numbers list
            await loadBannedNumbers()
            
        } catch {
            banPhoneError = "Failed to ban phone number: \(error.localizedDescription)"
            isBanningPhone = false
        }
    }
    
    // MARK: - Unban Number
    
    @Published var isUnbanning: Bool = false
    
    func unbanNumber(_ phone: String, completion: @escaping (Bool, String?) -> Void) {
        guard !isUnbanning else { return }
        isUnbanning = true
        
        Task {
            do {
                guard let user = Auth.auth().currentUser else {
                    await MainActor.run {
                        self.isUnbanning = false
                        completion(false, "You must be signed in to unban numbers")
                    }
                    return
                }
                
                let token = try await user.getIDTokenResult(forcingRefresh: false).token
                guard let url = URL(string: "\(Config.backendURL)/admin/unban-number") else {
                    await MainActor.run {
                        self.isUnbanning = false
                        completion(false, "Invalid server URL")
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["phone": phone]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (data, response) = try await URLSession.configured.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    await MainActor.run {
                        self.isUnbanning = false
                        completion(false, "Unexpected response from server")
                    }
                    return
                }
                
                guard (200..<300).contains(http.statusCode) else {
                    let bodyText = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.isUnbanning = false
                        completion(false, "Failed to unban number (\(http.statusCode)). \(bodyText)")
                    }
                    return
                }
                
                // Remove from local list
                await MainActor.run {
                    self.bannedNumbers.removeAll { $0.phone == phone }
                    self.isUnbanning = false
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    self.isUnbanning = false
                    completion(false, "Failed to unban number: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Format Date
    
    func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Unknown" }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        return dateString
    }
}
