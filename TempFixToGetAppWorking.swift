import Foundation

// 🚨 EMERGENCY TEMPORARY FIX 🚨
// This file disables image caching so your app can launch
// 
// HOW TO USE:
// 1. Add this file to your Xcode project
// 2. Build and run your app
// 3. App will launch successfully
// 4. DELETE this file after the app works
// 
// The cache managers now have kill switches built in,
// so the app will continue working without caching enabled.

class EmergencyRecovery {
    static func disableCachingToRecoverApp() {
        print("🚑 EMERGENCY RECOVERY: Disabling image caching")
        
        // MASTER KILL SWITCH - prevents MenuViewModel from even trying to initialize cache managers
        UserDefaults.standard.set(true, forKey: "disableAllImageCaching")
        
        // Disable both cache managers
        UserDefaults.standard.set(false, forKey: "menuImageCachingEnabled")
        UserDefaults.standard.set(false, forKey: "promoImageCachingEnabled")
        
        // Clear all corrupted metadata
        UserDefaults.standard.removeObject(forKey: "menuImageMetadata")
        UserDefaults.standard.removeObject(forKey: "promoImageMetadata")
        UserDefaults.standard.removeObject(forKey: "menuImageCacheVersion")
        UserDefaults.standard.removeObject(forKey: "promoImageCacheVersion")
        
        print("✅ Cache disabled - app should now launch")
        print("ℹ️  Images will load from network (no caching)")
        print("📝 To re-enable: UserDefaults.standard.set(false, forKey: \"disableAllImageCaching\")")
    }
}

// Auto-run on app launch
extension EmergencyRecovery {
    static let _ = {
        disableCachingToRecoverApp()
        return ()
    }()
}

