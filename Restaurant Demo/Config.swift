import Foundation

struct Config {
    enum Environment {
        case local          // Simulator - localhost
        case localNetwork   // Physical device - your computer's IP
        case production     // Deployed app
    }
    
    // 🔧 CHANGE THIS to switch environments
    static let currentEnvironment: Environment = .production
    
    // Backend URLs for each environment
    static var backendURL: String {
        switch currentEnvironment {
        case .local:
            return "http://localhost:3001"
        case .localNetwork:
            // 📱 Replace with your computer's IP address for iPhone testing
            return "http://192.168.0.108"  // Example: find your actual IP
        case .production:
            // 🚀 Replace with your deployed server URL
            return "https://restaurant-stripe-server.onrender.com"
        }
    }
    
    // Receipt scanning URLs (existing)
    static var receiptBackendURL: String {
        switch currentEnvironment {
        case .local:
            return "http://localhost:3001"
        case .localNetwork:
            return "http://192.168.0.108"  // Same IP as backend
        case .production:
            return "https://restaurant-stripe-server.onrender.com"
        }
    }
    
    // Environment info
    static var environmentName: String {
        switch currentEnvironment {
        case .local:
            return "Local (Simulator)"
        case .localNetwork:
            return "Local Network (iPhone)"
        case .production:
            return "Production"
        }
    }
    
    static var isProduction: Bool {
        return currentEnvironment == .production
    }
}

// MARK: - Setup Instructions

/*
 📱 FOR IPHONE TESTING:
 
 1. Find your computer's IP address:
    - Mac: System Preferences > Network > Wi-Fi > Advanced > TCP/IP
    - Windows: ipconfig in Command Prompt
    - Should look like: 192.168.1.xxx or 10.0.0.xxx
 
 2. Update the localNetwork URL above with your IP
 
 3. Change currentEnvironment to .localNetwork
 
 4. Make sure your iPhone and computer are on the same Wi-Fi network
 
 5. Start your server with: node server.js
 
 6. Test from iPhone!
 
 ☁️ FOR PRODUCTION DEPLOYMENT:
 
 1. Deploy server to Railway/Render/Heroku
 2. Update production URL above
 3. Change currentEnvironment to .production
 4. Build and test!
 */ 
