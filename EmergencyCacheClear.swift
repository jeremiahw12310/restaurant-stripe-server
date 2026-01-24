import SwiftUI

/// EMERGENCY RECOVERY VIEW
/// Only use this if your app is crashing and you need to clear the cache manually.
/// To use: Temporarily add this to your app's main view or settings.
///
/// Example usage:
/// ```
/// NavigationLink("Emergency: Clear Cache") {
///     EmergencyCacheClearView()
/// }
/// ```

struct EmergencyCacheClearView: View {
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var cacheStats = CacheStats()
    
    struct CacheStats {
        var menuSize: String = "Calculating..."
        var menuCount: Int = 0
        var promoSize: String = "Calculating..."
        var hasMenuMetadata: Bool = false
        var hasPromoMetadata: Bool = false
    }
    
    var body: some View {
        List {
            Section(header: Text("Cache Status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu Images")
                        .font(.headline)
                    Text("Size: \(cacheStats.menuSize)")
                    Text("Count: \(cacheStats.menuCount) images")
                    Text("Metadata: \(cacheStats.hasMenuMetadata ? "Present" : "Missing")")
                        .foregroundColor(cacheStats.hasMenuMetadata ? .green : .red)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Promo Images")
                        .font(.headline)
                    Text("Size: \(cacheStats.promoSize)")
                    Text("Metadata: \(cacheStats.hasPromoMetadata ? "Present" : "Missing")")
                        .foregroundColor(cacheStats.hasPromoMetadata ? .green : .red)
                }
                .padding(.vertical, 4)
                
                Button("Refresh Stats") {
                    loadCacheStats()
                }
            }
            
            Section(header: Text("Recovery Actions")) {
                Button(action: clearMenuCache) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Menu Cache")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .foregroundColor(.orange)
                
                Button(action: clearPromoCache) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Promo Cache")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .foregroundColor(.orange)
                
                Button(action: clearAllCaches) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Clear All Caches")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .foregroundColor(.red)
            }
            
            Section(header: Text("Advanced Recovery")) {
                Button(action: clearUserDefaults) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Clear UserDefaults Metadata")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .foregroundColor(.red)
                
                Button(action: fullReset) {
                    HStack {
                        Image(systemName: "exclamationmark.octagon")
                        Text("Full Reset (Nuclear Option)")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .foregroundColor(.red)
            }
            
            Section(footer: Text("Use these tools only if your app is experiencing cache-related issues. All cleared data will be re-downloaded automatically.")) {
                EmptyView()
            }
        }
        .navigationTitle("Cache Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Cache Cleared"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK")) {
                    loadCacheStats()
                }
            )
        }
        .onAppear {
            loadCacheStats()
        }
    }
    
    // MARK: - Actions
    
    func clearMenuCache() {
        MenuImageCacheManager.shared.clearCache()
        alertMessage = "Menu image cache cleared successfully. Images will re-download automatically."
        showingAlert = true
    }
    
    func clearPromoCache() {
        PromoImageCacheManager.shared.clearCache()
        alertMessage = "Promo image cache cleared successfully. Images will re-download automatically."
        showingAlert = true
    }
    
    func clearAllCaches() {
        MenuImageCacheManager.shared.clearCache()
        PromoImageCacheManager.shared.clearCache()
        alertMessage = "All caches cleared successfully. Images will re-download automatically."
        showingAlert = true
    }
    
    func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "menuImageMetadata")
        UserDefaults.standard.removeObject(forKey: "promoImageMetadata")
        UserDefaults.standard.removeObject(forKey: "menuImageCacheVersion")
        UserDefaults.standard.removeObject(forKey: "promoImageCacheVersion")
        alertMessage = "UserDefaults metadata cleared. Cache will rebuild on next app launch."
        showingAlert = true
    }
    
    func fullReset() {
        // Clear all caches
        MenuImageCacheManager.shared.clearCache()
        PromoImageCacheManager.shared.clearCache()
        
        // Clear all UserDefaults keys
        clearUserDefaults()
        
        // Clear Kingfisher cache too
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache()
        
        alertMessage = "Full reset complete! All cached data cleared. App will rebuild caches from scratch."
        showingAlert = true
    }
    
    func loadCacheStats() {
        DispatchQueue.global(qos: .userInitiated).async {
            let menuSize = MenuImageCacheManager.shared.getCacheSize()
            let menuCount = MenuImageCacheManager.shared.getCachedImageCount()
            let promoSize = PromoImageCacheManager.shared.getCacheSize()
            
            let hasMenuMetadata = UserDefaults.standard.data(forKey: "menuImageMetadata") != nil
            let hasPromoMetadata = UserDefaults.standard.data(forKey: "promoImageMetadata") != nil
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            
            DispatchQueue.main.async {
                cacheStats = CacheStats(
                    menuSize: formatter.string(fromByteCount: menuSize),
                    menuCount: menuCount,
                    promoSize: formatter.string(fromByteCount: promoSize),
                    hasMenuMetadata: hasMenuMetadata,
                    hasPromoMetadata: hasPromoMetadata
                )
            }
        }
    }
}

// MARK: - Preview

struct EmergencyCacheClearView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EmergencyCacheClearView()
        }
    }
}






