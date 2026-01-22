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
    
    deinit {
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
            print("🔎 AUTH uid:", user.uid)
            print("🔎 AUTH phone:", user.phoneNumber ?? "nil")
        } else {
            print("🔎 AUTH user is nil")
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
                print("Error loading user data: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            // If the profile doc is missing, treat this as a corrupted session and return to logged-out UI.
            // This can happen if the Auth user exists but users/{uid} was deleted (or never created).
            if let snapshot = snapshot, snapshot.exists == false {
                print("❌ UserViewModel: users/\(uid) doc missing. Forcing logout to avoid half-signed-in state.")
                DispatchQueue.main.async {
                    self.isLoading = false
                    UserDefaults.standard.set(false, forKey: "isLoggedIn")
                    self.signOut()
                }
                return
            }

            guard let data = snapshot?.data(), !data.isEmpty else {
                print("No user data found.")
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
                
                // Check if user is banned - if so, sign them out immediately
                let isBanned = data["isBanned"] as? Bool ?? false
                if isBanned {
                    print("❌ UserViewModel: User is banned. Forcing logout.")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        UserDefaults.standard.set(false, forKey: "isLoggedIn")
                        // Show alert before signing out
                        self.showBannedAlert = true
                        // Sign out after a brief delay to allow alert to show
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.signOut()
                        }
                    }
                    return
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
                        print("🖼️ Loading profile image from URL: \(photoURL)")
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
                
                // Request notification permission if not yet granted (will show prompt on first login)
                NotificationService.shared.checkNotificationPermission { granted in
                    if !granted {
                        // Request permission on first login
                        NotificationService.shared.requestNotificationPermission()
                    }
                }

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
            print("❌ Cannot update oldReceiptTestingEnabled - no authenticated user")
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData([
            "oldReceiptTestingEnabled": enabled
        ]) { error in
            if let error = error {
                print("❌ Failed to update oldReceiptTestingEnabled: \(error.localizedDescription)")
            } else {
                print("✅ oldReceiptTestingEnabled updated to \(enabled) for user \(uid)")
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
                            print("❌ Failed to write referral award seen marker: \(error.localizedDescription)")
                            return
                        }
                        // Only post notification if transaction returned true (new, not already seen)
                        guard let shouldPost = result as? Bool, shouldPost else {
                            print("ℹ️ Referral award already seen, skipping popup")
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
            print("❌ No user ID for photo upload")
            completion(false)
            return
        }
        
        print("📤 Starting photo upload for user: \(uid)")
        isUploadingPhoto = true
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to compress image")
            isUploadingPhoto = false
            completion(false)
            return
        }
        
        print("📦 Image compressed, size: \(imageData.count) bytes")
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let photoRef = storageRef.child("profile_photos/\(uid).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        photoRef.putData(imageData, metadata: metadata) { metadata, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error uploading photo: \(error.localizedDescription)")
                    self.isUploadingPhoto = false
                    completion(false)
                    return
                }
                
                print("📤 Photo uploaded to Storage successfully")
                
                // Get download URL
                photoRef.downloadURL { url, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error getting download URL: \(error.localizedDescription)")
                            self.isUploadingPhoto = false
                            completion(false)
                            return
                        }
                        
                        if let downloadURL = url {
                            print("🔗 Got download URL: \(downloadURL.absoluteString)")
                            // Save URL to Firestore
                            self.saveProfilePhotoURL(downloadURL.absoluteString) { success in
                                self.isUploadingPhoto = false
                                if success {
                                    print("✅ Profile photo URL saved to Firestore")
                                    self.profilePhotoURL = downloadURL.absoluteString
                                    self.profileImage = image
                                    print("🖼️ Profile image updated locally: \(self.profileImage != nil)")
                                }
                                completion(success)
                            }
                        } else {
                            print("❌ Failed to get download URL")
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
                    print("Error saving photo URL: \(error.localizedDescription)")
                    completion(false)
                } else {
                    // Update all existing posts and replies to include the new profile photo URL
                    self.updateProfilePhotoInAllPosts(userId: uid, profilePhotoURL: url) { success in
                        if success {
                            print("✅ Successfully updated profile photo in all community posts")
                        } else {
                            print("⚠️ Failed to update some community posts with new profile photo")
                        }
                        completion(true) // Continue regardless of community update success
                    }
                }
            }
        }
    }
    
    private func loadProfileImage(from urlString: String) {
        guard let url = URL(string: urlString) else { 
            print("❌ Invalid URL: \(urlString)")
            return 
        }
        
        print("🖼️ Loading image from URL: \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let data = data, let image = UIImage(data: data) {
                    print("✅ Image loaded successfully, size: \(data.count) bytes")
                    self.profileImage = image
                    print("🖼️ Profile image set: \(self.profileImage != nil)")
                } else {
                    print("❌ Failed to create image from data")
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
                        print("Error deleting photo: \(error.localizedDescription)")
                    }
                    
                    // Remove from Firestore
                    let db = Firestore.firestore()
                    db.collection("users").document(uid).updateData([
                        "profilePhotoURL": FieldValue.delete()
                    ]) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("Error removing photo URL: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                self.profilePhotoURL = nil
                                self.profileImage = nil
                                
                                // Clear profile photo URL from all existing posts and replies
                                self.clearProfilePhotoFromAllPosts(userId: uid) { success in
                                    if success {
                                        print("✅ Successfully cleared profile photo from all community posts")
                                    } else {
                                        print("⚠️ Failed to clear some community posts")
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
        print("🔄 Force refreshing profile image")
        if let photoURL = profilePhotoURL {
            loadProfileImage(from: photoURL)
        } else {
            profileImage = nil
        }
    }
    
    func clearProfileImageCache() {
        print("🗑️ Clearing profile image cache")
        profileImage = nil
    }
    
    // MARK: - Community Post Updates
    
    func updateProfilePhotoInAllPosts(userId: String, profilePhotoURL: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Update all posts by this user
        db.collection("posts").whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching user posts: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("✅ No posts found for user")
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
                                print("❌ Error updating posts: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("✅ Successfully updated \(documents.count) posts for user")
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
        // Get all posts that have replies
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching posts for reply updates: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                print("✅ No posts found for reply updates")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        print("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)")
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
                            print("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            print("✅ Updated \(replyDocuments.count) replies for post \(postDoc.documentID)")
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
        
        // Update all posts by this user
        db.collection("posts").whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching user posts: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("✅ No posts found for user")
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
                                print("❌ Error updating posts: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("✅ Successfully cleared profile photo from \(documents.count) posts for user")
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
        // Get all posts that have replies
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching posts for reply updates: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                print("✅ No posts found for reply updates")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        print("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)")
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
                            print("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            print("✅ Cleared profile photo from \(replyDocuments.count) replies for post \(postDoc.documentID)")
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
        
        // Update all posts by this user
        db.collection("posts").whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching user posts: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("✅ No posts found for user")
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
                                print("❌ Error updating posts: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("✅ Successfully updated \(documents.count) posts with new avatar")
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
        // Get all posts that have replies
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching posts for reply updates: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                print("✅ No posts found for reply updates")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        print("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)")
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
                            print("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            print("✅ Updated \(replyDocuments.count) replies for post \(postDoc.documentID)")
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
                    print("❌ Error saving user preferences: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ User preferences saved successfully")
                    self.hasCompletedPreferences = true
                    completion(true)
                }
            }
        }
    }
    
    func signOut() {
        // FIXED: Clear all cached data when signing out to prevent storage bloat
        print("🧹 Clearing all cached data for account switch...")
        
        // Remove FCM token from Firestore before signing out
        NotificationService.shared.removeFCMToken()
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
        
        print("✅ All cached data cleared for account switch")
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
            print("🧹 Cleared \(clearedCount) UserDefaults entries during sign out")
        }
    }
    
    // MARK: - Welcome Points
    
    func addWelcomePoints(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            print("❌ No authenticated user found")
            completion(false)
            return
        }
        
        user.getIDToken { token, error in
            if let error = error {
                print("❌ Failed to get ID token for welcome claim: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard let token = token, let url = URL(string: "\(Config.backendURL)/welcome/claim") else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            
            URLSession.shared.dataTask(with: req) { data, resp, err in
                if let err = err {
                    print("❌ Welcome claim network error: \(err.localizedDescription)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    print("❌ Welcome claim failed (\(http.statusCode)): \(body)")
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                // Best-effort parse for immediate UI update; snapshot listener will also update.
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let newPoints = json["newPointsBalance"] as? Int { DispatchQueue.main.async { self.points = newPoints } }
                    if let newLifetime = json["newLifetimePoints"] as? Int { DispatchQueue.main.async { self.lifetimePoints = newLifetime } }
                    if let already = json["alreadyClaimed"] as? Bool, already == true {
                        print("ℹ️ Welcome points already claimed")
                    } else {
                        print("✅ Welcome points claimed server-side")
                    }
                }
                
                DispatchQueue.main.async { completion(true) }
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
            print("❌ No authenticated user found")
            // Force UI back to Get Started if auth state is missing
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        guard let phoneNumber = user.phoneNumber, !phoneNumber.isEmpty else {
            print("❌ Current user does not have a phone number attached; cannot start phone re-auth")
            completion(false)
            return
        }
        print("📲 Sending re-auth SMS for account deletion to: \(phoneNumber)")
        PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error sending verification SMS: \(error.localizedDescription)")
                    self?.pendingDeletionVerificationID = nil
                    self?.isAwaitingDeletionSMSCode = false
                    completion(false)
                    return
                }
                self?.pendingDeletionVerificationID = verificationID
                self?.isAwaitingDeletionSMSCode = true
                print("✅ Verification ID received for deletion re-auth")
                completion(true)
            }
        }
    }

    /// Completes re-authentication with the provided SMS code and deletes the Firebase Auth account and user data.
    func finalizeAccountDeletion(withSMSCode smsCode: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            print("❌ No authenticated user found")
            // Force UI back to Get Started if auth state is missing
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        guard let verificationID = pendingDeletionVerificationID, !verificationID.isEmpty else {
            print("❌ No pending verification ID. Call startAccountDeletionReauthentication() first.")
            completion(false)
            return
        }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: smsCode)
        print("🔐 Reauthenticating user for account deletion…")
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error = error {
                print("❌ Re-authentication failed: \(error.localizedDescription)")
                completion(false)
                return
            }
            print("✅ Re-authenticated. Deleting Firestore data FIRST (while still authenticated)…")
            
            // IMPORTANT: Delete Firestore data FIRST while user is still authenticated
            // Otherwise Firestore security rules will reject the deletion
            let storage = Storage.storage()
            self?.deleteUserDataFromFirestore(user: user, storage: storage) { firestoreSuccess in
                if firestoreSuccess {
                    print("✅ User data cleanup complete")
                } else {
                    print("⚠️ User data cleanup encountered errors (continuing with Auth deletion)")
                }
                
                // NOW delete the Auth user after Firestore cleanup
                print("🗑️ Now deleting Auth user…")
                user.delete { deleteError in
                    DispatchQueue.main.async {
                        self?.pendingDeletionVerificationID = nil
                        self?.isAwaitingDeletionSMSCode = false
                        
                        if let deleteError = deleteError {
                            print("❌ Error deleting Auth user: \(deleteError.localizedDescription)")
                            // Firestore data was deleted but Auth failed - still consider partial success
                            completion(false)
                            return
                        }
                        print("✅ Auth user deleted successfully")
                        completion(true)
                    }
                }
            }
        }
    }

    func deleteAccount(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            print("❌ No authenticated user found")
            // Force UI back to Get Started if auth state is missing
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
            completion(false)
            return
        }
        // Clear UserDefaults flag for this user before deletion
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome_\(user.uid)")
        print("🧹 Cleared welcome popup flag for user: \(user.uid)")

        // IMPORTANT: Delete Firestore data FIRST while user is still authenticated
        // Otherwise Firestore security rules will reject the deletion after Auth is deleted
        print("🗑️ Deleting Firestore data FIRST (while still authenticated)…")
        let storage = Storage.storage()
        self.deleteUserDataFromFirestore(user: user, storage: storage) { [weak self] firestoreSuccess in
            if firestoreSuccess {
                print("✅ User data cleanup complete")
            } else {
                print("⚠️ User data cleanup encountered errors (continuing with Auth deletion)")
            }
            
            // NOW delete the Auth user after Firestore cleanup
            print("🗑️ Now attempting to delete Auth user…")
            user.delete { error in
                if let error = error as NSError?, error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                    print("ℹ️ Recent login required. Starting SMS re-auth flow…")
                    self?.startAccountDeletionReauthentication { started in
                        completion(started) // UI should now collect SMS code and call finalizeAccountDeletion
                    }
                    return
                }
                if let error = error {
                    print("❌ Error deleting Auth user: \(error.localizedDescription)")
                    // Firestore data was already deleted, Auth deletion failed
                    completion(false)
                    return
                }
                print("✅ Auth user deleted successfully")
                completion(true)
            }
        }
    }
    
    private func deleteUserDataFromFirestore(user: User, storage: Storage, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let uid = user.uid

        // Best-effort cleanup of user-associated documents.
        // Note: Community content deletion (posts/replies) would be handled separately if needed.
        let group = DispatchGroup()
        var didFail = false

        func deleteWhereUserIdEquals(_ collection: String) {
            group.enter()
            db.collection(collection)
                .whereField("userId", isEqualTo: uid)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("⚠️ Could not query \(collection) for deletion: \(error.localizedDescription)")
                        didFail = true
                        group.leave()
                        return
                    }
                    let docs = snapshot?.documents ?? []
                    guard !docs.isEmpty else {
                        group.leave()
                        return
                    }

                    // Batch delete for efficiency (<= 500 ops). If you ever exceed, split into chunks.
                    let batch = db.batch()
                    for d in docs.prefix(450) {
                        batch.deleteDocument(d.reference)
                    }
                    batch.commit { batchError in
                        if let batchError = batchError {
                            print("⚠️ Failed deleting \(collection) docs: \(batchError.localizedDescription)")
                            didFail = true
                        } else {
                            print("✅ Deleted \(min(docs.count, 450)) docs from \(collection)")
                            if docs.count > 450 {
                                print("⚠️ More than 450 docs in \(collection); additional docs were not deleted in this pass.")
                                didFail = true
                            }
                        }
                        group.leave()
                    }
                }
        }

        // Delete per-user secondary data that commonly contains personal history
        deleteWhereUserIdEquals("pointsTransactions")
        deleteWhereUserIdEquals("redeemedRewards")

        // Delete the primary user profile document
        group.enter()
        db.collection("users").document(uid).delete { error in
            if let error = error {
                print("❌ Error deleting user data from Firestore: \(error.localizedDescription)")
                didFail = true
            } else {
                print("✅ User document deleted from Firestore")
            }
            group.leave()
        }

        // Delete profile photo from Storage if exists (best-effort)
        if let photoURL = self.profilePhotoURL {
            group.enter()
            let storageRef = storage.reference(forURL: photoURL)
            storageRef.delete { error in
                if let error = error {
                    print("⚠️ Warning: Could not delete profile photo from Storage: \(error.localizedDescription)")
                    didFail = true
                } else {
                    print("✅ Profile photo deleted from Storage")
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(!didFail)
        }
    }
    
    // MARK: - Testing Helper
    
    func resetWelcomePopupFlag() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome_\(uid)")
        print("🧹 Reset welcome popup flag for testing")
    }

}
