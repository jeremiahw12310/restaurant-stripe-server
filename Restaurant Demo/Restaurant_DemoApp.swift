import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseAppCheck
import FirebaseMessaging
import Kingfisher
import UserNotifications

// This is your main app entry point.
@main
struct Restaurant_DemoApp: App {
    
    // Register the custom app delegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var authVM = AuthenticationViewModel()

    var body: some Scene {
        WindowGroup {
            LaunchView()
                .environmentObject(authVM)
                .preferredColorScheme(.light) // Force light mode always
        }
    }
}

// An App Delegate to handle events like app launch and redirects.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 🚨 CRITICAL: Run emergency cleanup FIRST to prevent cache corruption crashes
        // This MUST run before ANY cache managers are accessed
        CacheEmergencyCleanup.performEmergencyCleanup()
        
        // Configure App Check provider BEFORE FirebaseApp.configure().
        //
        // - Local development (Xcode): use debug provider (no App Store receipt).
        // - TestFlight/App Store: use production provider (App Attest / DeviceCheck).
        //
        // This prevents TestFlight builds from ever attempting exchangeDebugToken,
        // and avoids "placeholder token" behavior that can break Firestore ops like account deletion.
        #if DEBUG
        if Bundle.main.appStoreReceiptURL == nil {
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        } else {
            AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
        }
        #else
        AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
        #endif

        // Configure Firebase when the app launches.
        FirebaseApp.configure()

        // 🔎 Push notification diagnostics (helps debug FCM/APNs linkage issues)
        let runtimeBundleId = Bundle.main.bundleIdentifier ?? "nil"
        DebugLogger.debug("Runtime Bundle ID: \(runtimeBundleId)", category: "Notifications")
        if let opts = FirebaseApp.app()?.options {
            DebugLogger.debug("FirebaseOptions.projectID: \(opts.projectID ?? "nil")", category: "Notifications")
            DebugLogger.debug("FirebaseOptions.gcmSenderID: \(opts.gcmSenderID ?? "nil")", category: "Notifications")
            DebugLogger.debug("FirebaseOptions.googleAppID: \(opts.googleAppID)", category: "Notifications")
        } else {
            DebugLogger.debug("FirebaseApp.app() is nil after configure()", category: "Notifications")
        }
        
        // Set up notification center delegate for handling notifications
        UNUserNotificationCenter.current().delegate = self

        // Register for remote notifications so Firebase Phone Auth can use APNs when available.
        // (This does NOT show a user-facing permission prompt by itself.)
        application.registerForRemoteNotifications()
        
        // Configure Kingfisher for better image loading
        configureKingfisher()
        
        // FIXED: Clear any existing video data from UserDefaults on app startup
        clearLegacyVideoData()
        
        // FIXED: Clear all potentially problematic UserDefaults data on app startup
        clearAllUserDefaultsData()
        
        // FIXED: Check and log UserDefaults storage usage
        checkUserDefaultsStorageUsage()
        
        return true
    }
    
    // Handle custom URL scheme: myapp://referral?code=XXXX
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Allow Firebase Auth (reCAPTCHA / phone auth) to handle callback URLs first
        if Auth.auth().canHandle(url) {
            return true
        }
        let scheme = url.scheme?.lowercased() ?? ""
        guard !scheme.isEmpty else { return false }
        // Accept any scheme; validate host path
        let host = url.host?.lowercased() ?? ""
        if host == "referral" {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let codeItem = comps.queryItems?.first(where: { $0.name.lowercased() == "code" }),
               let code = codeItem.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty {
                // Persist so the code isn't lost during login/navigation
                ReferralDeepLinkStore.setPending(code: code)
                NotificationCenter.default.post(name: Notification.Name("incomingReferralCode"), object: nil, userInfo: ["code": code])
                return true
            }
        }
        return false
    }

    // Handle Universal Links: https://dumplinghouseapp.com/refer?code=XXXX
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }

        guard let host = url.host?.lowercased(), host.contains("dumplinghouseapp.com") else {
            return false
        }

        let path = url.path.lowercased()
        guard path.hasPrefix("/refer") || path.hasPrefix("/referral") else {
            return false
        }

        var code: String? = nil
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let item = comps.queryItems?.first(where: { $0.name.lowercased() == "code" }),
           let v = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !v.isEmpty {
            code = v
        } else {
            let last = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !last.isEmpty, last.lowercased() != "refer", last.lowercased() != "referral" {
                code = last
            }
        }

        guard let finalCode = code, !finalCode.isEmpty else {
            return false
        }

        ReferralDeepLinkStore.setPending(code: finalCode)
        NotificationCenter.default.post(name: Notification.Name("incomingReferralCode"), object: nil, userInfo: ["code": finalCode])
        return true
    }
    
    private func configureKingfisher() {
        // FIXED: Configure Kingfisher to prevent storage bloat
        KingfisherManager.shared.defaultOptions = [
            .cacheMemoryOnly,
            .processor(DownsamplingImageProcessor(size: CGSize(width: 120, height: 120))), // FIXED: Further reduced to prevent storage bloat
            .scaleFactor(UIScreen.main.scale),
            .cacheSerializer(FormatIndicatedCacheSerializer.png),
            .backgroundDecode
        ]
        
        // FIXED: Set up custom cache configuration to prevent storage bloat
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 15 * 1024 * 1024 // FIXED: Reduced to 15MB to prevent storage bloat
        cache.diskStorage.config.sizeLimit = 30 * 1024 * 1024 // FIXED: Reduced to 30MB to prevent storage bloat
        
        // FIXED: Set cache expiration to prevent storage bloat
        cache.memoryStorage.config.expiration = .seconds(120) // FIXED: Reduced to 2 minutes
        cache.diskStorage.config.expiration = .days(1) // FIXED: Reduced to 1 day
        
        DebugLogger.debug("Kingfisher configured to prevent storage bloat", category: "App")
    }
    
    // FIXED: Clear legacy video data that might have been stored before the fix
    private func clearLegacyVideoData() {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys
        var clearedCount = 0
        
        for key in keys {
            if key.contains("videos_") {
                userDefaults.removeObject(forKey: key)
                clearedCount += 1
            }
        }
        
        if clearedCount > 0 {
            DebugLogger.debug("Cleared \(clearedCount) legacy video data entries from UserDefaults", category: "App")
        }
    }
    
    // FIXED: Clear all potentially problematic UserDefaults data
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
               key.contains("menuItems_") {
                userDefaults.removeObject(forKey: key)
                clearedCount += 1
            }
        }
        
        if clearedCount > 0 {
            DebugLogger.debug("Cleared \(clearedCount) potentially problematic UserDefaults entries", category: "App")
        }
    }
    
    // FIXED: Add method to check UserDefaults storage usage
    private func checkUserDefaultsStorageUsage() {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys
        var totalSize: Int64 = 0
        var keySizes: [(String, Int64)] = []
        
        for key in keys {
            if let data = userDefaults.data(forKey: key) {
                let size = Int64(data.count)
                totalSize += size
                keySizes.append((key, size))
            }
        }
        
        // Sort by size (largest first)
        keySizes.sort { $0.1 > $1.1 }
        
        DebugLogger.debug("UserDefaults Storage Usage: \(formatBytes(totalSize))", category: "App")
        DebugLogger.debug("Top 10 largest keys:", category: "App")
        for (key, size) in keySizes.prefix(10) {
            DebugLogger.debug("  \(key): \(formatBytes(size))", category: "App")
        }
        
        // Alert if total size is too large
        if totalSize > 50 * 1024 * 1024 { // 50MB
            DebugLogger.debug("UserDefaults storage usage is high: \(formatBytes(totalSize))", category: "App")
        }
    }
    
    // FIXED: Helper method to format bytes
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    

    

    
    // MARK: - Remote Notification Methods for Firebase Auth & FCM
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Set the APNs device token for Firebase Auth
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
        
        // Also set the APNs token for Firebase Cloud Messaging
        Messaging.messaging().apnsToken = deviceToken
        DebugLogger.debug("APNs token set for FCM", category: "Notifications")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DebugLogger.debug("Failed to register for remote notifications: \(error.localizedDescription)", category: "App")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle remote notification for Firebase Auth
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        
        // Handle FCM data messages in the background
        DebugLogger.debug("Received remote notification: \(userInfo)", category: "Notifications")
        completionHandler(.newData)
    }
    
    // MARK: - UNUserNotificationCenterDelegate Methods
    
    /// Handle notifications when app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        DebugLogger.debug("Notification received in foreground: \(userInfo)", category: "Notifications")
        
        // Show the notification as a banner even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification tap (when user taps on a notification)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        DebugLogger.debug("Notification tapped: \(userInfo)", category: "Notifications")
        
        // Post notification for app to handle navigation if needed
        NotificationCenter.default.post(
            name: Notification.Name("didTapPushNotification"),
            object: nil,
            userInfo: userInfo as? [String: Any]
        )
        
        completionHandler()
    }
    
    /// Sync app badge when app becomes active (launch or foreground)
    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationService.shared.updateAppBadge()
    }
    
    // FIXED: Add memory warning handling to prevent storage bloat
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        DebugLogger.debug("App memory warning received - clearing all caches", category: "App")
        
        // Clear all image caches
        ImageCache.default.clearMemoryCache()
        ImageCache.default.clearDiskCache()
        
        // Performance: Clear menu and promo image memory caches on memory warning
        MenuImageCacheManager.shared.clearMemoryCache()
        PromoImageCacheManager.shared.clearMemoryCache()
        
        // Clear UserDefaults video data (if any exists from before the fix)
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys
        for key in keys {
            if key.contains("videos_") {
                userDefaults.removeObject(forKey: key)
                DebugLogger.debug("Cleared video data from UserDefaults: \(key)", category: "App")
            }
        }
        
        // Clear all potentially problematic UserDefaults data
        clearAllUserDefaultsData()
        
        DebugLogger.debug("All caches cleared to prevent storage bloat", category: "App")
    }
}

/// Production App Check provider factory for TestFlight/App Store builds.
/// Uses App Attest when available, otherwise falls back to DeviceCheck.
final class ProductionAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        } else {
            return DeviceCheckProvider(app: app)
        }
    }
}
