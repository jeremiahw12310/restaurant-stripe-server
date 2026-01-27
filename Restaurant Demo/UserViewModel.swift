//
//  UserViewModel.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/25/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine
import Kingfisher

class UserViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var firstName: String = ""
    @Published var points: Int = 0
    @Published var lifetimePoints: Int = 0 // Total points earned (not spent)
    // ✅ NEW: Added properties to hold the user's avatar customization.
    @Published var avatarEmoji: String = "👤" // Default emoji
    @Published var avatarColorName: String = "gray" // Default color
    @Published var profilePhotoURL: String? = nil // Profile photo URL
    @Published var profileImage: UIImage? = nil // Local profile image
    @Published var isVerified: Bool = false // Verification status
    @Published var isAdmin: Bool = false // Admin status
    @Published var isEmployee: Bool = false // Employee status
    @Published var isBanned: Bool = false // Ban status
    @Published var oldReceiptTestingEnabled: Bool = false // Admin-only: allow scanning old receipts for testing
    @Published var phoneNumber: String = "" // Phone number
    @Published var accountCreatedDate: Date = Date() // Account creation date
    @Published var hasAccountCreatedDate: Bool = false // True only when loaded from Firestore
    @Published var hasReceivedWelcomePoints: Bool = false // Track if user has received welcome points
    @Published var isNewUser: Bool = false // Track if this is a new user who should see welcome popup
    
    // MARK: - User Preferences
    @Published var likesSpicyFood: Bool = false
    @Published var dislikesSpicyFood: Bool = false
    @Published var hasPeanutAllergy: Bool = false
    @Published var isVegetarian: Bool = false
    @Published var hasLactoseIntolerance: Bool = false
    @Published var doesntEatPork: Bool = false
    @Published var tastePreferences: String = ""
    @Published var hasCompletedPreferences: Bool = false
    
    @Published var isLoading: Bool = true
    @Published var isUploadingPhoto: Bool = false
    @Published var showBannedAlert: Bool = false
    // Account deletion re-auth state
    @Published var pendingDeletionVerificationID: String? = nil
    @Published var isAwaitingDeletionSMSCode: Bool = false

    // ✅ NEW: A computed property to safely convert the color name string into a usable SwiftUI Color.
    var avatarColor: Color {
        switch avatarColorName.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "indigo": return .indigo
        case "brown": return .brown
        case "gold": return Color(red: 1.0, green: 0.84, blue: 0.0)
        default: return .gray // A safe default if the color name is unknown.
        }
    }
    
    // MARK: - Methods
    private var previousPointsValue: Int = 0
    private var lastAwardCheckAt: Date?
    private var referrerAwardsListener: ListenerRegistration?
    private var referralAwardsSeenThisSession = Set<String>()
    private var userDocListener: ListenerRegistration?
    private var userDocListenerUserId: String?
    private var lastLoadedProfilePhotoURL: String?
    
    /// Flag to prevent snapshot listener from reacting during intentional account deletion
    private var isDeletingAccount = false
    
    deinit {
        // Performance: Log deinit for memory leak tracking
        DebugLogger.debug("🧹 UserViewModel deinit - cleaning up listeners", category: "User")
        stopUserListener()
    }
    
    // Updated to load the new avatar fields from Firestore.
    func loadUserData() {
        guard let uid = Auth.auth().currentUser?.uid else {
            stopUserListener()
            self.isLoading = false
            return
        }

        // DEBUG (temporary): Log which Firebase Auth user is active on-device.
        // Remove after diagnosing duplicate/test-user behavior.
        if let user = Auth.auth().currentUser {
            DebugLogger.debug("🔎 AUTH uid: \(user.uid)", category: "User")
            // Redact phone number for privacy - only show last 4 digits
            let phoneRedacted = user.phoneNumber.map { phone in
                phone.count > 4 ? "***\(phone.suffix(4))" : "***"
            } ?? "nil"
            DebugLogger.debug("🔎 AUTH phone: \(phoneRedacted)", category: "User")
        } else {
            DebugLogger.debug("🔎 AUTH user is nil", category: "User")
        }
        
        // Avoid stacking duplicate snapshot listeners (a common source of UI churn/stutter).
        if let existingUid = userDocListenerUserId, existingUid == uid, userDocListener != nil {
            return
        }
        
        // User changed or first attach: ensure we have only one active listener.
        stopUserListener()
        userDocListenerUserId = uid

        let db = Firestore.firestore()
        userDocListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, error in
            // Using a snapshot listener will update the UI in real-time if the data changes.
            guard let self = self else { return }
            if let error = error {
                DebugLogger.debug("Error loading user data: \(error.localizedDescription)", category: "User")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            // If the profile doc is missing, treat this as a corrupted session and return to logged-out UI.
            // This can happen if the Auth user exists but users/{uid} was deleted (or never created).
            // EXCEPT: if we're intentionally deleting the account, don't interrupt the deletion flow.
            if let snapshot = snapshot, snapshot.exists == false {
                if self.isDeletingAccount {
                    DebugLogger.debug("ℹ️ UserViewModel: User doc missing during intentional deletion - this is expected, not forcing logout.", category: "User")
                    return
                }
                DebugLogger.debug("❌ UserViewModel: users/\(uid) doc missing. Forcing logout to avoid half-signed-in state.", category: "User")
                DispatchQueue.main.async {
                    self.isLoading = false
                    UserDefaults.standard.set(false, forKey: "isLoggedIn")
                    self.signOut()
                }
                return
            }

            guard let data = snapshot?.data(), !data.isEmpty else {
                DebugLogger.debug("No user data found.", category: "User")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            DispatchQueue.main.async {
                // Assign fetched data to our properties.
                let oldPoints = self.points
                self.firstName = data["firstName"] as? String ?? "User"
                self.points = data["points"] as? Int ?? 0
                self.lifetimePoints = data["lifetimePoints"] as? Int ?? self.points // Initialize with current points if not set
                self.avatarEmoji = data["avatarEmoji"] as? String ?? "👤"
                self.avatarColorName = data["avatarColor"] as? String ?? "gray"
                self.profilePhotoURL = data["profilePhotoURL"] as? String
                self.isVerified = data["isVerified"] as? Bool ?? false
                self.isAdmin = data["isAdmin"] as? Bool ?? false
                self.isEmployee = data["isEmployee"] as? Bool ?? false
                self.phoneNumber = data["phone"] as? String ?? ""
                self.hasReceivedWelcomePoints = data["hasReceivedWelcomePoints"] as? Bool ?? false
                self.isNewUser = data["isNewUser"] as? Bool ?? false
                
                // Check if user is banned - just set flag (LaunchView handles showing deletion screen)
                let isBanned = data["isBanned"] as? Bool ?? false
                self.isBanned = isBanned
                if isBanned {
                    DebugLogger.debug("⚠️ UserViewModel: User is banned. LaunchView will show deletion screen.", category: "User")
                }
                
                // Load account creation date
                if let timestamp = data["accountCreatedDate"] as? Timestamp {
                    self.accountCreatedDate = timestamp.dateValue()
                    self.hasAccountCreatedDate = true
                } else {
                    self.accountCreatedDate = Date()
                    self.hasAccountCreatedDate = false
                }
                
                // Load user preferences
                self.likesSpicyFood = data["likesSpicyFood"] as? Bool ?? false
                self.dislikesSpicyFood = data["dislikesSpicyFood"] as? Bool ?? false
                self.hasPeanutAllergy = data["hasPeanutAllergy"] as? Bool ?? false
                self.isVegetarian = data["isVegetarian"] as? Bool ?? false
                self.hasLactoseIntolerance = data["hasLactoseIntolerance"] as? Bool ?? false
                self.doesntEatPork = data["doesntEatPork"] as? Bool ?? false
                self.tastePreferences = data["tastePreferences"] as? String ?? ""
                self.hasCompletedPreferences = data["hasCompletedPreferences"] as? Bool ?? false
                self.oldReceiptTestingEnabled = data["oldReceiptTestingEnabled"] as? Bool ?? false
                
                // Load profile image only if URL changed (prevents repeated downloads/decoding on every snapshot update).
                if let photoURL = self.profilePhotoURL, !photoURL.isEmpty {
                    if self.lastLoadedProfilePhotoURL != photoURL || self.profileImage == nil {
                        self.lastLoadedProfilePhotoURL = photoURL
                        DebugLogger.debug("🖼️ Loading profile image from URL: \(photoURL)", category: "User")
                        self.loadProfileImage(from: photoURL)
                    }
                } else {
                    self.lastLoadedProfilePhotoURL = nil
                    self.profileImage = nil
                }
                
                self.isLoading = false
                
                // Refresh FCM token and start notifications listener after successful login
                NotificationService.shared.refreshAndStoreFCMToken()
                NotificationService.shared.startNotificationsListener()
                
                // Do NOT automatically trigger the iOS notification permission prompt on login.
                // We only refresh the current permission state here; the UI will decide when to request permission.
                NotificationService.shared.checkNotificationPermission { _ in }

                // Trigger award-check when crossing 50 (admin adjustments or any source)
                self.maybeTriggerReferralAwardCheckOnPointsChange(oldPoints: oldPoints, newPoints: self.points)

                // Start listening for referrer-side awards (so referrer also sees popup)
                self.startReferrerAwardListenerIfNeeded(userId: uid)
            }
        }
    }

    func stopUserListener() {
        userDocListener?.remove()
        userDocListener = nil
        userDocListenerUserId = nil
        
        referrerAwardsListener?.remove()
        referrerAwardsListener = nil
    }

    /// Admin-only helper to update the old-receipt testing flag on the user document.
    /// The UI toggle binds to `oldReceiptTestingEnabled` and calls this to persist changes.
    func updateOldReceiptTestingEnabled(_ enabled: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else {
            DebugLogger.debug("❌ Cannot update oldReceiptTestingEnabled - no authenticated user", category: "User")
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData([
            "oldReceiptTestingEnabled": enabled
        ]) { error in
            if let error = error {
                DebugLogger.debug("❌ Failed to update oldReceiptTestingEnabled: \(error.localizedDescription)", category: "User")
            } else {
                DebugLogger.debug("✅ oldReceiptTestingEnabled updated to \(enabled) for user \(uid)", category: "User")
            }
        }
    }
    
    // MARK: - Photo Management

    // MARK: - Referral Award Helpers
    private func maybeTriggerReferralAwardCheckOnPointsChange(oldPoints: Int, newPoints: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Only when crossing threshold upward
        guard oldPoints < 50 && newPoints >= 50 else { return }
        // Throttle to avoid spamming
        if let last = lastAwardCheckAt, Date().timeIntervalSince(last) < 10 { return }
        lastAwardCheckAt = Date()
        // Call backend award-check
        Auth.auth().currentUser?.getIDToken(completion: { token, _ in
            guard let token = token, let url = URL(string: "\(Config.backendURL)/referrals/award-check") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["referredUserId": uid]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard let http = resp as? HTTPURLResponse else { return }
                if http.statusCode >= 200 && http.statusCode < 300,
                   let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String, status == "awarded" {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("referralAwardGranted"), object: nil, userInfo: ["bonus": 50])
                    }
                }
            }.resume()
        })
    }

    private func startReferrerAwardListenerIfNeeded(userId: String) {
        if referrerAwardsListener != nil { return }
        let db = Firestore.firestore()
        referrerAwardsListener = db.collection("referrals")
            .whereField("referrerUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: "awarded")
            .addSnapshotListener { snapshot, _ in
                guard let changes = snapshot?.documentChanges else { return }
                for change in changes where change.type == .added || change.type == .modified {
                    let doc = change.document
                    let referralId = doc.documentID
                    
                    // Fast in-memory guard to avoid repeated work within a single session.
                    // Cross-device / reinstall prevention is handled via Firestore "seen" docs below.
                    if self.referralAwardsSeenThisSession.contains(referralId) { continue }
                    self.referralAwardsSeenThisSession.insert(referralId)
                    
                    // Persist a "seen" marker in Firestore so the award alert does not repeat across devices/reinstalls.
                    // Path: users/{uid}/clientState/referralAwardSeen_{referralId}
                    let seenRef = db.collection("users")
                        .document(userId)
                        .collection("clientState")
                        .document("referralAwardSeen_\(referralId)")
                    
                    db.runTransaction({ tx, errorPointer -> Any? in
                        do {
                            let seenSnap = try tx.getDocument(seenRef)
                            if seenSnap.exists {
                                // Already seen - don't show popup again
                                return false
                            }
                            tx.setData([
                                "type": "referral_award_seen",
                                "referralId": referralId,
                                "bonus": 50,
                                "seenAt": FieldValue.serverTimestamp()
                            ], forDocument: seenRef)
                            // New marker created - show popup
                            return true
                        } catch let err as NSError {
                            errorPointer?.pointee = err
                            return false
                        }
                    }, completion: { result, error in
                        if let error = error {
                            DebugLogger.debug("❌ Failed to write referral award seen marker: \(error.localizedDescription)", category: "User")
                            return
                        }
                        // Only post notification if transaction returned true (new, not already seen)
                        guard let shouldPost = result as? Bool, shouldPost else {
                            DebugLogger.debug("ℹ️ Referral award already seen, skipping popup", category: "User")
                            return
                        }
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: Notification.Name("referralAwardGranted"),
                                object: nil,
                                userInfo: ["bonus": 50]
                            )
                        }
                    })
                }
            }
    }
    
    func uploadProfilePhoto(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            DebugLogger.debug("❌ No user ID for photo upload", category: "User")
            completion(false)
            return
        }
        
        DebugLogger.debug("📤 Starting photo upload for user: \(uid)", category: "User")
        isUploadingPhoto = true
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            DebugLogger.debug("❌ Failed to compress image", category: "User")
            isUploadingPhoto = false
            completion(false)
            return
        }
        
        DebugLogger.debug("📦 Image compressed, size: \(imageData.count) bytes", category: "User")
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let photoRef = storageRef.child("profile_photos/\(uid).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        photoRef.putData(imageData, metadata: metadata) { metadata, error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("❌ Error uploading photo: \(error.localizedDescription)", category: "User")
                    self.isUploadingPhoto = false
                    completion(false)
                    return
                }
                
                DebugLogger.debug("📤 Photo uploaded to Storage successfully", category: "User")
                
                // Get download URL
                photoRef.downloadURL { url, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            DebugLogger.debug("❌ Error getting download URL: \(error.localizedDescription)", category: "User")
                            self.isUploadingPhoto = false
                            completion(false)
                            return
                        }
                        
                        if let downloadURL = url {
                            DebugLogger.debug("🔗 Got download URL: \(downloadURL.absoluteString)", category: "User")
                            // Save URL to Firestore
                            self.saveProfilePhotoURL(downloadURL.absoluteString) { success in
                                self.isUploadingPhoto = false
                                if success {
                                    DebugLogger.debug("✅ Profile photo URL saved to Firestore", category: "User")
                                    self.profilePhotoURL = downloadURL.absoluteString
                                    self.profileImage = image
                                    DebugLogger.debug("🖼️ Profile image updated locally: \(self.profileImage != nil)", category: "User")
                                }
                                completion(success)
                            }
                        } else {
                            DebugLogger.debug("❌ Failed to get download URL", category: "User")
                            self.isUploadingPhoto = false
                            completion(false)
                        }
                    }
                }
            }
        }
    }
    
    private func saveProfilePhotoURL(_ url: String, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData([
            "profilePhotoURL": url
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("Error saving photo URL: \(error.localizedDescription)", category: "User")
                    completion(false)
                } else {
                    // Update all existing posts and replies to include the new profile photo URL
                    self.updateProfilePhotoInAllPosts(userId: uid, profilePhotoURL: url) { success in
                        if success {
                            DebugLogger.debug("✅ Successfully updated profile photo in all community posts", category: "User")
                        } else {
                            DebugLogger.debug("⚠️ Failed to update some community posts with new profile photo", category: "User")
                        }
                        completion(true) // Continue regardless of community update success
                    }
                }
            }
        }
    }
    
    private func loadProfileImage(from urlString: String) {
        guard let url = URL(string: urlString) else { 
            DebugLogger.debug("❌ Invalid URL: \(urlString)", category: "User")
            return 
        }
        
        DebugLogger.debug("🖼️ Loading image from URL: \(url)", category: "User")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("❌ Error loading image: \(error.localizedDescription)", category: "User")
                    return
                }
                
                if let data = data, let image = UIImage(data: data) {
                    DebugLogger.debug("✅ Image loaded successfully, size: \(data.count) bytes", category: "User")
                    self.profileImage = image
                    DebugLogger.debug("🖼️ Profile image set: \(self.profileImage != nil)", category: "User")
                } else {
                    DebugLogger.debug("❌ Failed to create image from data", category: "User")
                }
            }
        }.resume()
    }
    
    func removeProfilePhoto(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        // Delete from Storage
        if let photoURL = profilePhotoURL {
            let storage = Storage.storage()
            let storageRef = storage.reference()
            let photoRef = storageRef.child("profile_photos/\(uid).jpg")
            
            photoRef.delete { error in
                DispatchQueue.main.async {
                    if let error = error {
                        DebugLogger.debug("Error deleting photo: \(error.localizedDescription)", category: "User")
                    }
                    
                    // Remove from Firestore
                    let db = Firestore.firestore()
                    db.collection("users").document(uid).updateData([
                        "profilePhotoURL": FieldValue.delete()
                    ]) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                DebugLogger.debug("Error removing photo URL: \(error.localizedDescription)", category: "User")
                                completion(false)
                            } else {
                                self.profilePhotoURL = nil
                                self.profileImage = nil
                                
                                // Clear profile photo URL from all existing posts and replies
                                self.clearProfilePhotoFromAllPosts(userId: uid) { success in
                                    if success {
                                        DebugLogger.debug("✅ Successfully cleared profile photo from all community posts", category: "User")
                                    } else {
                                        DebugLogger.debug("⚠️ Failed to clear some community posts", category: "User")
                                    }
                                    completion(true) // Continue regardless of community update success
                                }
                            }
                        }
                    }
                }
            }
        } else {
            completion(true)
        }
    }
    
    // MARK: - Force Refresh Methods
    
    func forceRefreshProfileImage() {
        DebugLogger.debug("🔄 Force refreshing profile image", category: "User")
        if let photoURL = profilePhotoURL {
            loadProfileImage(from: photoURL)
        } else {
            profileImage = nil
        }
    }
    
    func clearProfileImageCache() {
        DebugLogger.debug("🗑️ Clearing profile image cache", category: "User")
        profileImage = nil
    }
    
    // MARK: - Community Post Updates
    
    func updateProfilePhotoInAllPosts(userId: String, profilePhotoURL: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Update all posts by this user (limited to 500 for performance)
        db.collection("posts").whereField("userId", isEqualTo: userId).limit(to: 500).getDocuments { snapshot, error in
            if let error = error {
                DebugLogger.debug("❌ Error fetching user posts: \(error.localizedDescription)", category: "User")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                DebugLogger.debug("✅ No posts found for user", category: "User")
                completion(true)
                return
            }
            
            // Update posts - clear emoji and color when switching to profile photo
            for doc in documents {
                let postRef = doc.reference
                batch.updateData([
                    "userProfilePhotoURL": profilePhotoURL,
                    "authorProfilePhotoURL": profilePhotoURL, // Also update author field
                    "avatarEmoji": FieldValue.delete(),
                    "avatarColorName": FieldValue.delete(),
                    "authorAvatarEmoji": FieldValue.delete(), // Also clear author fields
                    "authorAvatarColorName": FieldValue.delete()
                ], forDocument: postRef)
            }
            
            // Update replies for this user in all posts
            self.updateProfilePhotoInAllReplies(userId: userId, profilePhotoURL: profilePhotoURL) { success in
                if success {
                    // Commit the batch update for posts
                    batch.commit { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                DebugLogger.debug("❌ Error updating posts: \(error.localizedDescription)", category: "User")
                                completion(false)
                            } else {
                                DebugLogger.debug("✅ Successfully updated \(documents.count) posts for user", category: "User")
                                completion(true)
                            }
                        }
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private func updateProfilePhotoInAllReplies(userId: String, profilePhotoURL: String, completion: @escaping (Bool) -> Void) {
        // Get all posts that have replies (limited to 500 for performance)
        let db = Firestore.firestore()
        db.collection("posts").limit(to: 500).getDocuments { snapshot, error in
            if let error = error {
                DebugLogger.debug("❌ Error fetching posts for reply updates: \(error.localizedDescription)", category: "User")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                DebugLogger.debug("✅ No posts found for reply updates", category: "User")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post (limited to 100 for performance)
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).limit(to: 100).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        DebugLogger.debug("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)", category: "User")
                        hasErrors = true
                        return
                    }
                    
                    guard let replyDocuments = replySnapshot?.documents else {
                        return
                    }
                    
                    // Update replies for this user - clear emoji and color when switching to profile photo
                    let replyBatch = db.batch()
                    for replyDoc in replyDocuments {
                        let replyRef = replyDoc.reference
                        replyBatch.updateData([
                            "userProfilePhotoURL": profilePhotoURL,
                            "avatarEmoji": FieldValue.delete(),
                            "avatarColorName": FieldValue.delete()
                        ], forDocument: replyRef)
                    }
                    
                    replyBatch.commit { batchError in
                        if let batchError = batchError {
                            DebugLogger.debug("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)", category: "User")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            DebugLogger.debug("✅ Updated \(replyDocuments.count) replies for post \(postDoc.documentID)", category: "User")
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(!hasErrors)
            }
        }
    }

    func clearProfilePhotoFromAllPosts(userId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Update all posts by this user (limited to 500 for performance)
        db.collection("posts").whereField("userId", isEqualTo: userId).limit(to: 500).getDocuments { snapshot, error in
            if let error = error {
                DebugLogger.debug("❌ Error fetching user posts: \(error.localizedDescription)", category: "User")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                DebugLogger.debug("✅ No posts found for user", category: "User")
                completion(true)
                return
            }
            
            // Update posts - set emoji and color when switching from profile photo to emoji avatar
            for doc in documents {
                let postRef = doc.reference
                batch.updateData([
                    "userProfilePhotoURL": FieldValue.delete(),
                    "authorProfilePhotoURL": FieldValue.delete(), // Also clear the author field
                    "avatarEmoji": self.avatarEmoji,
                    "avatarColorName": self.avatarColorName,
                    "authorAvatarEmoji": self.avatarEmoji, // Also update author fields
                    "authorAvatarColorName": self.avatarColorName
                ], forDocument: postRef)
            }
            
            // Clear profile photo URL from replies for this user in all posts
            self.clearProfilePhotoFromAllReplies(userId: userId) { success in
                if success {
                    // Commit the batch update for posts
                    batch.commit { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                DebugLogger.debug("❌ Error updating posts: \(error.localizedDescription)", category: "User")
                                completion(false)
                            } else {
                                DebugLogger.debug("✅ Successfully cleared profile photo from \(documents.count) posts for user", category: "User")
                                completion(true)
                            }
                        }
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private func clearProfilePhotoFromAllReplies(userId: String, completion: @escaping (Bool) -> Void) {
        // Get all posts that have replies (limited to 500 for performance)
        let db = Firestore.firestore()
        db.collection("posts").limit(to: 500).getDocuments { snapshot, error in
            if let error = error {
                DebugLogger.debug("❌ Error fetching posts for reply updates: \(error.localizedDescription)", category: "User")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                DebugLogger.debug("✅ No posts found for reply updates", category: "User")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post (limited to 100 for performance)
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).limit(to: 100).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        DebugLogger.debug("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)", category: "User")
                        hasErrors = true
                        return
                    }
                    
                    guard let replyDocuments = replySnapshot?.documents else {
                        return
                    }
                    
                    // Update replies for this user - set emoji and color when switching from profile photo to emoji avatar
                    let replyBatch = db.batch()
                    for replyDoc in replyDocuments {
                        let replyRef = replyDoc.reference
                        replyBatch.updateData([
                            "userProfilePhotoURL": FieldValue.delete(),
                            "avatarEmoji": self.avatarEmoji,
                            "avatarColorName": self.avatarColorName
                        ], forDocument: replyRef)
                    }
                    
                    replyBatch.commit { batchError in
                        if let batchError = batchError {
                            DebugLogger.debug("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)", category: "User")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            DebugLogger.debug("✅ Cleared profile photo from \(replyDocuments.count) replies for post \(postDoc.documentID)", category: "User")
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(!hasErrors)
            }
        }
    }

    // MARK: - Avatar Update Methods
    
    func updateAvatarInAllPosts(userId: String, avatarEmoji: String, avatarColorName: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Update all posts by this user (limited to 500 for performance)
        db.collection("posts").whereField("userId", isEqualTo: userId).limit(to: 500).getDocuments { snapshot, error in
            if let error = error {
                DebugLogger.debug("❌ Error fetching user posts: \(error.localizedDescription)", category: "User")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                DebugLogger.debug("✅ No posts found for user", category: "User")
                completion(true)
                return
            }
            
            // Update posts with new emoji and color
            for doc in documents {
                let postRef = doc.reference
                batch.updateData([
                    "avatarEmoji": avatarEmoji,
                    "avatarColorName": avatarColorName,
                    "authorAvatarEmoji": avatarEmoji, // Also update author fields
                    "authorAvatarColorName": avatarColorName
                ], forDocument: postRef)
            }
            
            // Update replies for this user in all posts
            self.updateAvatarInAllReplies(userId: userId, avatarEmoji: avatarEmoji, avatarColorName: avatarColorName) { success in
                if success {
                    // Commit the batch update for posts
                    batch.commit { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                DebugLogger.debug("❌ Error updating posts: \(error.localizedDescription)", category: "User")
                                completion(false)
                            } else {
                                DebugLogger.debug("✅ Successfully updated \(documents.count) posts with new avatar", category: "User")
                                completion(true)
                            }
                        }
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private func updateAvatarInAllReplies(userId: String, avatarEmoji: String, avatarColorName: String, completion: @escaping (Bool) -> Void) {
        // Get all posts that have replies (limited to 500 for performance)
        let db = Firestore.firestore()
        db.collection("posts").limit(to: 500).getDocuments { snapshot, error in
            if let error = error {
                DebugLogger.debug("❌ Error fetching posts for reply updates: \(error.localizedDescription)", category: "User")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                DebugLogger.debug("✅ No posts found for reply updates", category: "User")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post (limited to 100 for performance)
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).limit(to: 100).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        DebugLogger.debug("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)", category: "User")
                        hasErrors = true
                        return
                    }
                    
                    guard let replyDocuments = replySnapshot?.documents else {
                        return
                    }
                    
                    // Update replies for this user
                    let replyBatch = db.batch()
                    for replyDoc in replyDocuments {
                        let replyRef = replyDoc.reference
                        replyBatch.updateData([
                            "avatarEmoji": avatarEmoji,
                            "avatarColorName": avatarColorName
                        ], forDocument: replyRef)
                    }
                    
                    replyBatch.commit { batchError in
                        if let batchError = batchError {
                            DebugLogger.debug("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)", category: "User")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            DebugLogger.debug("✅ Updated \(replyDocuments.count) replies for post \(postDoc.documentID)", category: "User")
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(!hasErrors)
            }
        }
    }
    
    // MARK: - User Preferences Methods
    
    func saveUserPreferences(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        let db = Firestore.firestore()
        let preferencesData: [String: Any] = [
            "likesSpicyFood": likesSpicyFood,
            "dislikesSpicyFood": dislikesSpicyFood,
            "hasPeanutAllergy": hasPeanutAllergy,
            "isVegetarian": isVegetarian,
            "hasLactoseIntolerance": hasLactoseIntolerance,
            "doesntEatPork": doesntEatPork,
            "tastePreferences": tastePreferences,
            "hasCompletedPreferences": true
        ]
        
        db.collection("users").document(uid).updateData(preferencesData) { error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("❌ Error saving user preferences: \(error.localizedDescription)", category: "User")
                    completion(false)
                } else {
                    DebugLogger.debug("✅ User preferences saved successfully", category: "User")
                    self.hasCompletedPreferences = true
                    completion(true)
                }
            }
        }
    }
    
    /// - Parameter skipFCMRemoval: When true, skip removing FCM token from Firestore (e.g. after account deletion).
    ///   The user document no longer exists, so FCM removal would fail with permission errors.
    func signOut(skipFCMRemoval: Bool = false) {
        // FIXED: Clear all cached data when signing out to prevent storage bloat
        DebugLogger.debug("🧹 Clearing all cached data for account switch...", category: "User")
        
        // Remove FCM token from Firestore before signing out (skip if user/doc already deleted)
        if !skipFCMRemoval {
            NotificationService.shared.removeFCMToken()
        }
        NotificationService.shared.stopNotificationsListener()
        NotificationService.shared.resetTokenRefreshFlag()
        
        // Stop Firestore listeners first to prevent background callbacks while we clear state.
        stopUserListener()
        
        // Ensure LaunchView returns to Get Started flow
        UserDefaults.standard.set(false, forKey: "isLoggedIn")

        // Clear any pending referral deep link and referral session/cache keys
        ReferralDeepLinkStore.clearPending()
        if let uid = Auth.auth().currentUser?.uid {
            UserDefaults.standard.removeObject(forKey: "referral_pending_\(uid)")
            // Clear both v3 and v4 referral cache formats (the app currently uses v4 in ContentView).
            UserDefaults.standard.removeObject(forKey: "referral_cache_v3_\(uid)")
            UserDefaults.standard.removeObject(forKey: "referral_cache_v4_\(uid)")
        }
        // Clear persisted active reward card (cross-account leak prevention)
        UserDefaults.standard.removeObject(forKey: "persistedActiveReward")

        // Clear UserDefaults data
        clearAllUserDefaultsData()
        
        // Clear Kingfisher image cache
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
        
        // Clear offline cache
        OfflineCacheManager().clearCache()
        
        // Clear local user data
        self.firstName = ""
        self.points = 0
        self.lifetimePoints = 0
        self.isAdmin = false
        self.isVerified = false
        self.avatarEmoji = "👤"
        self.avatarColorName = "gray"
        self.profilePhotoURL = nil
        self.profileImage = nil
        self.phoneNumber = ""
        self.hasReceivedWelcomePoints = false
        self.isNewUser = false
        
        // Finally, sign out from Firebase Auth
        try? Auth.auth().signOut()
        
        DebugLogger.debug("✅ All cached data cleared for account switch", category: "User")
    }
    
    // FIXED: Add method to clear all UserDefaults data
    private func clearAllUserDefaultsData() {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys
        var clearedCount = 0
        
        for key in keys {
            // Clear all potentially large data
            if key.contains("pendingActions") || 
               key.contains("videos_") || 
               key.contains("posts_") || 
               key.contains("comments_") ||
               key.contains("userProfiles_") ||
               key.contains("menuItems_") ||
               key.contains("recent_searches") ||
               key.contains("lastSyncDate") {
                userDefaults.removeObject(forKey: key)
                clearedCount += 1
            }
        }
        
        if clearedCount > 0 {
            DebugLogger.debug("🧹 Cleared \(clearedCount) UserDefaults entries during sign out", category: "User")
        }
    }
    
    // MARK: - Welcome Points
    
    /// Claims welcome points. Completion: (success, blockedReason).
    /// blockedReason is non-nil when request succeeded but points were withheld (e.g. phone previously claimed).
    func addWelcomePoints(completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("❌ No authenticated user found", category: "User")
            completion(false, nil)
            return
        }
        
        user.getIDToken { token, error in
            if let error = error {
                DebugLogger.debug("❌ Failed to get ID token for welcome claim: \(error.localizedDescription)", category: "User")
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            guard let token = token, let url = URL(string: "\(Config.backendURL)/welcome/claim") else {
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err {
                    DebugLogger.debug("❌ Welcome claim network error: \(err.localizedDescription)", category: "User")
                    DispatchQueue.main.async { completion(false, nil) }
                    return
                }
                
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    DebugLogger.debug("❌ Welcome claim failed (\(http.statusCode)): \(body)", category: "User")
                    DispatchQueue.main.async { completion(false, nil) }
                    return
                }
                
                var blockedReason: String? = nil
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let newPoints = json["newPointsBalance"] as? Int { DispatchQueue.main.async { self.points = newPoints } }
                    if let newLifetime = json["newLifetimePoints"] as? Int { DispatchQueue.main.async { self.lifetimePoints = newLifetime } }
                    if let already = json["alreadyClaimed"] as? Bool, already == true {
                        if let reason = json["reason"] as? String, reason == "phone_previously_claimed" {
                            DebugLogger.debug("ℹ️ Welcome points blocked - phone number previously claimed on another account", category: "User")
                            blockedReason = "phone_previously_claimed"
                        } else {
                            DebugLogger.debug("ℹ️ Welcome points already claimed on this account", category: "User")
                        }
                    } else {
                        DebugLogger.debug("✅ Welcome points claimed server-side", category: "User")
                    }
                }
                
                DispatchQueue.main.async { completion(true, blockedReason) }
            }.resume()
        }
    }
    
    // MARK: - Points History Integration
    
    private func logWelcomePointsTransaction(points: Int) {
        // No-op: pointsTransactions are now written server-side.
    }
    
    func logReceiptScanTransaction(points: Int, receiptTotal: Double) {
        // No-op: receipt scan transactions are now written server-side.
    }
    
    func logRewardRedeemedTransaction(points: Int, rewardTitle: String) {
        // No-op: reward redemption transactions are written server-side.
    }
    
    // MARK: - Account Deletion
    
    /// Starts phone re-authentication for account deletion. Sends an SMS to the current user's phone.
    /// Call `finalizeAccountDeletion(withSMSCode:)` after the user enters the code.
    func startAccountDeletionReauthentication(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("❌ No authenticated user found", category: "User")
            // Force UI back to Get Started if auth state is missing
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        guard let phoneNumber = user.phoneNumber, !phoneNumber.isEmpty else {
            DebugLogger.debug("❌ Current user does not have a phone number attached; cannot start phone re-auth", category: "User")
            completion(false)
            return
        }
        DebugLogger.debug("📲 Sending re-auth SMS for account deletion to: \(phoneNumber)", category: "User")
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("❌ Error sending verification SMS: \(error.localizedDescription)", category: "User")
                    self?.pendingDeletionVerificationID = nil
                    self?.isAwaitingDeletionSMSCode = false
                    completion(false)
                    return
                }
                self?.pendingDeletionVerificationID = verificationID
                self?.isAwaitingDeletionSMSCode = true
                DebugLogger.debug("✅ Verification ID received for deletion re-auth", category: "User")
                completion(true)
            }
        }
    }

    /// Completes re-authentication with the provided SMS code and deletes the account via backend.
    /// Note: With the new backend-based deletion, re-auth should rarely be needed since
    /// the server uses Admin SDK to delete Auth users directly.
    func finalizeAccountDeletion(withSMSCode smsCode: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("❌ No authenticated user found", category: "User")
            // Force UI back to Get Started if auth state is missing
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            isDeletingAccount = false
            completion(false)
            return
        }
        guard let verificationID = pendingDeletionVerificationID, !verificationID.isEmpty else {
            DebugLogger.debug("❌ No pending verification ID. Call startAccountDeletionReauthentication() first.", category: "User")
            isDeletingAccount = false
            completion(false)
            return
        }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: smsCode)
        DebugLogger.debug("🔐 Reauthenticating user for account deletion…", category: "User")
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error = error {
                DebugLogger.debug("❌ Re-authentication failed: \(error.localizedDescription)", category: "User")
                DispatchQueue.main.async {
                    self?.isDeletingAccount = false
                    self?.pendingDeletionVerificationID = nil
                    self?.isAwaitingDeletionSMSCode = false
                    completion(false)
                }
                return
            }
            DebugLogger.debug("✅ Re-authenticated. Calling backend to delete account...", category: "User")
            
            // After re-auth, call the same backend endpoint
            self?.pendingDeletionVerificationID = nil
            self?.isAwaitingDeletionSMSCode = false
            self?.deleteAccount(completion: completion)
        }
    }

    func deleteAccount(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("❌ No authenticated user found", category: "User")
            // Force UI back to Get Started if auth state is missing
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        // Clear UserDefaults flag for this user before deletion
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome_\(user.uid)")
        DebugLogger.debug("🧹 Cleared welcome popup flag for user: \(user.uid)", category: "User")

        // Mark that we're intentionally deleting to prevent listener interference
        isDeletingAccount = true
        
        // Stop all listeners BEFORE deletion to prevent errors
        stopUserListener()
        DebugLogger.debug("🛑 Stopped user listeners before deletion", category: "User")

        // Call backend endpoint to handle all deletion (Firestore + Auth) via Admin SDK
        // This bypasses App Check and permission issues entirely
        DebugLogger.debug("🗑️ Calling backend /user/delete-account endpoint...", category: "User")
        user.getIDToken { [weak self] token, error in
            if let error = error {
                DebugLogger.debug("❌ Failed to get ID token: \(error.localizedDescription)", category: "User")
                DispatchQueue.main.async {
                    self?.isDeletingAccount = false
                    completion(false)
                }
                return
            }
            
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/user/delete-account") else {
                DebugLogger.debug("❌ Invalid token or URL", category: "User")
                DispatchQueue.main.async {
                    self?.isDeletingAccount = false
                    completion(false)
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        DebugLogger.debug("❌ Delete account request failed: \(error.localizedDescription)", category: "User")
                        self?.isDeletingAccount = false
                        completion(false)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        DebugLogger.debug("❌ Invalid response from delete account endpoint", category: "User")
                        self?.isDeletingAccount = false
                        completion(false)
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        // Server successfully deleted everything including Auth user
                        DebugLogger.debug("✅ Backend deleted account successfully", category: "User")
                        self?.isDeletingAccount = false
                        // Sign out locally; skip FCM removal (user doc no longer exists)
                        self?.signOut(skipFCMRemoval: true)
                        completion(true)
                    } else {
                        // Parse error message from response
                        var errorMsg = "Delete account failed with status \(httpResponse.statusCode)"
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let msg = json["error"] as? String {
                            errorMsg = msg
                        }
                        DebugLogger.debug("❌ Delete account failed: \(errorMsg)", category: "User")
                        self?.isDeletingAccount = false
                        completion(false)
                    }
                }
            }.resume()
        }
    }
    
    // MARK: - Banned Account Deletion (with Archive)
    
    /// Archives banned user data to bannedAccountHistory collection, then deletes the account.
    /// This endpoint handles all Firestore cleanup server-side, so we only need to delete Auth locally.
    func archiveAndDeleteBannedAccount(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("❌ No authenticated user found", category: "User")
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        
        // Clear UserDefaults flag for this user before deletion
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome_\(user.uid)")
        DebugLogger.debug("🧹 Cleared welcome popup flag for user: \(user.uid)", category: "User")
        
        DebugLogger.debug("📦 Archiving banned account data via backend...", category: "User")
        
        // Get ID token and call the archive endpoint
        user.getIDToken { [weak self] token, error in
            if let error = error {
                DebugLogger.debug("❌ Failed to get ID token: \(error.localizedDescription)", category: "User")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/admin/banned-account-archive") else {
                DebugLogger.debug("❌ Invalid token or URL", category: "User")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DebugLogger.debug("❌ Archive request failed: \(error.localizedDescription)", category: "User")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    DebugLogger.debug("❌ Invalid response", category: "User")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    DebugLogger.debug("✅ Backend archive complete. Now deleting Auth user...", category: "User")
                    
                    // Delete the Firebase Auth user locally
                    user.delete { deleteError in
                        DispatchQueue.main.async {
                            if let deleteError = deleteError as NSError?,
                               deleteError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                                DebugLogger.debug("ℹ️ Recent login required. Starting SMS re-auth flow…", category: "User")
                                self?.startBannedAccountDeletionReauth { started in
                                    completion(started)
                                }
                                return
                            }
                            
                            if let deleteError = deleteError {
                                DebugLogger.debug("❌ Error deleting Auth user: \(deleteError.localizedDescription)", category: "User")
                                // Archive was successful but Auth deletion failed
                                // This is acceptable - user doc is already deleted
                                completion(false)
                                return
                            }
                            
                            DebugLogger.debug("✅ Auth user deleted successfully", category: "User")
                            completion(true)
                        }
                    }
                } else {
                    // Parse error message from response
                    var errorMsg = "Archive failed with status \(httpResponse.statusCode)"
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let msg = json["error"] as? String {
                        errorMsg = msg
                    }
                    DebugLogger.debug("❌ Archive failed: \(errorMsg)", category: "User")
                    DispatchQueue.main.async { completion(false) }
                }
            }.resume()
        }
    }
    
    /// Starts phone re-authentication specifically for banned account deletion.
    private func startBannedAccountDeletionReauth(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        guard let phoneNumber = user.phoneNumber, !phoneNumber.isEmpty else {
            DebugLogger.debug("❌ Current user does not have a phone number attached", category: "User")
            completion(false)
            return
        }
        DebugLogger.debug("📲 Sending re-auth SMS for banned account deletion to: \(phoneNumber)", category: "User")
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("❌ Error sending verification SMS: \(error.localizedDescription)", category: "User")
                    self?.pendingDeletionVerificationID = nil
                    self?.isAwaitingDeletionSMSCode = false
                    completion(false)
                    return
                }
                self?.pendingDeletionVerificationID = verificationID
                self?.isAwaitingDeletionSMSCode = true
                DebugLogger.debug("✅ Verification ID received for banned deletion re-auth", category: "User")
                completion(true)
            }
        }
    }
    
    /// Finalizes banned account deletion after SMS re-authentication.
    /// Called when user enters SMS code after archiveAndDeleteBannedAccount required re-auth.
    func finalizeBannedAccountDeletion(withSMSCode smsCode: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("❌ No authenticated user found", category: "User")
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        guard let verificationID = pendingDeletionVerificationID, !verificationID.isEmpty else {
            DebugLogger.debug("❌ No pending verification ID", category: "User")
            completion(false)
            return
        }
        
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: smsCode)
        DebugLogger.debug("🔐 Reauthenticating user for banned account deletion…", category: "User")
        
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error = error {
                DebugLogger.debug("❌ Re-authentication failed: \(error.localizedDescription)", category: "User")
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            DebugLogger.debug("✅ Re-authenticated. Now deleting Auth user…", category: "User")
            user.delete { deleteError in
                DispatchQueue.main.async {
                    self?.pendingDeletionVerificationID = nil
                    self?.isAwaitingDeletionSMSCode = false
                    
                    if let deleteError = deleteError {
                        DebugLogger.debug("❌ Error deleting Auth user: \(deleteError.localizedDescription)", category: "User")
                        completion(false)
                        return
                    }
                    DebugLogger.debug("✅ Auth user deleted successfully", category: "User")
                    completion(true)
                }
            }
        }
    }
    
    // MARK: - Testing Helper
    
    func resetWelcomePopupFlag() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome_\(uid)")
        DebugLogger.debug("🧹 Reset welcome popup flag for testing", category: "User")
    }

}
