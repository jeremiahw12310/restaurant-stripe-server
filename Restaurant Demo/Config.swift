import Foundation

struct Config {
    // MARK: - Backend URLs
    
    // For local development (simulator)
    static let localBackendURL = "http://localhost:3001"
    
    // For local development (physical device on same network)
    // REPLACE 192.168.1.100 WITH YOUR COMPUTER'S ACTUAL IP ADDRESS
    static let localNetworkBackendURL = "http://192.168.1.100:3001"
    
    // For production (replace with your deployed URL)
    static let productionBackendURL = "https://restaurant-stripe-server-1.onrender.com"
    
    // MARK: - Current Environment
    // Change this to switch between environments
    static let currentEnvironment: Environment = .local
    
    enum Environment {
        case local
        case localNetwork
        case production
        
        var baseURL: String {
            switch self {
            case .local:
                return Config.localBackendURL
            case .localNetwork:
                return Config.localNetworkBackendURL
            case .production:
                return Config.productionBackendURL
            }
        }
    }
    
    // MARK: - Main Backend URL (used by StripeCheckoutManager)
    static var backendURL: String {
        return currentEnvironment.baseURL
    }
    
    // MARK: - API Endpoints
    static var analyzeReceiptURL: String {
        return "\(currentEnvironment.baseURL)/analyze-receipt"
    }
    
    static var chatURL: String {
        return "\(currentEnvironment.baseURL)/chat"
    }
    
    static var ordersURL: String {
        return "\(currentEnvironment.baseURL)/orders"
    }
    
    static var createCheckoutSessionURL: String {
        return "\(currentEnvironment.baseURL)/create-checkout-session"
    }
    
    // MARK: - Debug Info
    static func printCurrentConfig() {
        print("🔧 Current Environment: \(currentEnvironment)")
        print("🔗 Backend URL: \(currentEnvironment.baseURL)")
        print("📡 Receipt Analysis URL: \(analyzeReceiptURL)")
        print("💬 Chat URL: \(chatURL)")
        print("📦 Orders URL: \(ordersURL)")
    }
} 