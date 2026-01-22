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
    @Published var unreadNotificationCount: Int = 0
    @Published var notifications: [AppNotification] = []
    
    private let db = Firestore.firestore()
    private var notificationsListener: ListenerRegistration?
    private var hasRefreshedTokenThisSession = false // Prevent repeated token fetches
    
    private override init() {
        super.init()
        // Set messaging delegate
        Messaging.messaging().delegate = self
    }
    
    // MARK: - Permission Request
    
    /// Request notification permissions from the user
    func requestNotificationPermission(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasNotificationPermission = granted
                
                if let error = error {
                    print("❌ NotificationService: Permission request error: \(error.localizedDescription)")
                }
                
                if granted {
                    print("✅ NotificationService: Notification permission granted")
                    // Register for remote notifications on the main thread
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                    print("⚠️ NotificationService: Notification permission denied")
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
    
    // MARK: - FCM Token Management
    
    /// Store FCM token via server endpoint (enables deduplication across users)
    func storeFCMToken(_ token: String) {
        guard let user = Auth.auth().currentUser else {
            print("⚠️ NotificationService: No authenticated user, cannot store FCM token")
            return
        }
        
        // Use server endpoint for token storage - this enables deduplication
        // to prevent notifications going to wrong device after account switch
        user.getIDToken { [weak self] idToken, error in
            if let error = error {
                print("❌ NotificationService: Failed to get ID token: \(error.localizedDescription)")
                // Fallback to direct Firestore write
                self?.storeFCMTokenDirectly(token, uid: user.uid)
                return
            }
            
            guard let idToken = idToken,
                  let url = URL(string: "\(Config.backendURL)/me/fcmToken") else {
                print("❌ NotificationService: Invalid URL or token")
                self?.storeFCMTokenDirectly(token, uid: user.uid)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = ["fcmToken": token]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ NotificationService: Server FCM token store failed: \(error.localizedDescription)")
                    // Fallback to direct Firestore write
                    self?.storeFCMTokenDirectly(token, uid: user.uid)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("✅ NotificationService: FCM token stored via server (with deduplication)")
                    DispatchQueue.main.async {
                        self?.fcmToken = token
                    }
                } else {
                    print("⚠️ NotificationService: Server returned non-200, falling back to direct write")
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
                print("❌ NotificationService: Failed to store FCM token directly: \(error.localizedDescription)")
            } else {
                print("✅ NotificationService: FCM token stored directly (fallback)")
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
                print("❌ NotificationService: Failed to get ID token for removal: \(error.localizedDescription)")
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
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ NotificationService: Server FCM token removal failed: \(error.localizedDescription)")
                    self?.removeFCMTokenDirectly(uid: user.uid)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("✅ NotificationService: FCM token removed via server")
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
                print("❌ NotificationService: Failed to remove FCM token directly: \(error.localizedDescription)")
            } else {
                print("✅ NotificationService: FCM token removed directly (fallback)")
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
                print("❌ NotificationService: Error fetching FCM token: \(error.localizedDescription)")
                return
            }

            if let token = token {
                print("✅ NotificationService: FCM token fetched")
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
                    print("❌ NotificationService: Notifications listener error: \(error.localizedDescription)")
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
                        print("⚠️ NotificationService: Invalid data format for notification \(doc.documentID)")
                        return nil
                    }
                    // Safely create notification - init handles edge cases internally
                    return AppNotification(id: doc.documentID, data: data)
                }
                
                // Count unread notifications
                let unreadCount = allNotifications.filter { !$0.read }.count
                
                DispatchQueue.main.async {
                    self?.notifications = allNotifications
                    self?.unreadNotificationCount = unreadCount
                    self?.updateAppBadge()
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
        }
    }
    
    /// Mark a notification as read
    func markNotificationAsRead(notificationId: String) {
        db.collection("notifications").document(notificationId).updateData([
            "read": true
        ]) { [weak self] error in
            if let error = error {
                print("❌ NotificationService: Failed to mark notification as read: \(error.localizedDescription)")
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
        
        db.collection("notifications")
            .whereField("userId", isEqualTo: uid)
            .whereField("read", isEqualTo: false)
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                let batch = self?.db.batch()
                for doc in documents {
                    batch?.updateData(["read": true], forDocument: doc.reference)
                }
                
                batch?.commit { [weak self] error in
                    if let error = error {
                        print("❌ NotificationService: Failed to mark all as read: \(error.localizedDescription)")
                    } else {
                        print("✅ NotificationService: All notifications marked as read")
                        DispatchQueue.main.async {
                            self?.updateAppBadge()
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
                print("❌ NotificationService: Failed to show local notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Push Notification Tap Handling
    
    /// Handle when user taps on a push notification
    /// Marks all unread notifications as read (since push payloads don't include Firestore document IDs)
    func handlePushNotificationTap(userInfo: [String: Any]) {
        print("📱 NotificationService: Handling push notification tap")
        markAllNotificationsAsRead()
    }
    
    // MARK: - App Badge Management
    
    /// Update the app icon badge number based on unread notification count
    func updateAppBadge() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = self.unreadNotificationCount
            print("📱 NotificationService: Updated app badge to \(self.unreadNotificationCount)")
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔔 NotificationService: FCM token received/refreshed")
        
        guard let token = fcmToken else {
            print("⚠️ NotificationService: FCM token is nil")
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
    
    enum NotificationType: String, Codable {
        case adminBroadcast = "admin_broadcast"
        case adminIndividual = "admin_individual"
        case system = "system"
        case referral = "referral"
        case rewardGift = "reward_gift"
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
    }
}
