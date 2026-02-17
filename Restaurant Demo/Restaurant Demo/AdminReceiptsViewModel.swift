import SwiftUI
import FirebaseAuth

struct AdminReceipt: Identifiable, Equatable {
    let id: String
    let orderNumber: String?
    let orderDate: String?
    let timestamp: Date?
    let userId: String?
    let userName: String?
    let userPhone: String?
}

/// Full receipt detail from GET /admin/receipts/:id (for admin detail view).
struct AdminReceiptDetail: Equatable {
    let id: String
    let orderNumber: String?
    let orderDate: String?
    let orderTime: String?
    let orderTotal: Double?
    let userId: String?
    let userName: String?
    let userPhone: String?
    let pointsAwarded: Int?
    let timestamp: Date?
    let imageUrl: URL?
    let imageExpired: Bool
    let totalVisibleAndClear: Bool?
    let orderNumberVisibleAndClear: Bool?
    let dateVisibleAndClear: Bool?
    let timeVisibleAndClear: Bool?
    let keyFieldsTampered: Bool?
    let tamperingReason: String?
    let orderNumberInBlackBox: Bool?
    let paidOnlineReceipt: Bool?
    let orderNumberFromPaidOnlineSection: Bool?
}

@MainActor
class AdminReceiptsViewModel: ObservableObject {
    @Published var receipts: [AdminReceipt] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var nextPageToken: String?
    
    private let pageSize = 50
    
    func refresh() {
        Task {
            await loadInitial()
        }
    }
    
    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil
        receipts.removeAll()
        nextPageToken = nil
        await loadPage(startAfter: nil)
        isLoading = false
    }
    
    func loadMoreIfNeeded(currentReceipt receipt: AdminReceipt?) {
        guard let receipt = receipt else { return }
        guard let last = receipts.last, last == receipt else { return }
        guard nextPageToken != nil else { return }
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        Task {
            await loadPage(startAfter: nextPageToken)
            isLoadingMore = false
        }
    }
    
    func deleteReceipt(_ receipt: AdminReceipt) {
        Task {
            await deleteReceiptAsync(receipt)
        }
    }

    /// Fetches full receipt detail by id (GET /admin/receipts/:id). Returns nil and sets errorMessage on failure.
    func fetchReceiptDetail(receiptId: String) async -> AdminReceiptDetail? {
        errorMessage = nil
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view receipt details."
                return nil
            }
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/receipts/\(receiptId)") else {
                errorMessage = "Invalid receipt detail URL."
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                return nil
            }
            if http.statusCode == 404 {
                errorMessage = "Receipt not found."
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to load receipt (\(http.statusCode)). \(body)"
                return nil
            }
            let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            guard let d = dict else {
                errorMessage = "Invalid response from server."
                return nil
            }
            let id = d["id"] as? String ?? receiptId
            let timestampISO = d["timestamp"] as? String
            var tsDate: Date?
            if let iso = timestampISO {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                tsDate = formatter.date(from: iso)
            }
            var imageURL: URL?
            if let urlString = d["imageUrl"] as? String, !urlString.isEmpty {
                imageURL = URL(string: urlString)
            }
            let imageExpired = (d["imageExpired"] as? Bool) ?? true
            var orderTotal: Double?
            if let n = d["orderTotal"] as? NSNumber { orderTotal = n.doubleValue }
            else if let n = d["orderTotal"] as? Double { orderTotal = n }
            var pointsAwarded: Int?
            if let n = d["pointsAwarded"] as? Int { pointsAwarded = n }
            else if let n = d["pointsAwarded"] as? NSNumber { pointsAwarded = n.intValue }
            return AdminReceiptDetail(
                id: id,
                orderNumber: d["orderNumber"] as? String,
                orderDate: d["orderDate"] as? String,
                orderTime: d["orderTime"] as? String,
                orderTotal: orderTotal,
                userId: d["userId"] as? String,
                userName: d["userName"] as? String,
                userPhone: d["userPhone"] as? String,
                pointsAwarded: pointsAwarded,
                timestamp: tsDate,
                imageUrl: imageURL,
                imageExpired: imageExpired,
                totalVisibleAndClear: d["totalVisibleAndClear"] as? Bool,
                orderNumberVisibleAndClear: d["orderNumberVisibleAndClear"] as? Bool,
                dateVisibleAndClear: d["dateVisibleAndClear"] as? Bool,
                timeVisibleAndClear: d["timeVisibleAndClear"] as? Bool,
                keyFieldsTampered: d["keyFieldsTampered"] as? Bool,
                tamperingReason: d["tamperingReason"] as? String,
                orderNumberInBlackBox: d["orderNumberInBlackBox"] as? Bool,
                paidOnlineReceipt: d["paidOnlineReceipt"] as? Bool,
                orderNumberFromPaidOnlineSection: d["orderNumberFromPaidOnlineSection"] as? Bool
            )
        } catch {
            errorMessage = "Failed to load receipt: \(error.localizedDescription)"
            return nil
        }
    }

    private func loadPage(startAfter: String?) async {
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view receipts."
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            var urlString = "\(Config.backendURL)/admin/receipts?limit=\(pageSize)"
            if let cursor = startAfter {
                urlString += "&startAfter=\(cursor)"
            }
            guard let url = URL(string: urlString) else {
                errorMessage = "Invalid admin receipts URL."
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to load receipts (\(http.statusCode)). \(body)"
                return
            }
            
            let decoded = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            let receiptsJSON = decoded?["receipts"] as? [[String: Any]] ?? []
            let nextToken = decoded?["nextPageToken"] as? String
            
            let newReceipts: [AdminReceipt] = receiptsJSON.compactMap { dict in
                let id = dict["id"] as? String ?? ""
                guard !id.isEmpty else { return nil }
                
                let orderNumber = dict["orderNumber"] as? String
                let orderDate = dict["orderDate"] as? String
                let timestampISO = dict["timestamp"] as? String
                let userId = dict["userId"] as? String
                let userName = dict["userName"] as? String
                let userPhone = dict["userPhone"] as? String
                
                let tsDate: Date?
                if let iso = timestampISO {
                    let formatter = ISO8601DateFormatter()
                    // Support fractional seconds (e.g., "2023-11-02T11:47:32.135Z")
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    tsDate = formatter.date(from: iso)
                } else {
                    tsDate = nil
                }
                
                return AdminReceipt(
                    id: id,
                    orderNumber: orderNumber,
                    orderDate: orderDate,
                    timestamp: tsDate,
                    userId: userId,
                    userName: userName,
                    userPhone: userPhone
                )
            }
            
            receipts.append(contentsOf: newReceipts)
            nextPageToken = nextToken
        } catch {
            errorMessage = "Failed to load receipts: \(error.localizedDescription)"
        }
    }
    
    private func deleteReceiptAsync(_ receipt: AdminReceipt) async {
        errorMessage = nil
        successMessage = nil
        
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to manage receipts."
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/receipts/\(receipt.id)") else {
                errorMessage = "Invalid delete URL."
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "reason": "Admin deleted receipt to allow rescan"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected response from server."
                return
            }
            
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Failed to delete receipt (\(http.statusCode)). \(bodyText)"
                return
            }
            
            receipts.removeAll { $0.id == receipt.id }
            successMessage = "Receipt deleted. Customer can scan it again."
        } catch {
            errorMessage = "Failed to delete receipt: \(error.localizedDescription)"
        }
    }
}


