import Foundation

/// EMERGENCY: Runs BEFORE any cache managers initialize to clear corrupted data
/// This prevents crashes from corrupted UserDefaults on app launch
class CacheEmergencyCleanup {
    
    /// Call this in your App's init() BEFORE anything else
    static func performEmergencyCleanup() {
        DebugLogger.debug("🚑 Emergency Cache Cleanup: Running safety check...", category: "Cache")
        
        // CRITICAL: Don't even try to decode - just check if the data exists and clear it
        // Decoding corrupted data can throw Objective-C exceptions that crash before we can catch them
        
        let hasMenuData = UserDefaults.standard.data(forKey: "menuImageMetadata") != nil
        let hasPromoData = UserDefaults.standard.data(forKey: "promoImageMetadata") != nil
        
        if hasMenuData || hasPromoData {
            DebugLogger.debug("⚠️ Found existing cache metadata - clearing to prevent potential corruption", category: "Cache")
            DebugLogger.debug("🧹 CLEARING ALL CACHE DATA AS SAFETY PRECAUTION", category: "Cache")
            clearAllCacheData()
            DebugLogger.debug("✅ Cache cleared - app will rebuild cache safely", category: "Cache")
        } else {
            DebugLogger.debug("✅ No existing cache data found - fresh start", category: "Cache")
        }
    }
    
    /// Nuclear option: Clear all cache-related UserDefaults
    static func clearAllCacheData() {
        // Menu cache keys
        UserDefaults.standard.removeObject(forKey: "menuImageMetadata")
        UserDefaults.standard.removeObject(forKey: "menuImageCacheVersion")
        UserDefaults.standard.removeObject(forKey: "menuImageCachingEnabled")
        
        // Promo cache keys
        UserDefaults.standard.removeObject(forKey: "promoImageMetadata")
        UserDefaults.standard.removeObject(forKey: "promoImageCacheVersion")
        UserDefaults.standard.removeObject(forKey: "promoImageCachingEnabled")
        
        // Master kill switch
        UserDefaults.standard.removeObject(forKey: "disableAllImageCaching")
        
        UserDefaults.standard.synchronize()
        
        DebugLogger.debug("✅ All cache data cleared - app will work normally", category: "Cache")
        DebugLogger.debug("ℹ️  Images will re-download and cache will rebuild", category: "Cache")
    }
}

