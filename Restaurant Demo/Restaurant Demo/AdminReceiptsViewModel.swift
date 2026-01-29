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
    
    private func loadPage(startAfter: String?) async {
        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = "You must be signed in to view receipts."
                return
            }
            
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/admin/receipts" + (startAfter != nil ? "?startAfter=\(startAfter!)&limit=\(pageSize)" : "?limit=\(pageSize)")) else {
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


