import Foundation

/// Service to check if the app version meets the minimum required version from the backend
class AppVersionService {
    static let shared = AppVersionService()
    
    private init() {}
    
    /// Represents the version check response from the backend
    struct VersionCheckResponse: Codable {
        let minimumRequiredVersion: String
        let currentAppStoreVersion: String?
        let updateMessage: String?
        let forceUpdate: Bool
    }
    
    /// Check if the current app version meets the minimum required version
    /// - Returns: Result containing whether update is required and the response data
    func checkVersionRequirement() async -> Result<(updateRequired: Bool, response: VersionCheckResponse), Error> {
        guard let url = URL(string: "\(Config.backendURL)/app-version") else {
            return .failure(NSError(domain: "AppVersionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0 // 10 second timeout
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "AppVersionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
            }
            
            guard httpResponse.statusCode == 200 else {
                // If endpoint doesn't exist or fails, allow app to continue (graceful degradation)
                DebugLogger.debug("⚠️ Version check endpoint returned status \(httpResponse.statusCode) - allowing app to continue", category: "VersionCheck")
                return .failure(NSError(domain: "AppVersionService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Version check failed"]))
            }
            
            let versionResponse = try JSONDecoder().decode(VersionCheckResponse.self, from: data)
            
            // Get current app version
            let currentVersion = getCurrentAppVersion()
            let updateRequired = isUpdateRequired(currentVersion: currentVersion, minimumVersion: versionResponse.minimumRequiredVersion)
            
            DebugLogger.debug("📱 Version check: current=\(currentVersion), minimum=\(versionResponse.minimumRequiredVersion), updateRequired=\(updateRequired)", category: "VersionCheck")
            
            return .success((updateRequired: updateRequired, response: versionResponse))
            
        } catch {
            // If version check fails (network error, etc.), allow app to continue
            // This prevents network issues from locking users out
            DebugLogger.debug("⚠️ Version check failed: \(error.localizedDescription) - allowing app to continue", category: "VersionCheck")
            return .failure(error)
        }
    }
    
    /// Get the current app version from Info.plist
    private func getCurrentAppVersion() -> String {
        // Try CFBundleShortVersionString first (marketing version, e.g., "1.0.0")
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        // Fallback to CFBundleVersion (build number)
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return "0.0.0"
    }
    
    /// Compare version strings to determine if an update is required
    /// - Parameters:
    ///   - currentVersion: Current app version (e.g., "1.0.0")
    ///   - minimumVersion: Minimum required version (e.g., "1.1.0")
    /// - Returns: true if current version is less than minimum required version
    private func isUpdateRequired(currentVersion: String, minimumVersion: String) -> Bool {
        let currentComponents = versionComponents(currentVersion)
        let minimumComponents = versionComponents(minimumVersion)
        
        // Compare version components (major.minor.patch)
        for i in 0..<max(currentComponents.count, minimumComponents.count) {
            let current = i < currentComponents.count ? currentComponents[i] : 0
            let minimum = i < minimumComponents.count ? minimumComponents[i] : 0
            
            if current < minimum {
                return true
            } else if current > minimum {
                return false
            }
        }
        
        // Versions are equal, no update required
        return false
    }
    
    /// Parse version string into integer components
    /// - Parameter version: Version string (e.g., "1.2.3")
    /// - Returns: Array of version components [1, 2, 3]
    private func versionComponents(_ version: String) -> [Int] {
        return version.split(separator: ".").compactMap { Int($0) }
    }
    
    /// Get the App Store URL for the app
    /// - Returns: App Store URL if available, nil otherwise
    func getAppStoreURL() -> URL? {
        // Option 1: Use App Store ID from environment/config (recommended)
        // Set this in your Config.swift or as an environment variable
        // You can find your App Store ID in App Store Connect
        // Format: https://apps.apple.com/app/id1234567890
        
        // Option 2: Use bundle identifier to search App Store
        // This will open the App Store search for your app
        if let bundleId = Bundle.main.bundleIdentifier {
            // Try direct app link first (if you know the App Store ID)
            // For now, use search as fallback
            let encodedBundleId = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
            return URL(string: "https://apps.apple.com/search?term=\(encodedBundleId)")
        }
        
        return nil
    }
}
