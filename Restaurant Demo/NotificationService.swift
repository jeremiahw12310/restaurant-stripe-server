//
//  NotificationService.swift
//  Restaurant Demo
//
//  Handles Firebase Cloud Messaging (FCM) token management and push notification handling.
//

import Foundation
import FirebaseMessaging
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

/// Singleton service for managing push notifications and FCM tokens
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    @Published var fcmToken: String?
    @Published var hasNotificationPermission: Bool = false
    /// True while the system notification permission dialog is being shown (user tapped "Enable" in pre-prompt).
    @Published var isRequestingPermission: Bool = false
    /// True while the in-app pre-permission sheet is visible (so delayed closures can read current value).
    @Published var isPrePromptSheetVisible: Bool = false
    @Published var unreadNotificationCount: Int = 0
    @Published var notifications: [AppNotification] = []
    
    private let db = Firestore.firestore()
    private var notificationsListener: ListenerRegistration?
    private var hasRefreshedTokenThisSession = false // Prevent repeated token fetches
    private var isMarkingAllAsRead: Bool = false
    
    private override init() {
        super.init()
        // Set messaging delegate
        Messaging.messaging().delegate = self
    }
    
    // MARK: - Permission Request
    
    /// Request notification permissions from the user
    func requestNotificationPermission(completion: ((Bool) -> Void)? = nil) {
        isRequestingPermission = true
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isRequestingPermission = false
                self?.hasNotificationPermission = granted
                
                if let error = error {
                    DebugLogger.debug("❌ NotificationService: Permission request error: \(error.localizedDescription)", category: "Notifications")
                }
                
                if granted {
                    DebugLogger.debug("✅ NotificationService: Notification permission granted", category: "Notifications")
                    // Register for remote notifications on the main thread
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                    DebugLogger.debug("⚠️ NotificationService: Notification permission denied", category: "Notifications")
                }
                
                completion?(granted)
            }
        }
    }
    
    /// Check current notification permission status
    func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let granted = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                self?.hasNotificationPermission = granted
                completion(granted)
            }
        }
    }

    /// Get the full current notification authorization status (needed to detect `.notDetermined`)
    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }
    
    // MARK: - FCM Token Management
    
    /// Store FCM token via server endpoint (enables deduplication across users)
    func storeFCMToken(_ token: String) {
        guard let user = Auth.auth().currentUser else {
            DebugLogger.debug("⚠️ NotificationService: No authenticated user, cannot store FCM token", category: "Notifications")
            return
        }
        
        // Use server endpoint for token storage - this enables deduplication
        // to prevent notifications going to wrong device after account switch
        user.getIDToken { [weak self] idToken, error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to get ID token: \(error.localizedDescription)", category: "Notifications")
                // Fallback to direct Firestore write
                self?.storeFCMTokenDirectly(token, uid: user.uid)
                return
            }
            
            guard let idToken = idToken,
                  let url = URL(string: "\(Config.backendURL)/me/fcmToken") else {
                DebugLogger.debug("❌ NotificationService: Invalid URL or token", category: "Notifications")
                self?.storeFCMTokenDirectly(token, uid: user.uid)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = ["fcmToken": token]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.configured.dataTask(with: request) { data, response, error in
                if let error = error {
                    DebugLogger.debug("❌ NotificationService: Server FCM token store failed: \(error.localizedDescription)", category: "Notifications")
                    // Fallback to direct Firestore write
                    self?.storeFCMTokenDirectly(token, uid: user.uid)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DebugLogger.debug("✅ NotificationService: FCM token stored via server (with deduplication)", category: "Notifications")
                    DispatchQueue.main.async {
                        self?.fcmToken = token
                    }
                } else {
                    DebugLogger.debug("⚠️ NotificationService: Server returned non-200, falling back to direct write", category: "Notifications")
                    self?.storeFCMTokenDirectly(token, uid: user.uid)
                }
            }.resume()
        }
    }
    
    /// Fallback: Store FCM token directly in Firestore (no deduplication)
    private func storeFCMTokenDirectly(_ token: String, uid: String) {
        let userRef = db.collection("users").document(uid)
        userRef.updateData([
            "fcmToken": token,
            "hasFcmToken": true,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to store FCM token directly: \(error.localizedDescription)", category: "Notifications")
            } else {
                DebugLogger.debug("✅ NotificationService: FCM token stored directly (fallback)", category: "Notifications")
                DispatchQueue.main.async {
                    self?.fcmToken = token
                }
            }
        }
    }
    
    /// Remove FCM token via server endpoint (call on logout)
    func removeFCMToken() {
        guard let user = Auth.auth().currentUser else { return }
        
        // Use server endpoint for token removal
        user.getIDToken { [weak self] idToken, error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to get ID token for removal: \(error.localizedDescription)", category: "Notifications")
                self?.removeFCMTokenDirectly(uid: user.uid)
                return
            }
            
            guard let idToken = idToken,
                  let url = URL(string: "\(Config.backendURL)/me/fcmToken") else {
                self?.removeFCMTokenDirectly(uid: user.uid)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Send null to clear the token
            let body: [String: Any?] = ["fcmToken": nil]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.configured.dataTask(with: request) { data, response, error in
                if let error = error {
                    DebugLogger.debug("❌ NotificationService: Server FCM token removal failed: \(error.localizedDescription)", category: "Notifications")
                    self?.removeFCMTokenDirectly(uid: user.uid)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DebugLogger.debug("✅ NotificationService: FCM token removed via server", category: "Notifications")
                } else {
                    self?.removeFCMTokenDirectly(uid: user.uid)
                }
            }.resume()
        }
        
        DispatchQueue.main.async {
            self.fcmToken = nil
        }
    }
    
    /// Fallback: Remove FCM token directly from Firestore
    private func removeFCMTokenDirectly(uid: String) {
        let userRef = db.collection("users").document(uid)
        userRef.updateData([
            "fcmToken": FieldValue.delete(),
            "hasFcmToken": false,
            "fcmTokenUpdatedAt": FieldValue.delete()
        ]) { error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to remove FCM token directly: \(error.localizedDescription)", category: "Notifications")
            } else {
                DebugLogger.debug("✅ NotificationService: FCM token removed directly (fallback)", category: "Notifications")
            }
        }
    }
    
    /// Fetch and store current FCM token (call after login)
    func refreshAndStoreFCMToken() {
        // Only refresh once per session to prevent spam
        guard !hasRefreshedTokenThisSession else { return }
        hasRefreshedTokenThisSession = true
        
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Error fetching FCM token: \(error.localizedDescription)", category: "Notifications")
                return
            }

            if let token = token {
                DebugLogger.debug("✅ NotificationService: FCM token fetched", category: "Notifications")
                self?.storeFCMToken(token)
            }
        }
    }
    
    /// Reset the token refresh flag (call on logout)
    func resetTokenRefreshFlag() {
        hasRefreshedTokenThisSession = false
    }
    
    // MARK: - In-App Notifications
    
    /// Start listening for in-app notifications for the current user
    func startNotificationsListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // Stop any existing listener
        stopNotificationsListener()
        
        notificationsListener = db.collection("notifications")
            .whereField("userId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    DebugLogger.debug("❌ NotificationService: Notifications listener error: \(error.localizedDescription)", category: "Notifications")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self?.notifications = []
                        self?.unreadNotificationCount = 0
                    }
                    return
                }
                
                // Parse all notifications with error handling
                let allNotifications = documents.compactMap { doc -> AppNotification? in
                    let data = doc.data()
                    // Validate that data is actually a dictionary
                    guard data is [String: Any] else {
                        DebugLogger.debug("⚠️ NotificationService: Invalid data format for notification \(doc.documentID)", category: "Notifications")
                        return nil
                    }
                    // Safely create notification - init handles edge cases internally
                    return AppNotification(id: doc.documentID, data: data)
                }
                
                // Count unread notifications
                let unreadCount = allNotifications.filter { !$0.read }.count
                
                DispatchQueue.main.async {
                    self?.notifications = allNotifications
                    
                    // Only update count if we're not in the middle of marking all as read
                    if !(self?.isMarkingAllAsRead ?? false) {
                        self?.unreadNotificationCount = unreadCount
                        self?.updateAppBadge()
                    } else {
                        // During grace period: mark any unread notifications as read locally
                        // This prevents new notifications (like referral bonuses) from causing badge to reappear
                        let hasUnread = allNotifications.contains { !$0.read }
                        if hasUnread {
                            // Optimistically mark all as read locally
                            self?.notifications = allNotifications.map { notification in
                                AppNotification(
                                    id: notification.id,
                                    data: [
                                        "userId": notification.userId,
                                        "title": notification.title,
                                        "body": notification.body,
                                        "createdAt": notification.createdAt,
                                        "read": true,
                                        "type": notification.type.rawValue
                                    ]
                                )
                            }
                            // Also mark them as read in Firestore (fire-and-forget)
                            guard let self = self else { return }
                            for notification in allNotifications where !notification.read {
                                self.db.collection("notifications").document(notification.id).updateData(["read": true]) { _ in }
                            }
                        }
                    }
                }
            }
    }
    
    /// Stop listening for notifications
    func stopNotificationsListener() {
        notificationsListener?.remove()
        notificationsListener = nil
        DispatchQueue.main.async {
            self.notifications = []
            self.unreadNotificationCount = 0
            self.isMarkingAllAsRead = false // Clear flag in case operation was in progress
        }
    }
    
    /// Mark a notification as read
    func markNotificationAsRead(notificationId: String) {
        db.collection("notifications").document(notificationId).updateData([
            "read": true
        ]) { [weak self] error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to mark notification as read: \(error.localizedDescription)", category: "Notifications")
            } else {
                DispatchQueue.main.async {
                    self?.updateAppBadge()
                }
            }
        }
    }
    
    /// Mark all notifications as read for current user
    func markAllNotificationsAsRead() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // Optimistically update local state immediately to prevent flicker
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Set flag to prevent listener from overriding (on main thread for thread safety)
            self.isMarkingAllAsRead = true
            
            // Mark all notifications as read locally by creating new instances
            self.notifications = self.notifications.map { notification in
                var data: [String: Any] = [
                    "userId": notification.userId,
                    "title": notification.title,
                    "body": notification.body,
                    "createdAt": notification.createdAt,
                    "read": true,
                    "type": notification.type.rawValue
                ]
                if let rid = notification.reservationId { data["reservationId"] = rid }
                if let ph = notification.reservationPhone { data["phone"] = ph }
                return AppNotification(id: notification.id, data: data)
            }
            // Set count to 0 immediately
            self.unreadNotificationCount = 0
            self.updateAppBadge()
        }
        
        // Then update Firestore (listener will confirm the update)
        db.collection("notifications")
            .whereField("userId", isEqualTo: uid)
            .whereField("read", isEqualTo: false)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                // Handle errors explicitly
                if let error = error {
                    DebugLogger.debug("❌ NotificationService: Error fetching unread notifications: \(error.localizedDescription)", category: "Notifications")
                    DispatchQueue.main.async {
                        self.isMarkingAllAsRead = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self.isMarkingAllAsRead = false
                    }
                    return
                }
                
                let batch = self.db.batch()
                for doc in documents {
                    batch.updateData(["read": true], forDocument: doc.reference)
                }
                
                batch.commit { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        
                        if let error = error {
                            DebugLogger.debug("❌ NotificationService: Failed to mark all as read: \(error.localizedDescription)", category: "Notifications")
                            self.isMarkingAllAsRead = false
                        } else {
                            DebugLogger.debug("✅ NotificationService: All notifications marked as read", category: "Notifications")
                            
                            // Keep flag set for a grace period to catch notifications that arrive immediately after
                            // This prevents referral notifications (created by triggers) from causing badge to reappear
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.isMarkingAllAsRead = false
                            }
                        }
                    }
                }
            }
    }
    
    // MARK: - Notification Display
    
    /// Show a local notification banner when app is in foreground
    func showLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to show local notification: \(error.localizedDescription)", category: "Notifications")
            }
        }
    }
    
    // MARK: - Push Notification Tap Handling
    
    /// Handle when user taps on a push notification
    /// Marks all unread notifications as read and handles navigation based on notification type
    func handlePushNotificationTap(userInfo: [String: Any]) {
        DebugLogger.debug("📱 NotificationService: Handling push notification tap", category: "Notifications")
        markAllNotificationsAsRead()
        
        // Handle reward gift navigation
        if let type = userInfo["type"] as? String, type == "reward_gift",
           let giftedRewardId = userInfo["giftedRewardId"] as? String {
            DebugLogger.debug("🎁 NotificationService: Navigating to gifted reward: \(giftedRewardId)", category: "Notifications")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToGiftedReward,
                    object: nil,
                    userInfo: ["giftedRewardId": giftedRewardId]
                )
            }
        }
    }
    
    // MARK: - App Badge Management
    
    /// Update the app icon badge number based on unread notification count
    func updateAppBadge() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = self.unreadNotificationCount
            DebugLogger.debug("📱 NotificationService: Updated app badge to \(self.unreadNotificationCount)", category: "Notifications")
        }
    }
    
    // MARK: - Promotional Notification Preference
    
    /// Update user's promotional notification preference
    /// - Parameters:
    ///   - enabled: Whether to enable promotional notifications
    ///   - completion: Called with success status and optional error
    func updatePromotionalPreference(enabled: Bool, completion: @escaping (Bool, Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false, NSError(domain: "NotificationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]))
            return
        }
        
        let userRef = db.collection("users").document(uid)
        userRef.updateData([
            "promotionalNotificationsEnabled": enabled
        ]) { error in
            if let error = error {
                DebugLogger.debug("❌ NotificationService: Failed to update promotional preference: \(error.localizedDescription)", category: "Notifications")
                completion(false, error)
            } else {
                DebugLogger.debug("✅ NotificationService: Promotional preference updated to \(enabled)", category: "Notifications")
                completion(true, nil)
            }
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        DebugLogger.debug("🔔 NotificationService: FCM token received/refreshed", category: "Notifications")
        
        guard let token = fcmToken else {
            DebugLogger.debug("⚠️ NotificationService: FCM token is nil", category: "Notifications")
            return
        }
        
        // Store the new token
        storeFCMToken(token)
    }
}

// MARK: - Notification Model

struct AppNotification: Identifiable, Codable {
    let id: String
    let userId: String
    let title: String
    let body: String
    let createdAt: Date
    let read: Bool
    let type: NotificationType
    /// Set for reservation_new notifications; used for Confirm/Call actions.
    let reservationId: String?
    let reservationPhone: String?

    enum NotificationType: String, Codable {
        case adminBroadcast = "admin_broadcast"
        case adminIndividual = "admin_individual"
        case system = "system"
        case referral = "referral"
        case rewardGift = "reward_gift"
        case reservationNew = "reservation_new"
    }
    
    init(id: String, data: [String: Any]) {
        self.id = id
        
        // Safely extract fields with defensive checks
        if let userId = data["userId"] as? String {
            self.userId = userId
        } else if let userId = data["userId"] {
            // Handle any other type by converting to string
            self.userId = String(describing: userId)
        } else {
            self.userId = ""
        }
        
        if let title = data["title"] as? String {
            self.title = title
        } else if let title = data["title"] {
            self.title = String(describing: title)
        } else {
            self.title = ""
        }
        
        if let body = data["body"] as? String {
            self.body = body
        } else if let body = data["body"] {
            self.body = String(describing: body)
        } else {
            self.body = ""
        }
        
        // Safely extract read status
        if let read = data["read"] as? Bool {
            self.read = read
        } else {
            self.read = false
        }
        
        // Safely handle createdAt field - could be Timestamp or Date
        if let timestamp = data["createdAt"] as? Timestamp {
            self.createdAt = timestamp.dateValue()
        } else if let date = data["createdAt"] as? Date {
            self.createdAt = date
        } else {
            // Fallback if createdAt is missing or invalid
            self.createdAt = Date()
        }
        
        // Safely extract type
        if let typeString = data["type"] as? String,
           let type = NotificationType(rawValue: typeString) {
            self.type = type
        } else {
            self.type = .system
        }

        reservationId = data["reservationId"] as? String
        reservationPhone = data["phone"] as? String
    }
}
