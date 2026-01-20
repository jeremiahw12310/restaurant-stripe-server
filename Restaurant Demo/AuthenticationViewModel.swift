import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

class AuthenticationViewModel: ObservableObject {
    
    // MARK: - User Inputs
    @Published var phoneNumber: String = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var birthday = ""
    /// Referral code entered by the user during signup (a friend's code).
    /// IMPORTANT: This must NOT be stored as this user's own `users.referralCode` (share code).
    @Published var referralCodeEntered = ""
    @Published var smsCode: String = ""
    @Published var verificationID: String? = nil
    @Published var isVerifying: Bool = false
    @Published var acceptedPrivacyPolicy: Bool = false
    
    /// Stores the verified phone number after successful authentication.
    /// This is set immediately after sign-in to prevent loss from SwiftUI view lifecycle resets.
    private var verifiedPhoneNumber: String = ""
    
    // MARK: - State Properties
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var accountExists: Bool?
    @Published private(set) var userDocumentID: String?
    
    // MARK: - Navigation Triggers
    @Published var didAuthenticate = false
    @Published var shouldNavigateToUserDetails = false
    @Published var shouldNavigateToCustomization = false
    @Published var shouldNavigateToPreferences = false
    @Published var shouldNavigateToSplash = false
    
    // MARK: - Computed Properties
    var formattedPhoneNumber: String { 
        // Extract digits and format for Firebase
        let digits = phoneNumber.filter { $0.isNumber }
        return "+1" + digits
    }
    
    private var db = Firestore.firestore()
    
    // MARK: - Main Logic
    
