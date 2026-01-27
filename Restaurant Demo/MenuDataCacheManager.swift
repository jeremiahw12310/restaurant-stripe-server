import Foundation

/// Manages persistent disk caching for menu data to reduce Firebase downloads.
/// Uses a stale-while-revalidate pattern: loads from cache instantly, then background refreshes if stale.
class MenuDataCacheManager {
    static let shared = MenuDataCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    /// Background queue for all disk I/O operations to prevent main thread blocking
    private let cacheQueue = DispatchQueue(label: "MenuDataCache.io", qos: .userInitiated)
    
    // MARK: - Cache Configuration
    
    /// How long menu data is considered fresh (default: 24 hours)
    var menuStalenessThreshold: TimeInterval = 24 * 60 * 60 // 24 hours
    
    /// How long static data (drink options, flavors, etc.) is considered fresh (default: 7 days)
    var staticDataStalenessThreshold: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    /// Cache version - increment to invalidate all caches when format changes
    private let cacheVersion = "2.1"
    private let cacheVersionKey = "menuDataCacheVersion"
    
    // MARK: - Cache Keys
    
    private enum CacheKey: String {
        case menuCategories = "menu_categories"
        case rewardAddItemMenu = "reward_add_item_menu"
        case drinkOptions = "drink_options"
        case drinkFlavors = "drink_flavors"
        case drinkToppings = "drink_toppings"
        case allergyTags = "allergy_tags"
        case menuOrder = "menu_order"
        case configPricing = "config_pricing"
    }
    
    enum TimestampKey: String, CaseIterable {
        case menuCategories = "menu_categories_timestamp"
        case rewardAddItemMenu = "reward_add_item_menu_timestamp"
        case drinkOptions = "drink_options_timestamp"
        case drinkFlavors = "drink_flavors_timestamp"
        case drinkToppings = "drink_toppings_timestamp"
        case allergyTags = "allergy_tags_timestamp"
        case menuOrder = "menu_order_timestamp"
        case configPricing = "config_pricing_timestamp"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Create cache directory in app's caches folder
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesURL.appendingPathComponent("MenuDataCache", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            validateCacheVersion()
        } catch {
            DebugLogger.debug("❌ Failed to create MenuDataCache directory: \(error)", category: "Cache")
        }
    }
    
    /// Validate cache version and clear if incompatible
    private func validateCacheVersion() {
        let storedVersion = UserDefaults.standard.string(forKey: cacheVersionKey)
        
        if storedVersion != cacheVersion {
            clearAllCaches()
            UserDefaults.standard.set(cacheVersion, forKey: cacheVersionKey)
        }
    }
    
    // MARK: - Menu Categories Cache
    
    /// Get cached menu categories synchronously (use async version preferred)
    func getCachedMenuCategories() -> [MenuCategory]? {
        return loadFromCache(key: .menuCategories, type: [MenuCategory].self)
    }
    
