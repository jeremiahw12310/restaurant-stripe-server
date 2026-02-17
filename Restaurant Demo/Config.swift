import Foundation

// MARK: - Environment Configuration
enum AppEnvironment {
    case localNetwork
    case production
}

// MARK: - Performance Configuration
struct PerformanceConfig {
    // OPTIMIZED: Performance flags to reduce CPU usage
    static let enableReducedAnimations = true
    static let enableImageOptimization = true
    static let enableFirebaseOptimization = true
    static let enableTimerOptimization = true
    
    // Animation frame rates
    static let animationFrameRate: Double = 30.0 // Reduced from 60fps to 30fps
    static let backgroundAnimationFrameRate: Double = 15.0 // Reduced for background animations
    
    // Image processing limits
    static let maxImageSize = CGSize(width: 200, height: 200)
    static let imageCacheSizeMB = 30
    static let diskCacheSizeMB = 80
    
    // Firebase listener limits
    static let maxFirebaseListeners = 10
    static let firebaseQueryLimit = 50
}

// MARK: - Backend Configuration
struct Config {
    // Environment switching - automatically selects based on build configuration
    // Release builds always use production; DEBUG builds default to production but can be changed
    // To use local server during development: change .production to .localNetwork below
    #if DEBUG
    static let currentEnvironment: AppEnvironment = .production  // Change to .localNetwork for local testing
    #else
    static let currentEnvironment: AppEnvironment = .production
    #endif
    
    // Backend URLs for different environments
    static var backendURL: String {
        switch currentEnvironment {
        case .localNetwork:
            return localNetworkBackendURL
        case .production:
            return productionBackendURL
        }
    }
    
    // Individual backend URLs
    static let localBackendURL = "http://192.168.1.100:3001" // Update with your computer's IP
    static let localNetworkBackendURL = "http://192.168.1.100:3001" // Update with your computer's IP
    // NOTE: This host was originally named for Stripe; the app no longer uses Stripe.
    // Keep the backend base here (chat, rewards, receipt analysis, referral, etc.).
    static let productionBackendURL = "https://restaurant-stripe-server-1.onrender.com"
    
    // Firebase configuration (single source of truth is GoogleService-Info.plist)
    // NOTE: Do not hardcode alternate project IDs here.
    static let firebaseProjectID = "dumplinghouseapp"
    
    // Performance monitoring
    static let enablePerformanceMonitoring = true
    static let performanceLoggingEnabled = false // Set to true for debugging
    
    // App Store configuration
    // Set this once you create your app in App Store Connect (before approval)
    // You can find the App Store ID in App Store Connect → Your App → App Information → Apple ID
    // Format: "1234567890" (just the number, not the full URL)
    static let appStoreID: String? = "6758052536"
}

extension Config {
    // Whitelisted Order Online URL for external links
    static var orderOnlineURL: URL {
        // Default to backend base + "/order"; update if a dedicated ordering domain is used
        if let url = URL(string: backendURL + "/order") {
            return url
        }
        if let fallbackURL = URL(string: productionBackendURL + "/order") {
            #if DEBUG
            print("⚠️ Invalid backend URL configuration: \(backendURL)/order. Falling back to production /order.")
            #endif
            return fallbackURL
        }
        // This should never happen - both backendURL and productionBackendURL are hardcoded valid URLs
        // Last resort fallback - use a hardcoded known-good URL (compile-time constant guaranteed to parse)
        return URL(string: "https://restaurant-stripe-server-1.onrender.com/order")!
    }
}

// MARK: - More / Settings Links
extension Config {
    /// Restaurant phone number for "Call restaurant" and other tel: links.
    static let restaurantPhoneNumber = "+16158914728"

    /// Restaurant location for directions (Dumpling House).
    static let restaurantLatitude = 36.13663
    static let restaurantLongitude = -86.80233

    /// Support email used by the More screen. Set this to enable mailto: behavior.
    static let supportEmail: String? = "support@bytequack.com"

    /// Privacy Policy URL used by the More screen. Set this to enable in-app Safari viewing.
    static var privacyPolicyURL: URL? {
        if let url = URL(string: "\(backendURL)/privacy.html") {
            return url
        }
        if let fallbackURL = URL(string: "\(productionBackendURL)/privacy.html") {
            #if DEBUG
            print("⚠️ Invalid backend URL configuration: \(backendURL)/privacy.html. Falling back to production /privacy.html.")
            #endif
            return fallbackURL
        }
        return nil
    }

    /// Terms of Service URL used by the More screen. Set this to enable in-app Safari viewing.
    static var termsOfServiceURL: URL? {
        if let url = URL(string: "\(backendURL)/terms.html") {
            return url
        }
        if let fallbackURL = URL(string: "\(productionBackendURL)/terms.html") {
            #if DEBUG
            print("⚠️ Invalid backend URL configuration: \(backendURL)/terms.html. Falling back to production /terms.html.")
            #endif
            return fallbackURL
        }
        return nil
    }
}

// MARK: - Setup Instructions

/*
 📱 FOR IPHONE TESTING:
 
 1. Find your computer's IP address:
    - Mac: System Preferences > Network > Wi-Fi > Advanced > TCP/IP
    - Windows: ipconfig in Command Prompt
    - Should look like: 192.168.1.xxx or 10.0.0.xxx
 
 2. Update the localNetwork URL above with your IP:
    - Replace "localhost" with your IP address
    - Example: "http://192.168.1.100:3001"
 
 3. Make sure currentEnvironment is set to .localNetwork
 
 4. Make sure your iPhone and computer are on the same Wi-Fi network
 
 5. Start your server with: node server.js
 
 6. Test from iPhone!
 
 ☁️ FOR PRODUCTION DEPLOYMENT:
 
 1. Deploy server to Railway/Render/Heroku
 2. Change currentEnvironment to .production
 3. Build and test!
 */

// MARK: - Network Configuration
extension URLSession {
    /// Configured URLSession with explicit timeouts for production use
    /// Use this instead of URLSession.shared for better timeout handling
    static let configured: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
} 
