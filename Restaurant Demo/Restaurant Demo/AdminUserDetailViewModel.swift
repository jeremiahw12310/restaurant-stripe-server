import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// View model powering the per‑user admin detail screen.
/// Loads user profile basics, points history, dietary preferences, and referral info.
class AdminUserDetailViewModel: ObservableObject {
    // MARK: - Input
    let userId: String

    // We keep a lightweight summary for header display (name, email, points, lifetimePoints, etc.)
    @Published var userSummary: UserAccount

    // MARK: - Points / Rewards
    @Published var transactions: [PointsTransaction] = []
    @Published var summary: PointsHistorySummary?

    // Editable admin controls
    @Published var editablePoints: String = ""
    @Published var editablePhoneNumber: String = ""
    @Published var editableIsAdmin: Bool = false
    @Published var editableIsVerified: Bool = false

    // MARK: - Dietary Preferences
    @Published var likesSpicyFood: Bool = false
    @Published var dislikesSpicyFood: Bool = false
    @Published var hasPeanutAllergy: Bool = false
    @Published var isVegetarian: Bool = false
    @Published var hasLactoseIntolerance: Bool = false
    @Published var doesntEatPork: Bool = false
    @Published var tastePreferences: String = ""
    @Published var hasCompletedPreferences: Bool = false

    // MARK: - Referral Info
    struct ReferralConnection: Identifiable {
        let id: String
        let name: String
        let relation: String // "Referred by" or "You referred"
        let status: String   // "Pending" | "Awarded"
        let pointsTowards50: Int
    }

    @Published var referralCode: String?
    @Published var outboundReferrals: [ReferralConnection] = []
    @Published var inboundReferral: ReferralConnection?

    // MARK: - Loading / Error
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var referralAwardCheckDebug: String = ""

    private let db = Firestore.firestore()

    init(user: UserAccount) {
        self.userId = user.id
        self.userSummary = user
        syncEditableFieldsFromSummary()
    }

    // MARK: - Public API

    func loadAll() {
        isLoading = true
        errorMessage = ""

        let group = DispatchGroup()
        var firstError: String?

        group.enter()
        loadUserDocument { error in
            if let error = error, firstError == nil { firstError = error }
            group.leave()
        }

        group.enter()
        loadPointsHistory { error in
            if let error = error, firstError == nil { firstError = error }
            group.leave()
        }

        group.enter()
        loadReferralInfo { error in
            if let error = error, firstError == nil { firstError = error }
            group.leave()
        }

        group.notify(queue: .main) {
            self.isLoading = false
            if let message = firstError {
                self.errorMessage = message
            }
        }
    }

    // MARK: - Firestore Loads

