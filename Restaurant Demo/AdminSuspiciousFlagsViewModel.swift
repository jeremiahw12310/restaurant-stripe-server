import Foundation
import SwiftUI
import FirebaseAuth

// MARK: - Suspicious Flag Models

struct SuspiciousFlag: Identifiable, Codable {
    let id: String
    let userId: String
    let flagType: String
    let severity: String
    let riskScore: Int
    let description: String
    let evidence: [String: AnyCodable]
    let createdAt: String?
    let status: String
    let reviewedBy: String?
    let reviewedAt: String?
    let reviewNotes: String?
    let actionTaken: String?
    let userInfo: UserInfo?
    
    struct UserInfo: Codable {
        let id: String
        let firstName: String
        let lastName: String
        let phone: String
        let email: String
        let points: Int
    }
}

struct SuspiciousFlagsResponse: Codable {
    let flags: [SuspiciousFlag]
    let hasMore: Bool
    let nextCursor: String?
}

// Helper for decoding Any type
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Admin Suspicious Flags ViewModel

@MainActor
class AdminSuspiciousFlagsViewModel: ObservableObject {
    @Published var flags: [SuspiciousFlag] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    
    // Filter state
    @Published var selectedStatus: String? = "pending"
    @Published var selectedSeverity: String?
    @Published var selectedFlagType: String?
    
    // Pagination state
    private var hasMore: Bool = false
    private var nextCursor: String?
    
    // MARK: - Load Flags
    
    func loadFlags() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        flags = []
        nextCursor = nil
        hasMore = false
        
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view suspicious flags."
                isLoading = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            var urlString = "\(Config.backendURL)/admin/suspicious-flags"
            var queryItems: [String] = []
            
            if let status = selectedStatus {
                queryItems.append("status=\(status)")
            }
            if let severity = selectedSeverity {
                queryItems.append("severity=\(severity)")
            }
            if let flagType = selectedFlagType {
                queryItems.append("flagType=\(flagType)")
            }
            
            if !queryItems.isEmpty {
                urlString += "?" + queryItems.joined(separator: "&")
            }
            
            guard let url = URL(string: urlString) else {
                errorMessage = "Invalid suspicious flags URL."
                isLoading = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                isLoading = false
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to load flags (\(http.statusCode)). \(body)"
                isLoading = false
                return
            }
            
            let decoded = try JSONDecoder().decode(SuspiciousFlagsResponse.self, from: data)
            flags = decoded.flags
            hasMore = decoded.hasMore
            nextCursor = decoded.nextCursor
            
            isLoading = false
            
        } catch {
            errorMessage = "Failed to load flags: \(error.localizedDescription)"
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
            var urlString = "\(Config.backendURL)/admin/suspicious-flags"
            var queryItems: [String] = ["startAfter=\(cursor)"]
            
            if let status = selectedStatus {
                queryItems.append("status=\(status)")
            }
            if let severity = selectedSeverity {
                queryItems.append("severity=\(severity)")
            }
            if let flagType = selectedFlagType {
                queryItems.append("flagType=\(flagType)")
            }
            
            urlString += "?" + queryItems.joined(separator: "&")
            
            guard let url = URL(string: urlString) else {
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
            
            let decoded = try JSONDecoder().decode(SuspiciousFlagsResponse.self, from: data)
            flags.append(contentsOf: decoded.flags)
            hasMore = decoded.hasMore
            nextCursor = decoded.nextCursor
            
            isLoadingMore = false
            
        } catch {
            isLoadingMore = false
            // Silently fail for pagination
        }
    }
    
    // MARK: - Review Flag
    
    @Published var isReviewing: Bool = false
    @Published var reviewError: String?
    @Published var showReviewSuccess: Bool = false
    
    struct ReviewFlagResponse: Codable {
        let success: Bool
        let message: String
    }
    
    func reviewFlag(flagId: String, action: String, notes: String?) async {
        guard !isReviewing else { return }
        isReviewing = true
        reviewError = nil
        
        do {
            guard let user = Auth.auth().currentUser else {
                reviewError = "You must be signed in to review flags"
                isReviewing = false
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/suspicious-flags/\(flagId)/review") else {
                reviewError = "Invalid server URL"
                isReviewing = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = ["action": action]
            if let notes = notes, !notes.isEmpty {
                body["notes"] = notes
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                reviewError = "Unexpected response from server"
                isReviewing = false
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                reviewError = "Failed to review flag (\(http.statusCode)). \(bodyText)"
                isReviewing = false
                return
            }
            
            showReviewSuccess = true
            isReviewing = false
            
            // Refresh the flags list
            await loadFlags()
            
        } catch {
            reviewError = "Failed to review flag: \(error.localizedDescription)"
            isReviewing = false
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
    
    // MARK: - Pending Count
    
    func getPendingCount() async -> Int {
        // This would ideally be a separate endpoint for efficiency
        // For now, we'll just count pending flags in the current list
        return flags.filter { $0.status == "pending" }.count
    }
}
