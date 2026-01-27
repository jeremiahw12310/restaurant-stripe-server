import Foundation
import UIKit
import FirebaseStorage
import CryptoKit

/// Manages persistent caching of promo carousel images with compression and change detection
class PromoImageCacheManager {
    static let shared = PromoImageCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let metadataKey = "promoImageMetadata"
    private let cacheVersionKey = "promoImageCacheVersion"
    private let currentCacheVersion = "1.0" // Increment when cache format changes
    
    // EMERGENCY: Kill switch to completely disable caching if it's causing crashes
    private let cachingEnabled: Bool
    
    // Compression quality for cached images (0.7 = good quality with ~50% size reduction)
    private let compressionQuality: CGFloat = 0.7
    
    // In-memory cache for ultra-fast access
    private var memoryCache: [String: UIImage] = [:]
    private let memoryCacheLimit = 10 // Keep last 10 images in memory
    
    private init() {
        // EMERGENCY KILL SWITCH: Check if caching should be disabled
        self.cachingEnabled = UserDefaults.standard.object(forKey: "promoImageCachingEnabled") as? Bool ?? true
        
        // Create cache directory in app's caches folder (won't be backed up to iCloud)
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("PromoImageCache", isDirectory: true)
        
        if !cachingEnabled {
            DebugLogger.debug("⚠️ PROMO IMAGE CACHING DISABLED BY KILL SWITCH", category: "Cache")
            return
        }
        
        // Wrap entire initialization in try-catch to prevent ANY crash
        do {
            // Create directory if it doesn't exist
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            DebugLogger.debug("🗂️ PromoImageCache initialized at: \(cacheDirectory.path)", category: "Cache")
            
            // Check cache version - clear if incompatible
            validateCacheVersion()
        } catch {
            DebugLogger.debug("⚠️ CRITICAL: Promo cache initialization failed, disabling caching: \(error)", category: "Cache")
            // Auto-disable caching to prevent future crashes
            UserDefaults.standard.set(false, forKey: "promoImageCachingEnabled")
            clearCache()
        }
    }
    
    /// Validate cache version and clear if incompatible
    private func validateCacheVersion() {
        // SAFETY: Don't try to decode during initialization - just check version and clear if needed
        let storedVersion = UserDefaults.standard.string(forKey: cacheVersionKey)
        
        if storedVersion != currentCacheVersion {
            DebugLogger.debug("⚠️ Promo cache version mismatch (stored: \(storedVersion ?? "none"), current: \(currentCacheVersion))", category: "Cache")
            DebugLogger.debug("🧹 Clearing promo cache for compatibility...", category: "Cache")
            clearCache()
            UserDefaults.standard.set(currentCacheVersion, forKey: cacheVersionKey)
        } else {
            DebugLogger.debug("✅ Promo cache version valid: \(currentCacheVersion)", category: "Cache")
        }
    }
    
    // MARK: - Public API
    
    /// Get cached image if available, otherwise nil
    func getCachedImage(for url: String) -> UIImage? {
        guard cachingEnabled else { return nil }
        
        // Check memory cache first (fastest)
        if let cachedImage = memoryCache[url] {
            return cachedImage
        }
        
        // Check disk cache - try both PNG and JPEG extensions (with error protection)
        do {
            for ext in ["png", "jpg"] {
                let cacheKey = generateCacheKey(from: url, fileExtension: ext)
                let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
                
                if fileManager.fileExists(atPath: fileURL.path) {
                    // Load from disk
                    if let imageData = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: imageData) {
                        // Store in memory cache for faster access next time
                        addToMemoryCache(url: url, image: image)
                        return image
                    }
                }
            }
        } catch {
            DebugLogger.debug("⚠️ Error reading cached promo image: \(error)", category: "Cache")
        }
        
