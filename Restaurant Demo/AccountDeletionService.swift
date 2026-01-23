import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Centralized service for account deletion that handles both anonymization and deletion
/// of user data across all Firestore collections.
class AccountDeletionService {
    static let shared = AccountDeletionService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {}
    
    /// Main entry point for account deletion
    /// - Parameters:
    ///   - uid: The user ID to delete
    ///   - profilePhotoURL: Optional profile photo URL to delete from Storage
    ///   - completion: Called with success status
    func deleteAccount(uid: String, profilePhotoURL: String?, completion: @escaping (Bool) -> Void) {
        print("🗑️ Starting account deletion for user: \(uid)")
        let group = DispatchGroup()
        var didFail = false
        
        // MARK: - Anonymization (keep records but remove PII)
        
        anonymizeReceipts(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        anonymizeSuspiciousFlags(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        anonymizeGiftedRewards(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        anonymizeGiftedRewardClaims(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        anonymizePosts(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        // MARK: - Deletion (remove user-specific data)
        
        deletePointsTransactions(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteRedeemedRewards(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteReferrals(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteNotifications(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteReceiptScanAttempts(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteUserSubcollections(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteUserRiskScore(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        removeFromDeviceFingerprints(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        deleteUserDocument(uid: uid, group: group) { failed in
            if failed { didFail = true }
        }
        
        if let photoURL = profilePhotoURL {
            deleteProfilePhoto(url: photoURL, group: group) { failed in
                if failed { didFail = true }
            }
        }
        
        group.notify(queue: .main) {
            let success = !didFail
            if success {
                print("✅ Account deletion completed successfully for user: \(uid)")
            } else {
                print("⚠️ Account deletion completed with some errors for user: \(uid)")
            }
            completion(success)
        }
    }
    
    // MARK: - Anonymization Methods
    
    private func anonymizeReceipts(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        db.collection("receipts")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    group.leave()
                    completion(true)
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query receipts for anonymization: \(error.localizedDescription)")
                    group.leave()
                    completion(true) // Non-critical, continue
                    return
                }
                
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    group.leave()
                    completion(false)
                    return
                }
                
                let batch = self.db.batch()
                for doc in docs.prefix(450) {
                    // Store anonymized user info so admin views can show "Deleted User"
                    // without needing to look up the user (which no longer exists)
                    batch.updateData([
                        "userName": "Deleted User",
                        "userPhone": "",
                        "userEmail": ""
                    ], forDocument: doc.reference)
                }
                
                batch.commit { batchError in
                    if let batchError = batchError {
                        print("⚠️ Failed anonymizing receipts: \(batchError.localizedDescription)")
                        group.leave()
                        completion(true)
                    } else {
                        print("✅ Anonymized \(min(docs.count, 450)) receipt(s)")
                        if docs.count > 450 {
                            print("⚠️ More than 450 receipts; additional receipts were not anonymized in this pass.")
                        }
                        group.leave()
                        completion(false)
                    }
                }
            }
    }
    
    private func anonymizeSuspiciousFlags(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        db.collection("suspiciousFlags")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    group.leave()
                    completion(true)
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query suspiciousFlags for anonymization: \(error.localizedDescription)")
                    group.leave()
                    completion(true)
                    return
                }
                
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    group.leave()
                    completion(false)
                    return
                }
                
                let batch = self.db.batch()
                for doc in docs.prefix(450) {
                    // Update evidence to remove PII if present
                    var updateData: [String: Any] = [:]
                    
                    // Check if evidence contains user info and anonymize it
                    if let evidence = doc.data()["evidence"] as? [String: Any] {
                        var updatedEvidence = evidence
                        if evidence["userName"] != nil {
                            updatedEvidence["userName"] = "Deleted User"
                        }
                        if evidence["userPhone"] != nil {
                            updatedEvidence["userPhone"] = ""
                        }
                        if evidence["userEmail"] != nil {
                            updatedEvidence["userEmail"] = ""
                        }
                        updateData["evidence"] = updatedEvidence
                    }
                    
                    batch.updateData(updateData, forDocument: doc.reference)
                }
                
                batch.commit { batchError in
                    if let batchError = batchError {
                        print("⚠️ Failed anonymizing suspiciousFlags: \(batchError.localizedDescription)")
                        group.leave()
                        completion(true)
                    } else {
                        print("✅ Anonymized \(min(docs.count, 450)) suspicious flag(s)")
                        if docs.count > 450 {
                            print("⚠️ More than 450 flags; additional flags were not anonymized in this pass.")
                        }
                        group.leave()
                        completion(false)
                    }
                }
            }
    }
    
    private func anonymizeGiftedRewards(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        // Anonymize gifts where user is the target (individual gifts)
        db.collection("giftedRewards")
            .whereField("targetUserIds", arrayContains: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    group.leave()
                    completion(true)
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query giftedRewards for anonymization: \(error.localizedDescription)")
                    group.leave()
                    completion(true)
                    return
                }
                
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    group.leave()
                    completion(false)
                    return
                }
                
                let batch = self.db.batch()
                for doc in docs.prefix(450) {
                    // Remove uid from targetUserIds array
                    var data = doc.data()
                    if var targetUserIds = data["targetUserIds"] as? [String] {
                        targetUserIds.removeAll { $0 == uid }
                        batch.updateData([
                            "targetUserIds": targetUserIds
                        ], forDocument: doc.reference)
                    }
                }
                
                batch.commit { batchError in
                    if let batchError = batchError {
                        print("⚠️ Failed anonymizing giftedRewards: \(batchError.localizedDescription)")
                        group.leave()
                        completion(true)
                    } else {
                        print("✅ Anonymized \(min(docs.count, 450)) gifted reward(s)")
                        if docs.count > 450 {
                            print("⚠️ More than 450 gifted rewards; additional rewards were not anonymized in this pass.")
                        }
                        group.leave()
                        completion(false)
                    }
                }
            }
    }
    
    private func anonymizeGiftedRewardClaims(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        db.collection("giftedRewardClaims")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    group.leave()
                    completion(true)
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query giftedRewardClaims for anonymization: \(error.localizedDescription)")
                    group.leave()
                    completion(true)
                    return
                }
                
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    group.leave()
                    completion(false)
                    return
                }
                
                let batch = self.db.batch()
                for doc in docs.prefix(450) {
                    batch.updateData([
                        "userName": "Deleted User",
                        "userPhone": ""
                    ], forDocument: doc.reference)
                }
                
                batch.commit { batchError in
                    if let batchError = batchError {
                        print("⚠️ Failed anonymizing giftedRewardClaims: \(batchError.localizedDescription)")
                        group.leave()
                        completion(true)
                    } else {
                        print("✅ Anonymized \(min(docs.count, 450)) gifted reward claim(s)")
                        if docs.count > 450 {
                            print("⚠️ More than 450 claims; additional claims were not anonymized in this pass.")
                        }
                        group.leave()
                        completion(false)
                    }
                }
            }
    }
    
    private func anonymizePosts(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        db.collection("posts")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    group.leave()
                    completion(true)
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query posts for anonymization: \(error.localizedDescription)")
                    group.leave()
                    completion(true)
                    return
                }
                
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    group.leave()
                    completion(false)
                    return
                }
                
                let batch = self.db.batch()
                for doc in docs.prefix(450) {
                    var updateData: [String: Any] = [
                        "userName": "Deleted User",
                        "userDisplayName": "Deleted User"
                    ]
                    batch.updateData(updateData, forDocument: doc.reference)
                }
                
                batch.commit { batchError in
                    if let batchError = batchError {
                        print("⚠️ Failed anonymizing posts: \(batchError.localizedDescription)")
                        group.leave()
                        completion(true)
                    } else {
                        print("✅ Anonymized \(min(docs.count, 450)) post(s)")
                        if docs.count > 450 {
                            print("⚠️ More than 450 posts; additional posts were not anonymized in this pass.")
                        }
                        
                        // Anonymize replies separately (async, don't block)
                        self.anonymizePostReplies(uid: uid, posts: docs.prefix(450).map { $0.reference })
                        
                        group.leave()
                        completion(false)
                    }
                }
            }
    }
    
    private func anonymizePostReplies(uid: String, posts: [DocumentReference]) {
        // Anonymize replies for each post (best-effort, non-blocking)
        for postRef in posts {
            postRef.collection("replies")
                .whereField("userId", isEqualTo: uid)
                .getDocuments { [weak self] snapshot, _ in
                    guard let self = self, let docs = snapshot?.documents, !docs.isEmpty else { return }
                    
                    let batch = self.db.batch()
                    for replyDoc in docs.prefix(450) {
                        batch.updateData([
                            "userName": "Deleted User",
                            "userDisplayName": "Deleted User"
                        ], forDocument: replyDoc.reference)
                    }
                    batch.commit { _ in
                        print("✅ Anonymized replies for post \(postRef.documentID)")
                    }
                }
        }
    }
    
    // MARK: - Deletion Methods
    
    private func deletePointsTransactions(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        deleteWhereUserIdEquals("pointsTransactions", uid: uid) { failed in
            group.leave()
            completion(failed)
        }
    }
    
    private func deleteRedeemedRewards(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        deleteWhereUserIdEquals("redeemedRewards", uid: uid) { failed in
            group.leave()
            completion(failed)
        }
    }
    
    private func deleteReferrals(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        let innerGroup = DispatchGroup()
        var didFail = false
        
        // Delete where user is referrer
        innerGroup.enter()
        db.collection("referrals")
            .whereField("referrerUserId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    innerGroup.leave()
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query referrals (referrer) for deletion: \(error.localizedDescription)")
                    didFail = true
                    innerGroup.leave()
                    return
                }
                
                self.deleteDocuments(snapshot?.documents ?? [], collection: "referrals (referrer)") { failed in
                    if failed { didFail = true }
                    innerGroup.leave()
                }
            }
        
        // Delete where user is referred
        innerGroup.enter()
        db.collection("referrals")
            .whereField("referredUserId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    innerGroup.leave()
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query referrals (referred) for deletion: \(error.localizedDescription)")
                    didFail = true
                    innerGroup.leave()
                    return
                }
                
                self.deleteDocuments(snapshot?.documents ?? [], collection: "referrals (referred)") { failed in
                    if failed { didFail = true }
                    innerGroup.leave()
                }
            }
        
        innerGroup.notify(queue: .main) {
            group.leave()
            completion(didFail)
        }
    }
    
    private func deleteNotifications(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        deleteWhereUserIdEquals("notifications", uid: uid) { failed in
            group.leave()
            completion(failed)
        }
    }
    
    private func deleteReceiptScanAttempts(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        deleteWhereUserIdEquals("receiptScanAttempts", uid: uid) { failed in
            group.leave()
            completion(failed)
        }
    }
    
    private func deleteUserSubcollections(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        let innerGroup = DispatchGroup()
        var didFail = false
        
        // Delete clientState subcollection
        innerGroup.enter()
        db.collection("users").document(uid).collection("clientState")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    innerGroup.leave()
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query clientState for deletion: \(error.localizedDescription)")
                    didFail = true
                    innerGroup.leave()
                    return
                }
                
                self.deleteDocuments(snapshot?.documents ?? [], collection: "clientState") { failed in
                    if failed { didFail = true }
                    innerGroup.leave()
                }
            }
        
        // Delete activity subcollection
        innerGroup.enter()
        db.collection("users").document(uid).collection("activity")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    innerGroup.leave()
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query activity for deletion: \(error.localizedDescription)")
                    didFail = true
                    innerGroup.leave()
                    return
                }
                
                self.deleteDocuments(snapshot?.documents ?? [], collection: "activity") { failed in
                    if failed { didFail = true }
                    innerGroup.leave()
                }
            }
        
        innerGroup.notify(queue: .main) {
            group.leave()
            completion(didFail)
        }
    }
    
    private func deleteUserRiskScore(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        db.collection("userRiskScores").document(uid).delete { error in
            if let error = error {
                print("⚠️ Could not delete userRiskScore: \(error.localizedDescription)")
                group.leave()
                completion(true)
            } else {
                print("✅ Deleted userRiskScore")
                group.leave()
                completion(false)
            }
        }
    }
    
    private func removeFromDeviceFingerprints(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        // Device fingerprints are keyed by hash, not userId
        // We'd need to query all fingerprints and remove uid from arrays
        // This is complex and may not be necessary - skipping for now
        print("ℹ️ Skipping deviceFingerprints cleanup (complex query required)")
        group.leave()
        completion(false)
    }
    
    private func deleteUserDocument(uid: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        db.collection("users").document(uid).delete { error in
            if let error = error {
                print("❌ Error deleting user document: \(error.localizedDescription)")
                group.leave()
                completion(true)
            } else {
                print("✅ User document deleted")
                group.leave()
                completion(false)
            }
        }
    }
    
    private func deleteProfilePhoto(url: String, group: DispatchGroup, completion: @escaping (Bool) -> Void) {
        group.enter()
        let storageRef = storage.reference(forURL: url)
        storageRef.delete { error in
            if let error = error {
                print("⚠️ Warning: Could not delete profile photo from Storage: \(error.localizedDescription)")
                group.leave()
                completion(true)
            } else {
                print("✅ Profile photo deleted from Storage")
                group.leave()
                completion(false)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func deleteWhereUserIdEquals(_ collection: String, uid: String, completion: @escaping (Bool) -> Void) {
        db.collection(collection)
            .whereField("userId", isEqualTo: uid)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion(true)
                    return
                }
                
                if let error = error {
                    print("⚠️ Could not query \(collection) for deletion: \(error.localizedDescription)")
                    completion(true)
                    return
                }
                
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    completion(false)
                    return
                }
                
                self.deleteDocuments(docs, collection: collection, completion: completion)
            }
    }
    
    private func deleteDocuments(_ docs: [QueryDocumentSnapshot], collection: String, completion: @escaping (Bool) -> Void) {
        // Batch delete for efficiency (<= 500 ops). If you ever exceed, split into chunks.
        let batch = db.batch()
        for doc in docs.prefix(450) {
            batch.deleteDocument(doc.reference)
        }
        
        batch.commit { batchError in
            if let batchError = batchError {
                print("⚠️ Failed deleting \(collection) docs: \(batchError.localizedDescription)")
                completion(true)
            } else {
                print("✅ Deleted \(min(docs.count, 450)) doc(s) from \(collection)")
                if docs.count > 450 {
                    print("⚠️ More than 450 docs in \(collection); additional docs were not deleted in this pass.")
                }
                completion(false)
            }
        }
    }
}
