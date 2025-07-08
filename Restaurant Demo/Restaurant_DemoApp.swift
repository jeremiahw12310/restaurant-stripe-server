import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseAppCheck
import Kingfisher

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
                .preferredColorScheme(.dark) // Force dark mode
        }
    }
}

// An App Delegate to handle events like app launch and redirects.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Add App Check debug provider for development
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif
        // Configure Firebase when the app launches.
        FirebaseApp.configure()
        
        // Configure Kingfisher for better image loading
        configureKingfisher()
        
        return true
    }
    
    private func configureKingfisher() {
        // Configure Kingfisher for better performance with Firebase Storage
        KingfisherManager.shared.defaultOptions = [
            .cacheMemoryOnly,
            .forceTransition,
            .processor(DownsamplingImageProcessor(size: CGSize(width: 300, height: 300))),
            .scaleFactor(UIScreen.main.scale),
            .alsoPrefetchToMemory,
            .cacheSerializer(FormatIndicatedCacheSerializer.png)
        ]
        
        // Set up custom cache configuration
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024 // 50MB
        cache.diskStorage.config.sizeLimit = 100 * 1024 * 1024 // 100MB
        
        print("✅ Kingfisher configured for Firebase Storage")
    }
    
    // This function handles the redirect URL from Stripe Checkout.
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // You can add logic here to check if the payment was successful
        // based on the URL returned by Stripe. For now, we just print it.
        print("Redirected back to app with URL: \(url)")
        
        // After payment, you might want to clear the cart or show a thank you message.
        // This part can be expanded with more advanced state management.
        
        return true
    }
    
    // MARK: - Remote Notification Methods for Firebase Auth
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Set the APNs device token for Firebase Auth
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle remote notification for Firebase Auth
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        
        // Handle other remote notifications if needed
        completionHandler(.noData)
    }
}
