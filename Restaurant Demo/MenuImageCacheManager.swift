import Foundation
import UIKit
import FirebaseStorage
import CryptoKit

/// Manages persistent caching of menu category icons and item images with smart preloading
class MenuImageCacheManager {
    static let shared = MenuImageCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let metadataKey = "menuImageMetadata"
    private let cacheVersionKey = "menuImageCacheVersion"
    private let currentCacheVersion = "1.0" // Increment when cache format changes
    
    // EMERGENCY: Kill switch to completely disable caching if it's causing crashes
    private let cachingEnabled: Bool
    
    // Compression quality for cached images
    private let compressionQuality: CGFloat = 0.7
    
    // Cache size limits
    private let maxCacheSize: Int64 = 50 * 1024 * 1024 // 50 MB
    
    // In-memory cache for ultra-fast access
    private var memoryCache: [String: UIImage] = [:]
    private let memoryCacheLimit = 30 // Keep last 30 images in memory
    
    // Track download tasks for cancellation
    private var downloadTasks: [String: URLSessionDataTask] = [:]
    private let downloadTasksQueue = DispatchQueue(label: "com.restaurantdemo.menuImageCache.downloadTasks", attributes: .concurrent)
    
    // Priority queue for smart preloading
    private enum CachePriority {
        case critical   // Category icons - must load immediately
        case high       // Visible menu items - load quickly
        case normal     // Off-screen items - background load
        case low        // Rarely viewed items - lazy load
    }
    
    private init() {
        // EMERGENCY KILL SWITCH: Check if caching should be disabled
        // Set this to false in UserDefaults to completely disable caching if it causes crashes
        self.cachingEnabled = UserDefaults.standard.object(forKey: "menuImageCachingEnabled") as? Bool ?? true
        
        // Create cache directory in app's caches folder
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("MenuImageCache", isDirectory: true)
        
        if !cachingEnabled {
            DebugLogger.debug("⚠️ MENU IMAGE CACHING DISABLED BY KILL SWITCH", category: "Cache")
            return
        }
        
        // Wrap entire initialization in try-catch to prevent ANY crash
        do {
            // Create directory if it doesn't exist
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            DebugLogger.debug("🗂️ MenuImageCache initialized at: \(cacheDirectory.path)", category: "Cache")
            
            // Check cache version - clear if incompatible
            validateCacheVersion()
            
            // Check and cleanup if cache is too large
            cleanupIfNeeded()
        } catch {
            DebugLogger.debug("⚠️ CRITICAL: Cache initialization failed, disabling caching: \(error)", category: "Cache")
            // Auto-disable caching to prevent future crashes
            UserDefaults.standard.set(false, forKey: "menuImageCachingEnabled")
            clearCache()
        }
    }
    
    /// Validate cache version and clear if incompatible
    private func validateCacheVersion() {
        // SAFETY: Don't try to decode during initialization - just check version and clear if needed
        let storedVersion = UserDefaults.standard.string(forKey: cacheVersionKey)
        
        if storedVersion != currentCacheVersion {
            DebugLogger.debug("⚠️ Cache version mismatch (stored: \(storedVersion ?? "none"), current: \(currentCacheVersion))", category: "Cache")
            DebugLogger.debug("🧹 Clearing cache for compatibility...", category: "Cache")
            clearCache()
            UserDefaults.standard.set(currentCacheVersion, forKey: cacheVersionKey)
        } else {
            DebugLogger.debug("✅ Cache version valid: \(currentCacheVersion)", category: "Cache")
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
            DebugLogger.debug("⚠️ Error reading cached image: \(error)", category: "Cache")
        }
        
        return nil
    }
    
    /// Check if we need to update the cached image
    func needsUpdate(for url: String, currentMetadata: MenuImageMetadata) -> Bool {
        guard cachingEnabled else { return true }
        
        guard let cachedMetadata = getCachedMetadata(for: url) else {
            return true // No metadata = needs download
        }
        
        return cachedMetadata.url != url || cachedMetadata.timestamp < currentMetadata.timestamp
    }
    