    private func loadUserDocument(completion: @escaping (String?) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion("Error loading user profile: \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.data() else {
                    completion("User profile not found")
                    return
                }

                // Update summary with freshest fields
                let accountCreatedDate: Date = (data["accountCreatedDate"] as? Timestamp)?.dateValue() ?? self.userSummary.accountCreatedDate
                let updated = UserAccount(
                    id: self.userSummary.id,
                    firstName: data["firstName"] as? String ?? self.userSummary.firstName,
                    email: data["email"] as? String ?? self.userSummary.email,
                    phoneNumber: data["phone"] as? String ?? self.userSummary.phoneNumber,
                    points: data["points"] as? Int ?? self.userSummary.points,
                    lifetimePoints: data["lifetimePoints"] as? Int ?? self.userSummary.lifetimePoints,
                    avatarEmoji: data["avatarEmoji"] as? String ?? self.userSummary.avatarEmoji,
                    avatarColorName: data["avatarColor"] as? String ?? self.userSummary.avatarColorName,
                    profilePhotoURL: data["profilePhotoURL"] as? String ?? self.userSummary.profilePhotoURL,
                    isVerified: data["isVerified"] as? Bool ?? self.userSummary.isVerified,
                    isAdmin: data["isAdmin"] as? Bool ?? self.userSummary.isAdmin,
                    isEmployee: data["isEmployee"] as? Bool ?? self.userSummary.isEmployee,
                    isBanned: data["isBanned"] as? Bool ?? false,
                    accountCreatedDate: accountCreatedDate,
                    profileImage: self.userSummary.profileImage
                )
                self.userSummary = updated

                // Keep editable fields in sync with latest data
                self.syncEditableFieldsFromSummary()

                // Dietary preferences
                self.likesSpicyFood = data["likesSpicyFood"] as? Bool ?? false
                self.dislikesSpicyFood = data["dislikesSpicyFood"] as? Bool ?? false
                self.hasPeanutAllergy = data["hasPeanutAllergy"] as? Bool ?? false
                self.isVegetarian = data["isVegetarian"] as? Bool ?? false
                self.hasLactoseIntolerance = data["hasLactoseIntolerance"] as? Bool ?? false
                self.doesntEatPork = data["doesntEatPork"] as? Bool ?? false
                self.tastePreferences = data["tastePreferences"] as? String ?? ""
                self.hasCompletedPreferences = data["hasCompletedPreferences"] as? Bool ?? false

                // Referral code (if present)
                self.referralCode = data["referralCode"] as? String

                completion(nil)
            }
        }
    }

    private func loadPointsHistory(completion: @escaping (String?) -> Void) {
        db.collection("pointsTransactions")
            .whereField("userId", isEqualTo: userId)
            .limit(to: 100)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion("Error loading points history: \(error.localizedDescription)")
                        return
                    }
                    guard let documents = snapshot?.documents else {
                        self.transactions = []
                        self.summary = nil
                        completion(nil)
                        return
                    }

                    let loaded = documents.compactMap { PointsTransaction.fromFirestore($0) }
                    // Sort newest first
                    let sorted = loaded.sorted { $0.timestamp > $1.timestamp }
                    self.transactions = sorted
                    self.updateSummary(from: sorted)
                    completion(nil)
                }
            }
    }

    private func loadReferralInfo(completion: @escaping (String?) -> Void) {
        var outbound: [ReferralConnection] = []
        var inbound: ReferralConnection?
        let group = DispatchGroup()
        var firstError: String?

        // Outbound (this user referred others)
        group.enter()
        db.collection("referrals")
            .whereField("referrerUserId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    if firstError == nil { firstError = "Error loading outbound referrals: \(error.localizedDescription)" }
                    group.leave()
                    return
                }
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    group.leave()
                    return
                }

                let innerGroup = DispatchGroup()
                for doc in docs {
                    let data = doc.data()
                    let referredUserId = data["referredUserId"] as? String ?? ""
                    let statusRaw = (data["status"] as? String) ?? "pending"
                    let status = statusRaw == "awarded" ? "Awarded" : "Pending"
                    let referralId = doc.documentID

                    innerGroup.enter()
                    self.db.collection("users").document(referredUserId).getDocument { userDoc, _ in
                        let name = (userDoc?.data()?["firstName"] as? String) ?? "Friend"
                        let pts = (userDoc?.data()?["totalPoints"] as? Int) ?? 0
                        let connection = ReferralConnection(
                            id: referralId,
                            name: name,
                            relation: "You referred",
                            status: status,
                            pointsTowards50: max(0, min(50, pts))
                        )
                        outbound.append(connection)
                        innerGroup.leave()
                    }
                }

                innerGroup.notify(queue: .main) {
                    group.leave()
                }
            }

        // Inbound (someone referred this user)
        group.enter()
        db.collection("referrals")
            .whereField("referredUserId", isEqualTo: userId)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    if firstError == nil { firstError = "Error loading inbound referral: \(error.localizedDescription)" }
                    group.leave()
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    group.leave()
                    return
                }

                let data = doc.data()
                let referrerUserId = data["referrerUserId"] as? String ?? ""
                let statusRaw = (data["status"] as? String) ?? "pending"
                let status = statusRaw == "awarded" ? "Awarded" : "Pending"
                let referralId = doc.documentID

                self.db.collection("users").document(referrerUserId).getDocument { userDoc, _ in
                    let name = (userDoc?.data()?["firstName"] as? String) ?? "Friend"
                    let connection = ReferralConnection(
                        id: referralId,
                        name: name,
                        relation: "Referred by",
                        status: status,
                        pointsTowards50: 0
                    )
                    inbound = connection
                    group.leave()
                }
            }

        group.notify(queue: .main) {
            self.outboundReferrals = outbound.sorted { $0.name < $1.name }
            self.inboundReferral = inbound
            completion(firstError)
        }
    }

    // MARK: - Admin Editing

    func saveAdminEdits(completion: @escaping (Bool, String?) -> Void) {
        // Validate points input
        guard let pointsInt = Int(editablePoints), pointsInt >= 0 else {
            let message = "Points must be a valid non-negative number"
            errorMessage = message
            completion(false, message)
            return
        }

        let phone = editablePhoneNumber
        let isAdminFlag = editableIsAdmin
        let isVerifiedFlag = editableIsVerified

        isLoading = true
        errorMessage = ""

        Task {
            do {
                guard let user = Auth.auth().currentUser else {
                    await MainActor.run {
                        self.isLoading = false
                        let message = "You must be signed in to update users"
                        self.errorMessage = message
                        completion(false, message)
                    }
                    return
                }

                let token = try await user.getIDTokenResult(forcingRefresh: false).token
                guard let url = URL(string: "\(Config.backendURL)/admin/users/update") else {
                    await MainActor.run {
                        self.isLoading = false
                        let message = "Invalid server URL"
                        self.errorMessage = message
                        completion(false, message)
                    }
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "userId": userId,
                    "points": pointsInt,
                    "phone": phone,
                    "isAdmin": isAdminFlag,
                    "isVerified": isVerifiedFlag
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("📤 Sending admin user update request to: \(url.absoluteString)")
                print("📦 Request body: userId=\(userId), points=\(pointsInt), isAdmin=\(isAdminFlag), isVerified=\(isVerifiedFlag)")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    let message = "Unexpected response from server (not HTTP)"
                    print("❌ \(message)")
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = message
                        completion(false, message)
                    }
                    return
                }

                print("📥 Response status: \(http.statusCode)")
                print("📥 Response headers: \(http.allHeaderFields)")

                guard (200..<300).contains(http.statusCode) else {
                    let bodyText = String(data: data, encoding: .utf8) ?? ""
                    print("❌ Server error response: \(bodyText)")
                    
                    // Try to parse error message from JSON response
                    var errorMessage = "Failed to update user"
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = errorJson["error"] as? String {
                            errorMessage = error
                        } else if let errorCode = errorJson["errorCode"] as? String {
                            errorMessage = "\(errorCode): \(errorJson["error"] as? String ?? "Unknown error")"
                        }
                    } else if !bodyText.isEmpty {
                        errorMessage = bodyText
                    }
                    
                    // Add status code context
                    let statusMessage: String
                    switch http.statusCode {
                    case 401:
                        statusMessage = "Authentication failed - please sign in again"
                    case 403:
                        statusMessage = "Permission denied - admin access required"
                    case 404:
                        statusMessage = "User not found"
                    case 400:
                        statusMessage = "Invalid request: \(errorMessage)"
                    case 500:
                        statusMessage = "Server error: \(errorMessage)"
                    default:
                        statusMessage = "HTTP \(http.statusCode): \(errorMessage)"
                    }
                    
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = statusMessage
                        completion(false, statusMessage)
                    }
                    return
                }

                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let previousPoints = json?["previousPoints"] as? Int ?? self.userSummary.points
                let delta = json?["delta"] as? Int ?? (pointsInt - previousPoints)
                let newLifetimePoints = json?["lifetimePoints"] as? Int ?? self.userSummary.lifetimePoints

                await MainActor.run {
                    self.isLoading = false

                    let updatedSummary = UserAccount(
                        id: self.userSummary.id,
                        firstName: self.userSummary.firstName,
                        email: self.userSummary.email,
                        phoneNumber: phone,
                        points: pointsInt,
                        lifetimePoints: newLifetimePoints,
                        avatarEmoji: self.userSummary.avatarEmoji,
                        avatarColorName: self.userSummary.avatarColorName,
                        profilePhotoURL: self.userSummary.profilePhotoURL,
                        isVerified: isVerifiedFlag,
                        isAdmin: isAdminFlag,
                        isEmployee: self.userSummary.isEmployee,
                        isBanned: self.userSummary.isBanned,
                        accountCreatedDate: self.userSummary.accountCreatedDate,
                        profileImage: self.userSummary.profileImage
                    )
                    self.userSummary = updatedSummary
                    self.syncEditableFieldsFromSummary()

                    if delta != 0 {
                        self.loadPointsHistory { _ in }
                    }

                    if previousPoints < 50 && pointsInt >= 50 {
                        self.triggerReferralCheckForUser()
                    }

                    completion(true, nil)
                }
            } catch {
                let message: String
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        message = "No internet connection - please check your network"
                    case .timedOut:
                        message = "Request timed out - server may be slow or unreachable"
                    case .cannotFindHost, .cannotConnectToHost:
                        message = "Cannot reach server - check your backend URL configuration"
                    default:
                        message = "Network error: \(urlError.localizedDescription)"
                    }
                    print("❌ Network error: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
                } else {
                    message = "Failed to update user: \(error.localizedDescription)"
                    print("❌ Error updating user: \(error)")
                }
                
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = message
                    completion(false, message)
                }
            }
        }
    }

    /// Triggers the backend referral award-check for the target user.
    /// Called after admin adjusts points to ensure referral bonuses are awarded if threshold is met.
    private func triggerReferralCheckForUser() {
        print("📤 triggerReferralCheckForUser() called for userId: \(userId)")
        
        guard let url = URL(string: "\(Config.backendURL)/referrals/award-check") else {
            print("❌ Invalid backend URL for referral check")
            return
        }

        print("📤 Calling: \(url.absoluteString)")

        // Get admin's auth token to make the authenticated request
        Auth.auth().currentUser?.getIDToken { [weak self] token, error in
            guard let self = self, let token = token else {
                if let error = error {
                    print("❌ Failed to get admin token for referral check: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.referralAwardCheckDebug = "Referral check failed: \(error.localizedDescription)"
                    }
                }
                return
            }

            print("📤 Got auth token, making request...")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            // Pass the target user ID so backend checks their referral status
            let body: [String: Any] = ["targetUserId": self.userId]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ Referral check request failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.referralAwardCheckDebug = "Referral check error: \(error.localizedDescription)"
                    }
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    print("❌ No HTTP response received")
                    DispatchQueue.main.async {
                        self.referralAwardCheckDebug = "Referral check: no HTTP response"
                    }
                    return
                }

                print("📥 Referral check HTTP status: \(http.statusCode)")

                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📥 Referral check response: \(json)")
                    DispatchQueue.main.async {
                        self.referralAwardCheckDebug = "Referral check HTTP \(http.statusCode): \(json)"
                    }
                    
                    if let status = json["status"] as? String {
                        if status == "awarded" {
                            print("🎉 Referral bonus awarded for user \(self.userId)!")
                            // Reload referral info to reflect the new status
                            DispatchQueue.main.async {
                                self.loadReferralInfo { _ in }
                            }
                        } else if status == "not_eligible" {
                            let reason = json["reason"] as? String ?? "unknown"
                            print("ℹ️ Referral not eligible: \(reason)")
                        } else {
                            print("ℹ️ Referral check result: \(status)")
                        }
                    }
                } else {
                    print("⚠️ Could not parse response, HTTP \(http.statusCode)")
                    if let data = data, let raw = String(data: data, encoding: .utf8) {
                        print("⚠️ Raw response: \(raw)")
                        DispatchQueue.main.async {
                            self.referralAwardCheckDebug = "Referral check HTTP \(http.statusCode) raw: \(raw)"
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.referralAwardCheckDebug = "Referral check HTTP \(http.statusCode) (no body)"
                        }
                    }
                }
            }.resume()
        }
    }

    func syncEditableFieldsFromSummary() {
        editablePoints = String(userSummary.points)
        editablePhoneNumber = userSummary.phoneNumber
        editableIsAdmin = userSummary.isAdmin
        editableIsVerified = userSummary.isVerified
    }

    // MARK: - Helpers

    private func updateSummary(from transactions: [PointsTransaction]) {
        let totalEarned = transactions.filter { $0.isEarned }.reduce(0) { $0 + $1.amount }
        let totalSpent = abs(transactions.filter { $0.isSpent }.reduce(0) { $0 + $1.amount }
        )
        let currentBalance = totalEarned - totalSpent
        let transactionCount = transactions.count
        let lastTransactionDate = transactions.first?.timestamp

        summary = PointsHistorySummary(
            totalEarned: totalEarned,
            totalSpent: totalSpent,
            currentBalance: currentBalance,
            transactionCount: transactionCount,
            lastTransactionDate: lastTransactionDate
        )
    }

    // MARK: - Ban/Unban Functions

    @Published var isBanning: Bool = false
    @Published var banError: String?

    func banUser(reason: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard !isBanning else { return }
        isBanning = true
        banError = nil

        Task {
            do {
                guard let user = Auth.auth().currentUser else {
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "You must be signed in to ban users"
                        completion(false, self.banError)
                    }
                    return
                }

                let token = try await user.getIDTokenResult(forcingRefresh: false).token
                guard let url = URL(string: "\(Config.backendURL)/admin/ban-user") else {
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "Invalid server URL"
                        completion(false, self.banError)
                    }
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                var body: [String: Any] = ["userId": userId]
                if let reason = reason, !reason.isEmpty {
                    body["reason"] = reason
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "Unexpected response from server"
                        completion(false, self.banError)
                    }
                    return
                }

                guard (200..<300).contains(http.statusCode) else {
                    let bodyText = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "Failed to ban user (\(http.statusCode)). \(bodyText)"
                        completion(false, self.banError)
                    }
                    return
                }

                // Reload user document to get updated isBanned status
                await MainActor.run {
                    self.loadUserDocument { _ in }
                    self.isBanning = false
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    self.isBanning = false
                    self.banError = "Failed to ban user: \(error.localizedDescription)"
                    completion(false, self.banError)
                }
            }
        }
    }

    func unbanUser(completion: @escaping (Bool, String?) -> Void) {
        guard !isBanning else { return }
        isBanning = true
        banError = nil

        Task {
            do {
                guard let user = Auth.auth().currentUser else {
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "You must be signed in to unban users"
                        completion(false, self.banError)
                    }
                    return
                }

                let token = try await user.getIDTokenResult(forcingRefresh: false).token
                guard let url = URL(string: "\(Config.backendURL)/admin/unban-number") else {
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "Invalid server URL"
                        completion(false, self.banError)
                    }
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let body = ["phone": userSummary.phoneNumber]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "Unexpected response from server"
                        completion(false, self.banError)
                    }
                    return
                }

                guard (200..<300).contains(http.statusCode) else {
                    let bodyText = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.isBanning = false
                        self.banError = "Failed to unban user (\(http.statusCode)). \(bodyText)"
                        completion(false, self.banError)
                    }
                    return
                }

                // Reload user document to get updated isBanned status
                await MainActor.run {
                    self.loadUserDocument { _ in }
                    self.isBanning = false
                    completion(true, nil)
                }
            } catch {
                await MainActor.run {
                    self.isBanning = false
                    self.banError = "Failed to unban user: \(error.localizedDescription)"
                    completion(false, self.banError)
                }
            }
        }
    }
}



