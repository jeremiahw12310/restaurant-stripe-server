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
    // Environment switching
    static let currentEnvironment: AppEnvironment = .production
    
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
    static let productionBackendURL = "https://restaurant-stripe-server-1.onrender.com"
    
    // Firebase configuration
    static let firebaseProjectID = "restaurant-demo-12345"
    
    // Performance monitoring
    static let enablePerformanceMonitoring = true
    static let performanceLoggingEnabled = false // Set to true for debugging
}

extension Config {
    // Whitelisted Order Online URL for Community link policy
    static var orderOnlineURL: URL {
        // Default to backend base + "/order"; update if a dedicated ordering domain is used
        return URL(string: backendURL + "/order")!
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