    /// Download image from URL and cache it
    private func downloadAndCache(url: String, priority: CachePriority = .normal, metadata: MenuImageMetadata, completion: @escaping (UIImage?) -> Void) {
        guard let imageURL = URL(string: url) else {
            DebugLogger.debug("❌ Invalid URL: \(url)", category: "Cache")
            completion(nil)
            return
        }
        
        // Create task first
        let task = URLSession.shared.dataTask(with: imageURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Remove from active downloads (thread-safe)
            self.downloadTasksQueue.async(flags: .barrier) {
                self.downloadTasks.removeValue(forKey: url)
            }
            
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
                completion(originalImage)
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
                DebugLogger.debug("✅ Cached: \(url.split(separator: "/").last ?? "unknown")", category: "Cache")
                DebugLogger.debug("   Size: \(self.formatBytes(originalSize)) → \(self.formatBytes(compressedSize)) (\(String(format: "%.0f", savings))% saved)", category: "Cache")
                
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
        
        // Atomically check if already downloading and add task if not (thread-safe)
        var shouldStart = false
        downloadTasksQueue.sync(flags: .barrier) {
            if downloadTasks[url] == nil {
                downloadTasks[url] = task
                shouldStart = true
            }
        }
        
        if shouldStart {
            task.resume()
        } else {
            DebugLogger.debug("⏳ Already downloading: \(url)", category: "Cache")
            // Task will be deallocated since it's not stored or resumed
        }
    }
    
    /// Preload category icons (high priority, small number)
    func preloadCategoryIcons(urls: [(url: String, metadata: MenuImageMetadata)], completion: @escaping () -> Void) {
        guard cachingEnabled else {
            completion()
            return
        }
        
        guard !urls.isEmpty else {
            completion()
            return
        }
        
        DebugLogger.debug("🎯 Preloading \(urls.count) category icons...", category: "Cache")
        
        let group = DispatchGroup()
        
        for (url, metadata) in urls {
            // Check if already cached and up-to-date
            if getCachedImage(for: url) != nil && !needsUpdate(for: url, currentMetadata: metadata) {
                continue
            }
            
            group.enter()
            downloadAndCache(url: url, priority: .critical, metadata: metadata) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            DebugLogger.debug("✅ Category icons preloaded!", category: "Cache")
            completion()
        }
    }
    
    /// Preload menu item images (smart batching)
    func preloadMenuItems(urls: [(url: String, metadata: MenuImageMetadata)], batchSize: Int = 10, completion: @escaping (Int) -> Void) {
        guard cachingEnabled else {
            completion(0)
            return
        }
        
        guard !urls.isEmpty else {
            completion(0)
            return
        }
        
        DebugLogger.debug("📸 Preloading \(urls.count) menu item images (batch size: \(batchSize))...", category: "Cache")
        
        var loadedCount = 0
        let totalCount = urls.count
        
        // Filter to only items that need updating
        let itemsToLoad = urls.filter { (url, metadata) in
            getCachedImage(for: url) == nil || needsUpdate(for: url, currentMetadata: metadata)
        }
        
        guard !itemsToLoad.isEmpty else {
            DebugLogger.debug("✅ All menu items already cached!", category: "Cache")
            completion(0)
            return
        }
        
        DebugLogger.debug("🔄 Need to download \(itemsToLoad.count)/\(totalCount) items", category: "Cache")
        
        // Process in batches to avoid overwhelming the system
        func loadBatch(startIndex: Int) {
            let endIndex = min(startIndex + batchSize, itemsToLoad.count)
            guard startIndex < endIndex else {
                DebugLogger.debug("✅ Preloading complete! Loaded \(loadedCount)/\(itemsToLoad.count) items", category: "Cache")
                completion(loadedCount)
                return
            }
            
            let batch = Array(itemsToLoad[startIndex..<endIndex])
            let group = DispatchGroup()
            
            for item in batch {
                group.enter()
                downloadAndCache(url: item.url, priority: .normal, metadata: item.metadata) { image in
                    if image != nil {
                        loadedCount += 1
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // Load next batch
                loadBatch(startIndex: endIndex)
            }
        }
        
        loadBatch(startIndex: 0)
    }
    
    /// Cancel all pending downloads
    func cancelAllDownloads() {
        downloadTasksQueue.async(flags: .barrier) {
            for (url, task) in self.downloadTasks {
                task.cancel()
                DebugLogger.debug("🛑 Cancelled download: \(url)", category: "Cache")
            }
            self.downloadTasks.removeAll()
        }
    }
    
    /// Clear memory cache only (for memory warnings)
    func clearMemoryCache() {
        memoryCache.removeAll()
        DebugLogger.debug("🧹 Cleared menu image memory cache", category: "Cache")
    }
    
    /// Clear all cached images
    func clearCache() {
        // Cancel downloads
        cancelAllDownloads()
        
        // Clear memory cache
        memoryCache.removeAll()
        
        // Clear disk cache
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try? fileManager.removeItem(at: file)
            }
            DebugLogger.debug("🗑️ Cleared all cached menu images", category: "Cache")
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
    
    /// Get cached image count
    func getCachedImageCount() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return files.count
    }
    
    // MARK: - Private Helpers
    
    private func generateCacheKey(from url: String, fileExtension: String = "jpg") -> String {
        // Use SHA256 hash of URL as filename
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
        memoryCache[url] = image
        
        // Limit memory cache size (LRU-style)
        if memoryCache.count > memoryCacheLimit {
            // Remove oldest entries
            let toRemove = memoryCache.count - memoryCacheLimit
            let keysToRemove = Array(memoryCache.keys.prefix(toRemove))
            keysToRemove.forEach { memoryCache.removeValue(forKey: $0) }
        }
    }
    
    private func getCachedMetadata(for url: String) -> MenuImageMetadata? {
        guard cachingEnabled else { return nil }
        
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
            let metadataDict = try JSONDecoder().decode([String: MenuImageMetadata].self, from: data)
            return metadataDict[url]
        } catch {
            DebugLogger.debug("⚠️ Corrupted metadata detected, clearing cache: \(error.localizedDescription)", category: "Cache")
            DebugLogger.debug("🔧 Auto-disabling caching to prevent crashes", category: "Cache")
            // Clear ALL cache-related keys to be safe
            UserDefaults.standard.removeObject(forKey: metadataKey)
            UserDefaults.standard.removeObject(forKey: cacheVersionKey)
            UserDefaults.standard.set(false, forKey: "menuImageCachingEnabled")
            return nil
        }
    }
    
    private func saveCachedMetadata(for url: String, metadata: MenuImageMetadata) {
        var metadataDict: [String: MenuImageMetadata] = [:]
        
        // Try to load existing metadata, clear if corrupted
        if let data = UserDefaults.standard.data(forKey: metadataKey) {
            do {
                metadataDict = try JSONDecoder().decode([String: MenuImageMetadata].self, from: data)
            } catch {
                DebugLogger.debug("⚠️ Corrupted metadata during save, starting fresh: \(error.localizedDescription)", category: "Cache")
                UserDefaults.standard.removeObject(forKey: metadataKey)
                metadataDict = [:]
            }
        }
        
        metadataDict[url] = metadata
        
        do {
            let data = try JSONEncoder().encode(metadataDict)
            UserDefaults.standard.set(data, forKey: metadataKey)
        } catch {
            DebugLogger.debug("❌ Failed to encode metadata: \(error.localizedDescription)", category: "Cache")
        }
    }
    
    /// Check cache size and cleanup old images if needed (public for external triggers)
    func cleanupIfNeeded() {
        let currentSize = getCacheSize()
        
        if currentSize > maxCacheSize {
            DebugLogger.debug("⚠️ Cache size (\(formatBytes(Int(currentSize)))) exceeds limit (\(formatBytes(Int(maxCacheSize))))", category: "Cache")
            DebugLogger.debug("🧹 Cleaning up old images...", category: "Cache")
            
            // Get all cached files sorted by last access time
            guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]) else {
                return
            }
            
            let sortedFiles = files.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate ?? Date.distantPast
                return date1 < date2 // Oldest first
            }
            
            // Delete oldest files until we're under the limit
            var deletedSize: Int64 = 0
            var deletedCount = 0
            
            for file in sortedFiles {
                guard currentSize - deletedSize > maxCacheSize * 8 / 10 else { break } // Keep at 80% of max
                
                if let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    try? fileManager.removeItem(at: file)
                    deletedSize += Int64(fileSize)
                    deletedCount += 1
                }
            }
            
            DebugLogger.debug("✅ Cleaned up \(deletedCount) old images, freed \(formatBytes(Int(deletedSize)))", category: "Cache")
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Supporting Types
// ImageMetadata needs to be public for method signatures
struct MenuImageMetadata: Codable {
    let url: String
    let timestamp: Date
    
    init(url: String, timestamp: Date = Date()) {
        self.url = url
        self.timestamp = timestamp
    }
}