    func sendVerificationCode() {
        guard formattedPhoneNumber.count == 12 else {
            errorMessage = "Please enter a valid 10-digit phone number."; return
        }
        guard acceptedPrivacyPolicy else {
            errorMessage = "Please accept the Privacy Policy to continue."; return
        }
        isLoading = true; errorMessage = ""
        PhoneAuthProvider.provider().verifyPhoneNumber(formattedPhoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Failed to send code: \(error.localizedDescription)"; return
                }
                self?.verificationID = verificationID
            }
        }
    }
    
    // Email authentication methods removed - keeping only phone and Apple Sign-In
    
    func verifyCodeAndSignIn() {
        guard let verificationID = verificationID, !smsCode.isEmpty else {
            errorMessage = "Please enter the code sent to your phone."; return
        }
        isVerifying = true; errorMessage = ""
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: smsCode)
        // Capture the phone number NOW before any view lifecycle resets can occur
        let capturedPhone = self.formattedPhoneNumber
        
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isVerifying = false
                if let error = error {
                    self?.errorMessage = "Verification failed: \(error.localizedDescription)"; return
                }
                guard let uid = result?.user.uid else {
                    self?.errorMessage = "Failed to get user ID."; return
                }
                
                // Store the verified phone number immediately after successful sign-in
                // This preserves it even if SwiftUI view lifecycle resets the phoneNumber property
                self?.verifiedPhoneNumber = capturedPhone
                print("🔵 Stored verifiedPhoneNumber: \(capturedPhone)")
                
                self?.checkIfUserExists(uid: uid)
            }
        }
    }
    
    private func checkIfUserExists(uid: String) {
        isLoading = true
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Error: \(error.localizedDescription)"; return
                }
                if let data = snapshot?.data(), !data.isEmpty {
                    self?.didAuthenticate = true
                    // Pre-load referral code for instant access when user opens Referral screen
                    self?.preloadReferralCode()
                } else {
                    self?.shouldNavigateToUserDetails = true
                }
            }
        }
    }
    
    func reset() {
        print("🔵 reset() called")
        phoneNumber = ""
        errorMessage = ""; accountExists = nil; isLoading = false
        userDocumentID = nil; shouldNavigateToSplash = false
        smsCode = ""
        verificationID = nil
        isVerifying = false
        acceptedPrivacyPolicy = false
        // Don't reset navigation states here as they're needed for the flow
        // didAuthenticate = false
        // shouldNavigateToUserDetails = false
        // shouldNavigateToCustomization = false
        // shouldNavigateToPreferences = false
    }
    
    func resetPhoneAndSMS() {
        print("🔵 resetPhoneAndSMS() called")
        phoneNumber = ""
        smsCode = ""
        verificationID = nil
        isVerifying = false
        errorMessage = ""
        isLoading = false
    }
    
    func resetAllNavigationState() {
        print("🔵 resetAllNavigationState() called")
        // Reset all navigation states to ensure clean navigation
        shouldNavigateToUserDetails = false
        shouldNavigateToCustomization = false
        shouldNavigateToPreferences = false
        didAuthenticate = false
        verificationID = nil
        print("✅ All navigation states reset")
    }
    
    func createAccountAndSaveDetails() {
        print("🔵 createAccountAndSaveDetails called")
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated."; return
        }
        guard validateNewAccountDetails() else { return }
        isLoading = true; errorMessage = ""
        print("🔵 About to save user details for UID: \(uid)")
        saveUserDetailsToFirestore(uid: uid)
    }
    
    // MARK: - Private Helpers
    
    private func saveUserDetailsToFirestore(uid: String) {
        print("🔵 saveUserDetailsToFirestore called")
        
        // Use verifiedPhoneNumber (captured at sign-in) as primary source
        // Fall back to Firebase Auth, then formattedPhoneNumber as last resort
        var phoneToSave = verifiedPhoneNumber
        
        // If verifiedPhoneNumber is empty or just "+1", try Firebase Auth
        if phoneToSave.isEmpty || phoneToSave == "+1" {
            phoneToSave = Auth.auth().currentUser?.phoneNumber ?? ""
        }
        
        // If still empty or just "+1", use formattedPhoneNumber (may also be incomplete)
        if phoneToSave.isEmpty || phoneToSave == "+1" {
            phoneToSave = formattedPhoneNumber
        }
        
        print("🔵 Phone to save: \(phoneToSave), verifiedPhoneNumber: \(verifiedPhoneNumber), formattedPhoneNumber: \(formattedPhoneNumber)")
        
        // Validate phone number - warn if it looks incomplete
        if phoneToSave == "+1" || phoneToSave.count < 12 {
            print("⚠️ Warning: Phone number appears incomplete: \(phoneToSave)")
        }
        
        let userData: [String: Any] = [
            "uid": uid, 
            "phone": phoneToSave, 
            "firstName": firstName, 
            "lastName": lastName,
            "birthday": birthday, 
            // NOTE: Do NOT set `users.referralCode` here.
            // That field is reserved for the user's own shareable code and is generated server-side.
            // We store the signup-entered code separately for debugging/audit only.
            "signupReferralCode": referralCodeEntered.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "points": 0, 
            "isNewUser": true, // Mark as new user for welcome popup
            "hasReceivedWelcomePoints": false, // Ensure welcome points not received yet
            "createdAt": FieldValue.serverTimestamp()
        ]
        print("🔵 AuthenticationViewModel: Creating user with isNewUser: true")
        
        print("🔵 Saving user data: \(userData)")
        
        db.collection("users").document(uid).setData(userData) { [weak self] error in
            DispatchQueue.main.async {
                print("🔵 Firestore save completed")
                self?.isLoading = false
                if let error = error {
                    print("🔴 Firestore error: \(error.localizedDescription)")
                    self?.errorMessage = "Auth account created, but failed to save details: \(error.localizedDescription)"
                } else {
                    print("✅ Firestore save successful")
                    // Pre-load referral code for instant access when user opens Referral screen
                    self?.preloadReferralCode()

                    // If we carried a pending referral from a deep link, clear it once the user details are saved.
                    if let entered = self?.referralCodeEntered.trimmingCharacters(in: .whitespacesAndNewlines),
                       !entered.isEmpty {
                        ReferralDeepLinkStore.clearPending()
                    }
                    
                    // If a referral code was entered at signup, accept it now and set session flag to hide input immediately
                    if let code = self?.referralCodeEntered.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
                        self?.acceptReferralAtSignup(uid: uid, code: code) {
                            // Continue navigation regardless of referral outcome
                            self?.advanceToCustomization()
                        }
                    } else {
                        self?.advanceToCustomization()
                    }
                }
            }
        }
    }

    private func advanceToCustomization() {
        // Navigate to dietary preferences screen after account creation
        print("✅ Proceeding to dietary preferences")
        // Reset other navigation states to ensure clean navigation
        self.shouldNavigateToUserDetails = false
        self.shouldNavigateToCustomization = false
        self.didAuthenticate = false
        self.shouldNavigateToPreferences = true
        print("✅ shouldNavigateToPreferences is now: \(self.shouldNavigateToPreferences)")
    }

    private func acceptReferralAtSignup(uid: String, code: String, completion: @escaping () -> Void) {
        guard let user = Auth.auth().currentUser else { completion(); return }
        user.getIDToken { token, err in
            if let err = err { print("❌ Signup referral token error: \(err.localizedDescription)"); completion(); return }
            guard let token = token, let url = URL(string: "\(Config.backendURL)/referrals/accept") else { completion(); return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["code": code.uppercased(), "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? ""]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let http = resp as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 {
                    var referrerId: String? = nil
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        referrerId = json["referrerUserId"] as? String
                    }
                    // Set session flag so ReferralView hides input immediately on first load
                    var payload: [String: String] = [:]
                    if let rid = referrerId { payload["referrerUserId"] = rid }
                    UserDefaults.standard.set(payload, forKey: "referral_pending_\(uid)")
                    print("✅ Signup referral accepted; session flag set")
                } else {
                    print("ℹ️ Signup referral accept not successful or not applicable")
                }
                DispatchQueue.main.async { completion() }
            }.resume()
        }
    }
    
    private func validateNewAccountDetails() -> Bool {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "First and last name are required."; return false
        }
        return true
    }
    
    // Debug method to manually trigger customization navigation
    func forceNavigateToCustomization() {
        print("🔵 forceNavigateToCustomization called")
        // Reset other navigation states to ensure clean navigation
        shouldNavigateToUserDetails = false
        shouldNavigateToPreferences = false
        didAuthenticate = false
        shouldNavigateToCustomization = true
        print("✅ shouldNavigateToCustomization set to: \(shouldNavigateToCustomization)")
    }
    
    // Debug method to print current navigation state
    func printNavigationState() {
        print("🔵 Current Navigation State:")
        print("  - shouldNavigateToUserDetails: \(shouldNavigateToUserDetails)")
        print("  - shouldNavigateToCustomization: \(shouldNavigateToCustomization)")
        print("  - shouldNavigateToPreferences: \(shouldNavigateToPreferences)")
        print("  - didAuthenticate: \(didAuthenticate)")
        print("  - verificationID: \(verificationID?.prefix(10) ?? "nil")")
    }
    
    // MARK: - Referral Code Preload
    
    /// Pre-fetches and caches the user's referral code for instant loading in ReferralView
    func preloadReferralCode() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        
        print("🔄 Pre-loading referral code for instant access...")
        
        user.getIDToken { token, err in
            guard let token = token, err == nil else {
                print("⚠️ Failed to get token for referral preload")
                return
            }
            
            guard let url = URL(string: "\(Config.backendURL)/referrals/create") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard let http = resp as? HTTPURLResponse,
                      http.statusCode >= 200 && http.statusCode < 300,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = json["code"] as? String,
                      let shareUrl = (json["webUrl"] as? String) ?? (json["shareUrl"] as? String),
                      !code.isEmpty else {
                    print("⚠️ Failed to preload referral code")
                    return
                }
                
                // Cache the referral code using the same cache system as ReferralView
                ReferralCache.save(code: code, shareUrl: shareUrl, userId: uid)
                print("✅ Referral code preloaded and cached for instant loading")
            }.resume()
        }
    }
}

// MARK: - Referral Cache (shared with ReferralView)
fileprivate struct ReferralCache {
    // Updated cache key to v3: ensures webUrl (https://) is used for QR + sharing
    private static let cacheKeyPrefix = "referral_cache_v3_"
    
    struct CachedData: Codable {
        let code: String
        let shareUrl: String
        let timestamp: Date
    }
    
    static func save(code: String, shareUrl: String, userId: String) {
        let data = CachedData(code: code, shareUrl: shareUrl, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: cacheKeyPrefix + userId)
        }
    }
    
    static func load(userId: String) -> (code: String, shareUrl: String)? {
        guard let data = UserDefaults.standard.data(forKey: cacheKeyPrefix + userId),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        return (cached.code, cached.shareUrl)
    }
}