    /// Get cached menu categories asynchronously (preferred - doesn't block main thread)
    func getCachedMenuCategoriesAsync(completion: @escaping ([MenuCategory]?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .menuCategories, type: [MenuCategory].self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    /// Cache menu categories to disk asynchronously
    func cacheMenuCategories(_ categories: [MenuCategory]) {
        cacheQueue.async { [weak self] in
            self?.saveToCache(categories, key: .menuCategories, timestampKey: .menuCategories)
        }
    }
    
    /// Check if menu categories cache is stale
    func isMenuCategoriesStale() -> Bool {
        return isCacheStale(timestampKey: .menuCategories, threshold: menuStalenessThreshold)
    }
    
    /// Get last fetch date for menu categories
    func getMenuCategoriesLastFetchDate() -> Date? {
        return getTimestamp(for: .menuCategories)
    }

    // MARK: - Reward Add Item Menu Cache
    
    func getCachedRewardAddItemMenu() -> [MenuCategory]? {
        return loadFromCache(key: .rewardAddItemMenu, type: [MenuCategory].self)
    }
    
    func getCachedRewardAddItemMenuAsync(completion: @escaping ([MenuCategory]?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .rewardAddItemMenu, type: [MenuCategory].self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheRewardAddItemMenu(_ categories: [MenuCategory]) {
        cacheQueue.async { [weak self] in
            self?.saveToCache(categories, key: .rewardAddItemMenu, timestampKey: .rewardAddItemMenu)
        }
    }
    
    func isRewardAddItemMenuStale() -> Bool {
        return isCacheStale(timestampKey: .rewardAddItemMenu, threshold: menuStalenessThreshold)
    }
    
    func getRewardAddItemMenuLastFetchDate() -> Date? {
        return getTimestamp(for: .rewardAddItemMenu)
    }
    
    // MARK: - Drink Options Cache
    
    func getCachedDrinkOptions() -> [DrinkOption]? {
        return loadFromCache(key: .drinkOptions, type: [DrinkOption].self)
    }
    
    func getCachedDrinkOptionsAsync(completion: @escaping ([DrinkOption]?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .drinkOptions, type: [DrinkOption].self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheDrinkOptions(_ options: [DrinkOption]) {
        cacheQueue.async { [weak self] in
            self?.saveToCache(options, key: .drinkOptions, timestampKey: .drinkOptions)
        }
    }
    
    func isDrinkOptionsStale() -> Bool {
        return isCacheStale(timestampKey: .drinkOptions, threshold: staticDataStalenessThreshold)
    }
    
    // MARK: - Drink Flavors Cache
    
    func getCachedDrinkFlavors() -> [DrinkFlavor]? {
        return loadFromCache(key: .drinkFlavors, type: [DrinkFlavor].self)
    }
    
    func getCachedDrinkFlavorsAsync(completion: @escaping ([DrinkFlavor]?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .drinkFlavors, type: [DrinkFlavor].self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheDrinkFlavors(_ flavors: [DrinkFlavor]) {
        cacheQueue.async { [weak self] in
            self?.saveToCache(flavors, key: .drinkFlavors, timestampKey: .drinkFlavors)
        }
    }
    
    func isDrinkFlavorsStale() -> Bool {
        return isCacheStale(timestampKey: .drinkFlavors, threshold: staticDataStalenessThreshold)
    }
    
    // MARK: - Drink Toppings Cache
    
    func getCachedDrinkToppings() -> [DrinkTopping]? {
        return loadFromCache(key: .drinkToppings, type: [DrinkTopping].self)
    }
    
    func getCachedDrinkToppingsAsync(completion: @escaping ([DrinkTopping]?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .drinkToppings, type: [DrinkTopping].self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheDrinkToppings(_ toppings: [DrinkTopping]) {
        cacheQueue.async { [weak self] in
            self?.saveToCache(toppings, key: .drinkToppings, timestampKey: .drinkToppings)
        }
    }
    
    func isDrinkToppingsStale() -> Bool {
        return isCacheStale(timestampKey: .drinkToppings, threshold: staticDataStalenessThreshold)
    }
    
    // MARK: - Allergy Tags Cache
    
    func getCachedAllergyTags() -> [AllergyTag]? {
        return loadFromCache(key: .allergyTags, type: [AllergyTag].self)
    }
    
    func getCachedAllergyTagsAsync(completion: @escaping ([AllergyTag]?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .allergyTags, type: [AllergyTag].self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheAllergyTags(_ tags: [AllergyTag]) {
        cacheQueue.async { [weak self] in
            self?.saveToCache(tags, key: .allergyTags, timestampKey: .allergyTags)
        }
    }
    
    func isAllergyTagsStale() -> Bool {
        return isCacheStale(timestampKey: .allergyTags, threshold: staticDataStalenessThreshold)
    }
    
    // MARK: - Menu Order Cache
    
    struct MenuOrderData: Codable {
        var orderedCategoryIds: [String]
        var orderedItemIdsByCategory: [String: [String]]
    }
    
    func getCachedMenuOrder() -> MenuOrderData? {
        return loadFromCache(key: .menuOrder, type: MenuOrderData.self)
    }
    
    func getCachedMenuOrderAsync(completion: @escaping (MenuOrderData?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .menuOrder, type: MenuOrderData.self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheMenuOrder(orderedCategoryIds: [String], orderedItemIdsByCategory: [String: [String]]) {
        let orderData = MenuOrderData(
            orderedCategoryIds: orderedCategoryIds,
            orderedItemIdsByCategory: orderedItemIdsByCategory
        )
        cacheQueue.async { [weak self] in
            self?.saveToCache(orderData, key: .menuOrder, timestampKey: .menuOrder)
        }
    }
    
    func isMenuOrderStale() -> Bool {
        return isCacheStale(timestampKey: .menuOrder, threshold: menuStalenessThreshold)
    }
    
    // MARK: - Config/Pricing Cache
    
    struct ConfigPricing: Codable {
        var halfAndHalfPrice: Double
    }
    
    func getCachedConfigPricing() -> ConfigPricing? {
        return loadFromCache(key: .configPricing, type: ConfigPricing.self)
    }
    
    func getCachedConfigPricingAsync(completion: @escaping (ConfigPricing?) -> Void) {
        cacheQueue.async { [weak self] in
            let result = self?.loadFromCache(key: .configPricing, type: ConfigPricing.self)
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func cacheConfigPricing(halfAndHalfPrice: Double) {
        let config = ConfigPricing(halfAndHalfPrice: halfAndHalfPrice)
        cacheQueue.async { [weak self] in
            self?.saveToCache(config, key: .configPricing, timestampKey: .configPricing)
        }
    }
    
    func isConfigPricingStale() -> Bool {
        return isCacheStale(timestampKey: .configPricing, threshold: menuStalenessThreshold)
    }
    
    // MARK: - Bulk Async Loading
    
    /// Result struct for bulk cache loading
    struct CachedMenuData {
        var menuCategories: [MenuCategory]?
        var drinkOptions: [DrinkOption]?
        var drinkFlavors: [DrinkFlavor]?
        var drinkToppings: [DrinkTopping]?
        var allergyTags: [AllergyTag]?
        var menuOrder: MenuOrderData?
        var configPricing: ConfigPricing?
    }
    
    /// Load all cached menu data asynchronously in one batch (most efficient)
    func loadAllCachedDataAsync(completion: @escaping (CachedMenuData) -> Void) {
        cacheQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(CachedMenuData()) }
                return
            }
            
            let result = CachedMenuData(
                menuCategories: self.loadFromCache(key: .menuCategories, type: [MenuCategory].self),
                drinkOptions: self.loadFromCache(key: .drinkOptions, type: [DrinkOption].self),
                drinkFlavors: self.loadFromCache(key: .drinkFlavors, type: [DrinkFlavor].self),
                drinkToppings: self.loadFromCache(key: .drinkToppings, type: [DrinkTopping].self),
                allergyTags: self.loadFromCache(key: .allergyTags, type: [AllergyTag].self),
                menuOrder: self.loadFromCache(key: .menuOrder, type: MenuOrderData.self),
                configPricing: self.loadFromCache(key: .configPricing, type: ConfigPricing.self)
            )
            
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    // MARK: - Cache Management
    
    /// Force refresh all caches on next fetch (marks all as stale)
    func invalidateAllCaches() {
        for key in TimestampKey.allCases {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }
    
    /// Clear all cached data from disk
    func clearAllCaches() {
        // Clear timestamps
        invalidateAllCaches()
        
        // Clear cache files
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            DebugLogger.debug("❌ Failed to clear menu data cache: \(error)", category: "Cache")
        }
    }
    
    /// Get total cache size in bytes
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
    
    /// Get formatted cache size string
    func getFormattedCacheSize() -> String {
        let bytes = getCacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Private Helpers
    
    private func cacheFileURL(for key: CacheKey) -> URL {
        return cacheDirectory.appendingPathComponent("\(key.rawValue).json")
    }
    
    private func saveToCache<T: Encodable>(_ data: T, key: CacheKey, timestampKey: TimestampKey) {
        let fileURL = cacheFileURL(for: key)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: fileURL)
            
            // Save timestamp
            UserDefaults.standard.set(Date(), forKey: timestampKey.rawValue)
            
        } catch {
            DebugLogger.debug("❌ Failed to cache \(key.rawValue): \(error)", category: "Cache")
        }
    }
    
    private func loadFromCache<T: Decodable>(key: CacheKey, type: T.Type) -> T? {
        let fileURL = cacheFileURL(for: key)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            DebugLogger.debug("⚠️ Failed to load cache for \(key.rawValue): \(error)", category: "Cache")
            // Remove corrupted cache file
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }
    
    private func getTimestamp(for key: TimestampKey) -> Date? {
        return UserDefaults.standard.object(forKey: key.rawValue) as? Date
    }
    
    private func isCacheStale(timestampKey: TimestampKey, threshold: TimeInterval) -> Bool {
        guard let timestamp = getTimestamp(for: timestampKey) else {
            return true // No timestamp means never fetched
        }
        
        let age = Date().timeIntervalSince(timestamp)
        return age > threshold
    }
}