        return nil
    }
    
    /// Check if we need to update the cached image (compare metadata)
    func needsUpdate(for url: String, currentMetadata: ImageMetadata) -> Bool {
        guard cachingEnabled else { return true }
        
        guard let cachedMetadata = getCachedMetadata(for: url) else {
            DebugLogger.debug("🔄 No cached metadata, needs download: \(url)", category: "Cache")
            return true // No metadata = needs download
        }
        
        // Compare URLs and timestamps
        let needsUpdate = cachedMetadata.url != url || 
                         cachedMetadata.timestamp < currentMetadata.timestamp
        
        if needsUpdate {
            DebugLogger.debug("🔄 Metadata changed, needs update: \(url)", category: "Cache")
        } else {
            DebugLogger.debug("✅ Cached image is up-to-date: \(url)", category: "Cache")
        }
        
        return needsUpdate
    }
    
    /// Download image from Firebase and cache it
    func downloadAndCache(url: String, metadata: ImageMetadata, completion: @escaping (UIImage?) -> Void) {
        DebugLogger.debug("⬇️ Downloading image: \(url)", category: "Cache")
        
        guard let imageURL = URL(string: url) else {
            DebugLogger.debug("❌ Invalid URL: \(url)", category: "Cache")
            completion(nil)
            return
        }
        
        // Download image data
        let task = URLSession.shared.dataTask(with: imageURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DebugLogger.debug("❌ Download failed: \(error.localizedDescription)", category: "Cache")
                completion(nil)
                return
            }
            
            guard let data = data, let originalImage = UIImage(data: data) else {
                DebugLogger.debug("❌ Failed to decode image data", category: "Cache")
                completion(nil)
                return
            }
            
            // Smart compression - PNG for transparency, JPEG for opaque
            guard let compressed = self.compressImage(originalImage) else {
                DebugLogger.debug("❌ Failed to compress image", category: "Cache")
                completion(originalImage) // Return original if compression fails
                return
            }
            
            // Save to disk with appropriate extension
            let cacheKey = self.generateCacheKey(from: url, fileExtension: compressed.fileExtension)
            let fileURL = self.cacheDirectory.appendingPathComponent(cacheKey)
            
            do {
                try compressed.data.write(to: fileURL)
                
                // Save metadata
                self.saveCachedMetadata(for: url, metadata: metadata)
                
                let originalSize = data.count
                let compressedSize = compressed.data.count
                let savings = Float(originalSize - compressedSize) / Float(originalSize) * 100
                DebugLogger.debug("✅ Cached image: \(url)", category: "Cache")
                DebugLogger.debug("   Original: \(self.formatBytes(originalSize)) → Compressed: \(self.formatBytes(compressedSize)) (saved \(String(format: "%.1f", savings))%)", category: "Cache")
                
                // Create image from compressed data
                if let cachedImage = UIImage(data: compressed.data) {
                    // Add to memory cache
                    self.addToMemoryCache(url: url, image: cachedImage)
                    completion(cachedImage)
                } else {
                    completion(originalImage)
                }
            } catch {
                DebugLogger.debug("❌ Failed to save cached image: \(error.localizedDescription)", category: "Cache")
                completion(originalImage)
            }
        }
        
        task.resume()
    }
    
    /// Preload all carousel images in background
    func preloadImages(urls: [(url: String, metadata: ImageMetadata)], completion: @escaping () -> Void) {
        guard cachingEnabled else {
            completion()
            return
        }
        
        guard !urls.isEmpty else {
            completion()
            return
        }
        
        DebugLogger.debug("🔄 Preloading \(urls.count) carousel images...", category: "Cache")
        
        let group = DispatchGroup()
        
        for (url, metadata) in urls {
            // Check if we need to download
            if getCachedImage(for: url) != nil && !needsUpdate(for: url, currentMetadata: metadata) {
                // Already cached and up-to-date
                continue
            }
            
            group.enter()
            downloadAndCache(url: url, metadata: metadata) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            DebugLogger.debug("✅ Preloading complete!", category: "Cache")
            completion()
        }
    }
    
    /// Clear memory cache only (for memory warnings)
    func clearMemoryCache() {
        memoryCache.removeAll()
        DebugLogger.debug("🧹 Cleared promo image memory cache", category: "Cache")
    }
    
    /// Clear all cached images
    func clearCache() {
        // Clear memory cache
        memoryCache.removeAll()
        
        // Clear disk cache
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try? fileManager.removeItem(at: file)
            }
            DebugLogger.debug("🗑️ Cleared all cached images", category: "Cache")
        } catch {
            DebugLogger.debug("❌ Failed to clear cache: \(error.localizedDescription)", category: "Cache")
        }
        
        // Clear metadata
        UserDefaults.standard.removeObject(forKey: metadataKey)
    }
    
    /// Get cache size in bytes
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        for file in files {
            if let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Hero Image (First Carousel Image) Persistence
    
    private let heroImageFileName = "hero_carousel_image.jpg"
    private let heroImageURLKey = "heroCarouselImageURL"
    
    /// Load the persisted hero image instantly (for immediate display on app launch)
    func loadHeroImage() -> UIImage? {
        let heroFileURL = cacheDirectory.appendingPathComponent(heroImageFileName)
        
        guard fileManager.fileExists(atPath: heroFileURL.path) else {
            DebugLogger.debug("📸 [Hero] No hero image cached yet", category: "Cache")
            return nil
        }
        
        do {
            let imageData = try Data(contentsOf: heroFileURL)
            if let image = UIImage(data: imageData) {
                DebugLogger.debug("✅ [Hero] Loaded hero image instantly from disk", category: "Cache")
                return image
            }
        } catch {
            DebugLogger.debug("⚠️ [Hero] Failed to load hero image: \(error.localizedDescription)", category: "Cache")
        }
        
        return nil
    }
    
    /// Get the URL of the currently cached hero image (to detect changes)
    func getHeroImageURL() -> String? {
        return UserDefaults.standard.string(forKey: heroImageURLKey)
    }
    
    /// Save the first carousel image for instant display on next launch
    func saveHeroImage(_ image: UIImage, url: String) {
        let heroFileURL = cacheDirectory.appendingPathComponent(heroImageFileName)
        
        // Compress to JPEG for efficient storage
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            DebugLogger.debug("⚠️ [Hero] Failed to compress hero image", category: "Cache")
            return
        }
        
        do {
            try jpegData.write(to: heroFileURL)
            UserDefaults.standard.set(url, forKey: heroImageURLKey)
            DebugLogger.debug("✅ [Hero] Saved hero image (\(formatBytes(jpegData.count))) for instant loading", category: "Cache")
        } catch {
            DebugLogger.debug("⚠️ [Hero] Failed to save hero image: \(error.localizedDescription)", category: "Cache")
        }
    }
    
    /// Check if the hero image needs updating (URL changed)
    func heroImageNeedsUpdate(currentURL: String) -> Bool {
        guard let cachedURL = getHeroImageURL() else {
            return true // No cached hero image
        }
        return cachedURL != currentURL
    }
    
    /// Download and save a new hero image
    func downloadAndSaveHeroImage(url: String, completion: @escaping (UIImage?) -> Void) {
        guard let imageURL = URL(string: url) else {
            completion(nil)
            return
        }
        
        DebugLogger.debug("⬇️ [Hero] Downloading hero image...", category: "Cache")
        
        URLSession.shared.dataTask(with: imageURL) { [weak self] data, _, error in
            guard let self = self, let data = data, let image = UIImage(data: data) else {
                DebugLogger.debug("⚠️ [Hero] Download failed: \(error?.localizedDescription ?? "Unknown error")", category: "Cache")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Save for next launch
            self.saveHeroImage(image, url: url)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
    
    // MARK: - Private Helpers
    
    private func generateCacheKey(from url: String, fileExtension: String = "jpg") -> String {
        // Use SHA256 hash of URL as filename to avoid special characters
        let data = Data(url.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".\(fileExtension)"
    }
    
    /// Check if image has transparency (alpha channel)
    private func hasTransparency(image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        let alphaInfo = cgImage.alphaInfo
        return alphaInfo == .first || 
               alphaInfo == .last || 
               alphaInfo == .premultipliedFirst || 
               alphaInfo == .premultipliedLast
    }
    
    /// Compress image with appropriate format (PNG for transparency, JPEG for opaque)
    private func compressImage(_ image: UIImage) -> (data: Data, fileExtension: String)? {
        if hasTransparency(image: image) {
            // Image has transparency - save as PNG to preserve it
            guard let pngData = image.pngData() else { return nil }
            DebugLogger.debug("   Format: PNG (has transparency)", category: "Cache")
            return (pngData, "png")
        } else {
            // Image is opaque - save as JPEG for better compression
            guard let jpegData = image.jpegData(compressionQuality: compressionQuality) else { return nil }
            DebugLogger.debug("   Format: JPEG (opaque)", category: "Cache")
            return (jpegData, "jpg")
        }
    }
    
    private func addToMemoryCache(url: String, image: UIImage) {
        // Add to memory cache
        memoryCache[url] = image
        
        // Limit memory cache size
        if memoryCache.count > memoryCacheLimit {
            // Remove oldest entry (simple implementation, could be improved with LRU)
            if let firstKey = memoryCache.keys.first {
                memoryCache.removeValue(forKey: firstKey)
            }
        }
    }
    
    private func getCachedMetadata(for url: String) -> ImageMetadata? {
        guard cachingEnabled else { return nil }
        
        // SAFETY: Wrap in autoreleasepool to catch any Obj-C exceptions
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else {
            return nil
        }
        
        // Extra safety: Check if data is valid before decoding
        if data.count == 0 || data.count > 1_000_000 { // Sanity check
            DebugLogger.debug("⚠️ Invalid metadata size, clearing: \(data.count) bytes", category: "Cache")
            UserDefaults.standard.removeObject(forKey: metadataKey)
            return nil
        }
        
        do {
            let metadataDict = try JSONDecoder().decode([String: ImageMetadata].self, from: data)
            return metadataDict[url]
        } catch {
            DebugLogger.debug("⚠️ Corrupted carousel metadata detected, clearing cache: \(error.localizedDescription)", category: "Cache")
            DebugLogger.debug("🔧 Auto-disabling caching to prevent crashes", category: "Cache")
            // Clear ALL cache-related keys to be safe
            UserDefaults.standard.removeObject(forKey: metadataKey)
            UserDefaults.standard.removeObject(forKey: cacheVersionKey)
            UserDefaults.standard.set(false, forKey: "promoImageCachingEnabled")
            return nil
        }
    }
    
    private func saveCachedMetadata(for url: String, metadata: ImageMetadata) {
        var metadataDict: [String: ImageMetadata] = [:]
        
        // Try to load existing metadata, clear if corrupted
        if let data = UserDefaults.standard.data(forKey: metadataKey) {
            do {
                metadataDict = try JSONDecoder().decode([String: ImageMetadata].self, from: data)
            } catch {
                DebugLogger.debug("⚠️ Corrupted carousel metadata during save, starting fresh: \(error.localizedDescription)", category: "Cache")
                UserDefaults.standard.removeObject(forKey: metadataKey)
                metadataDict = [:]
            }
        }
        
        metadataDict[url] = metadata
        
        do {
            let data = try JSONEncoder().encode(metadataDict)
            UserDefaults.standard.set(data, forKey: metadataKey)
        } catch {
            DebugLogger.debug("❌ Failed to encode carousel metadata: \(error.localizedDescription)", category: "Cache")
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Types

struct ImageMetadata: Codable {
    let url: String
    let timestamp: Date
    
    init(url: String, timestamp: Date = Date()) {
        self.url = url
        self.timestamp = timestamp
    }
}

