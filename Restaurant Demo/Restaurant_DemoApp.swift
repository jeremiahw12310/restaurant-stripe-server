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
    @StateObject var stripeManager = StripeCheckoutManager.shared
    @State private var showOrderStatus = false

    var body: some Scene {
        WindowGroup {
            LaunchView()
                .environmentObject(authVM)
                .preferredColorScheme(.dark) // Force dark mode
                .onReceive(stripeManager.$shouldNavigateToOrderStatus) { shouldNavigate in
                    if shouldNavigate {
                        showOrderStatus = true
                    }
                }
                .sheet(isPresented: $showOrderStatus) {
                    if let order = stripeManager.currentOrder {
                        OrderStatusView(order: order)
                            .onDisappear {
                                stripeManager.reset()
                            }
                    }
                }
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
        print("🔗 [AppDelegate] application(_:open:options:) called with URL: \(url)")
        print("🔗 [AppDelegate] URL scheme: \(url.scheme ?? "nil")")
        print("🔗 [AppDelegate] URL host: \(url.host ?? "nil")")
        print("🔗 [AppDelegate] URL path: \(url.path)")
        
        // Handle Stripe checkout success/cancel URLs
        if url.absoluteString.contains("restaurantdemo://success") {
            print("✅ [AppDelegate] Payment successful! Triggering success handler...")
            // Trigger payment success on main thread
            DispatchQueue.main.async {
                print("✅ [AppDelegate] Calling handlePaymentSuccess on main thread")
                StripeCheckoutManager.shared.handlePaymentSuccess()
            }
            return true
        } else if url.absoluteString.contains("restaurantdemo://cancel") {
            print("❌ [AppDelegate] Payment cancelled! Triggering cancel handler...")
            DispatchQueue.main.async {
                print("❌ [AppDelegate] Calling handlePaymentCancellation on main thread")
                StripeCheckoutManager.shared.handlePaymentCancellation()
            }
            return true
        }
        
        print("⚠️ [AppDelegate] URL not recognized, returning false")
        return false
    }
    
    // Handle URL schemes when app is already running
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("[AppDelegate] continue userActivity called")
        
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            print("[AppDelegate] Handling webpage URL: \(url)")
            
            // Check if this is a Stripe redirect
            if url.absoluteString.contains("restaurantdemo://success") {
                print("✅ Payment successful via user activity!")
                DispatchQueue.main.async {
                    StripeCheckoutManager.shared.handlePaymentSuccess()
                }
                return true
            } else if url.absoluteString.contains("restaurantdemo://cancel") {
                print("❌ Payment cancelled via user activity")
                DispatchQueue.main.async {
                    StripeCheckoutManager.shared.handlePaymentCancellation()
                }
                return true
            }
        }
        
        return false
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
