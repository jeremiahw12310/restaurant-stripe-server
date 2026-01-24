import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import Kingfisher

class MenuViewModel: ObservableObject {
    @Published var menuCategories = [MenuCategory]()
    @Published var isLoading = true
    @Published var errorMessage = ""
    @Published var halfAndHalfPrice: Double = 13.99 // Default price for half and half dumplings
    @Published var drinkOptions: [DrinkOption] = [] // All global toppings and milk subs
    @Published var allergyTags: [AllergyTag] = [] // All reusable allergy tags
    @Published var loadingCategories: Set<String> = [] // Tracks categories currently loading
    @Published var isRefreshing = false // For pull-to-refresh UI
    @Published var lastMenuUpdate: Date? // Track when menu was last fetched
    
    // MARK: - Image Caching
    @Published var cachedCategoryIcons: [String: UIImage] = [:] // Cached category icons for instant display
    @Published var cachedItemImages: [String: UIImage] = [:] // Cached menu item images for instant display
    
    // MARK: - Data Caching (Firebase optimization)
    private let dataCacheManager = MenuDataCacheManager.shared
    
    // SAFETY: Only initialize cache manager if it's safe to do so
    private var imageCacheManager: MenuImageCacheManager? {
        // Check if caching is explicitly disabled
        if UserDefaults.standard.object(forKey: "disableAllImageCaching") as? Bool == true {
            print("⚠️ Image caching completely disabled by safety flag")
            return nil
        }
        // Try to access the cache manager safely
        return MenuImageCacheManager.shared
    }
    
    // Computed property to get all menu items across all categories
    var allMenuItems: [MenuItem] {
        return menuCategories.flatMap { category in
            category.items ?? []
        }
    }
    
    // Computed property to get menu categories in the correct order
    var orderedMenuCategories: [MenuCategory] {
        if orderedCategoryIds.isEmpty {
            // If no order is set, return categories as they are
            return menuCategories
        }
        
        // Create a dictionary for quick lookup
        let categoryDict = Dictionary(uniqueKeysWithValues: menuCategories.map { ($0.id, $0) })
        
        // Return categories in the order specified by orderedCategoryIds
        var orderedCategories: [MenuCategory] = []
        for categoryId in orderedCategoryIds {
            if let category = categoryDict[categoryId] {
                orderedCategories.append(category)
            }
        }
        
        // Add any categories that aren't in the ordered list at the end
        for category in menuCategories {
            if !orderedCategoryIds.contains(category.id) {
                orderedCategories.append(category)
            }
        }
        
        return orderedCategories
    }

    /// The single category marked as the toppings category (if any).
    var toppingsCategory: MenuCategory? {
        return menuCategories.first(where: { $0.isToppingCategory })
    }

    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private let orderDocRef = Firestore.firestore().collection("menuOrder").document("order")
    private let configDocRef = Firestore.firestore().collection("config").document("pricing")
    @Published var orderedCategoryIds: [String] = []
    @Published var orderedItemIdsByCategory: [String: [String]] = [:]
    private var itemListeners: [String: ListenerRegistration] = [:]
    private var orderListener: ListenerRegistration?
    private var configListener: ListenerRegistration?
    private var isFetchingMenu = false // Prevent concurrent fetches
    private var drinkOptionsListener: ListenerRegistration?
    private var allergyTagsListener: ListenerRegistration?
    private var isAdminUser: Bool = false

    // MARK: - Firestore doc ID normalization
    /// Some legacy menu item documents may use non-canonical Firestore doc IDs.
    /// We treat the canonical docID for an item as a sanitized version of the item's `id` field.
    private func sanitizeMenuItemDocumentId(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "(", with: "_")
            .replacingOccurrences(of: ")", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Deduplicate menu items that share the same `id` field, preferring the canonical docID.
    private func dedupeMenuItemsFromSnapshot(categoryId: String, documents: [QueryDocumentSnapshot]) -> [MenuItem] {
        // Keep the chosen item per id
        var chosen: [String: (docId: String, item: MenuItem)] = [:]
        // Track duplicates for logging
        var duplicates: [String: [(docId: String, description: String)]] = [:]

        for doc in documents {
            do {
                let item = try doc.data(as: MenuItem.self)
                let itemId = item.id
                let docId = doc.documentID
                let canonicalDocId = sanitizeMenuItemDocumentId(itemId)

                if let existing = chosen[itemId] {
                    // record existing + new in duplicates list
                    if duplicates[itemId] == nil {
                        duplicates[itemId] = [(existing.docId, existing.item.description)]
                    }
                    duplicates[itemId]?.append((docId, item.description))

                    // Prefer canonical docID if present
                    let existingIsCanonical = existing.docId == canonicalDocId
                    let newIsCanonical = docId == canonicalDocId
                    if !existingIsCanonical && newIsCanonical {
                        chosen[itemId] = (docId, item)
                    }
                } else {
                    chosen[itemId] = (docId, item)
                }
            } catch {
                print("❌ Decoding error for item \(doc.documentID) in category \(categoryId): \(error)")
            }
        }

        // Note: Duplicate detection still happens, just without verbose logging
        // Duplicates are handled by keeping the canonical document

        return chosen.values.map { $0.item }
    }

    init() {
        // Always fetch from Firebase to ensure menu loads reliably
        isLoading = true
        
        // Fetch config first (small, fast)
        fetchConfig()
        
        // Always fetch menu from Firebase - this is the reliable path
        fetchMenu()
        
        // Defer static data loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.fetchStaticDataIfStale()
        }
    }
    
    /// Fetch static data only if cache is stale (7 days for static data)
    private func fetchStaticDataIfStale() {
        if dataCacheManager.isDrinkOptionsStale() {
            fetchDrinkOptions()
        }
        if dataCacheManager.isAllergyTagsStale() {
            fetchAllergyTags()
        }
        if dataCacheManager.isDrinkFlavorsStale() {
            fetchDrinkFlavors()
        }
        if dataCacheManager.isDrinkToppingsStale() {
            fetchDrinkToppings()
        }
    }
    
    /// Start the menu order listener only if the user is an admin.
    /// This prevents permission errors and crashes for non-admin users.
    /// Call this from views that have access to UserViewModel when admin status is known.
    func startMenuOrderListenerIfAdmin(isAdmin: Bool) {
        // Menu order is public-read in Firestore rules, and all users should apply the admin-defined order.
        // We still keep the isAdmin flag to prevent non-admins from attempting to create a default order doc.
        self.isAdminUser = isAdmin
        
        if isAdmin {
            // Admins get real-time listeners for editing
            listenToMenuOrder()
        }
        // Non-admins already loaded menu order from cache or one-time fetch in init()
    }
    
    /// Enable admin editing mode - starts real-time listeners for all data
    /// Call this when admin enters the menu editing screen
    func enableAdminEditingMode() {
        print("🔐 Admin editing mode enabled - starting real-time listeners")
        isAdminUser = true
        
        // Start real-time listeners for admin editing
        startMenuListenerForAdmin()
        startConfigListenerForAdmin()
        startDrinkOptionsListenerForAdmin()
        startDrinkFlavorsListenerForAdmin()
        startDrinkToppingsListenerForAdmin()
        startAllergyTagsListenerForAdmin()
        listenToMenuOrder()
    }
    
    /// Disable admin editing mode - stops real-time listeners and caches current data
    /// Call this when admin leaves the menu editing screen
    func disableAdminEditingMode() {
        print("🔐 Admin editing mode disabled - stopping listeners and caching data")
        
        // Stop all real-time listeners
        listenerRegistration?.remove()
        listenerRegistration = nil
        for (_, listener) in itemListeners {
            listener.remove()
        }
        itemListeners.removeAll()
        configListener?.remove()
        configListener = nil
        drinkOptionsListener?.remove()
        drinkOptionsListener = nil
        drinkFlavorsListener?.remove()
        drinkFlavorsListener = nil
        drinkToppingsListener?.remove()
        drinkToppingsListener = nil
        allergyTagsListener?.remove()
        allergyTagsListener = nil
        orderListener?.remove()
        orderListener = nil
        
        // Cache current data for other users
        dataCacheManager.cacheMenuCategories(menuCategories)
        dataCacheManager.cacheMenuOrder(orderedCategoryIds: orderedCategoryIds, orderedItemIdsByCategory: orderedItemIdsByCategory)
        dataCacheManager.cacheConfigPricing(halfAndHalfPrice: halfAndHalfPrice)
        dataCacheManager.cacheDrinkOptions(drinkOptions)
        dataCacheManager.cacheDrinkFlavors(drinkFlavors)
        dataCacheManager.cacheDrinkToppings(drinkToppings)
        dataCacheManager.cacheAllergyTags(allergyTags)
    }
    
    /// Start real-time listener for menu categories and items (only for admin editing)
    private func startMenuListenerForAdmin() {
        listenerRegistration?.remove()
        for (_, listener) in itemListeners {
            listener.remove()
        }
        itemListeners.removeAll()
        
        listenerRegistration = db.collection("menu").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("❌ Error fetching menu categories: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else { return }
            
            // Build categories
            var newCategories: [MenuCategory] = documents.map { doc in
                let data = doc.data()
                return MenuCategory(
                    id: doc.documentID,
                    items: self.menuCategories.first(where: { $0.id == doc.documentID })?.items ?? [],
                    subCategories: nil,
                    isDrinks: data["isDrinks"] as? Bool ?? false,
                    lemonadeSodaEnabled: data["lemonadeSodaEnabled"] as? Bool ?? false,
                    isToppingCategory: data["isToppingCategory"] as? Bool ?? false,
                    icon: data["icon"] as? String ?? "",
                    hideIcon: data["hideIcon"] as? Bool ?? false
                )
            }
            
            // Set up item listeners for each category
            for (index, document) in documents.enumerated() {
                let categoryId = document.documentID
                
                let itemListener = self.db.collection("menu").document(categoryId).collection("items").addSnapshotListener { [weak self] (itemsSnapshot, itemsError) in
                    guard let self = self else { return }
                    if let itemsSnapshot = itemsSnapshot {
                        let items = self.dedupeMenuItemsFromSnapshot(categoryId: categoryId, documents: itemsSnapshot.documents)
                        DispatchQueue.main.async {
                            if let catIndex = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                                self.menuCategories[catIndex].items = items.sorted { $0.id < $1.id }
                            }
                        }
                    }
                }
                self.itemListeners[categoryId] = itemListener
            }
            
            self.menuCategories = newCategories.sorted { $0.id < $1.id }
        }
    }
    
    deinit {
        // Stop listening for changes when the view model is deallocated.
        listenerRegistration?.remove()
        orderListener?.remove()
        configListener?.remove()
        drinkOptionsListener?.remove()
        allergyTagsListener?.remove()
        drinkFlavorsListener?.remove()
        drinkToppingsListener?.remove()
    }

    func loadMenuItems() {
        // This method is called by MenuItemPickerView to ensure menu items are loaded
        fetchMenu()
    }

    // MARK: - Admin Helper
    
    private func isPermissionDeniedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == FirestoreErrorCode.permissionDenied.rawValue
    }
    
    private func friendlyPermissionDeniedMessage(action: String) -> String {
        return """
        Missing or insufficient permissions while trying to \(action).
        
        This usually means one of:
        - Your account is not marked as admin in Firestore: users/{uid}.isAdmin must be boolean true
        - Firestore rules were not deployed to the same Firebase project your app is using
        """
    }
    
    private func requireAdmin(_ completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false, "User not authenticated. Please sign in.")
            return
        }
        
        let userRef = db.collection("users").document(user.uid)
        userRef.getDocument { (document, error) in
            if let error = error {
                print("❌ requireAdmin: Error reading users/\(user.uid): \(error.localizedDescription)")
                completion(false, "Error checking admin status: \(error.localizedDescription)")
                return
            }
            guard let document = document, document.exists else {
                print("❌ requireAdmin: users/\(user.uid) does not exist")
                completion(false, "User profile not found. Please contact support.")
                return
            }
            
            let data = document.data() ?? [:]
            let isAdminValue = data["isAdmin"]
            let isAdminType = isAdminValue.map { String(describing: Swift.type(of: $0)) } ?? "nil"
            print("🔐 requireAdmin: users/\(user.uid) exists. isAdmin=\(String(describing: isAdminValue)) type=\(isAdminType)")
            
            // Strongly validate: security rules require boolean true.
            if isAdminValue != nil && (isAdminValue as? Bool) == nil {
                completion(false, "Admin flag is invalid. users/{uid}.isAdmin must be boolean true.")
                return
            }
            
            let isAdmin = isAdminValue as? Bool ?? false
            if !isAdmin {
                completion(false, "Admin privileges required.")
                return
            }
            
            completion(true, nil)
        }
    }
    
    func fetchMenu() {
        // Prevent concurrent fetches
        guard !isFetchingMenu else {
            return
        }
        
        isFetchingMenu = true
        isLoading = true

        // Remove any previous listeners to prevent memory leaks
        listenerRegistration?.remove()
        listenerRegistration = nil
        for (_, listener) in itemListeners {
            listener.remove()
        }
        itemListeners.removeAll()

        // Use snapshot listener instead of getDocuments - more reliable
        listenerRegistration = db.collection("menu").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error fetching menu categories: \(error.localizedDescription)")
                self.isLoading = false
                self.isFetchingMenu = false
                return
            }
            
            guard let documents = snapshot?.documents else {
                self.isLoading = false
                self.isFetchingMenu = false
                return
            }

            // Build categories with flags from Firestore
            var newCategories: [MenuCategory] = documents.map { doc in
                let data = doc.data()
                return MenuCategory(
                    id: doc.documentID,
                    items: [],
                    subCategories: nil,
                    isDrinks: data["isDrinks"] as? Bool ?? false,
                    lemonadeSodaEnabled: data["lemonadeSodaEnabled"] as? Bool ?? false,
                    isToppingCategory: data["isToppingCategory"] as? Bool ?? false,
                    icon: data["icon"] as? String ?? "",
                    hideIcon: data["hideIcon"] as? Bool ?? false
                )
            }
            
            // Update categories immediately (items will load separately)
            self.menuCategories = newCategories.sorted { $0.id < $1.id }

            // Set up item listeners for each category
            for document in documents {
                let categoryId = document.documentID
                
                // Skip if we already have a listener for this category
                if self.itemListeners[categoryId] != nil { continue }
                
                let itemListener = self.db.collection("menu").document(categoryId).collection("items").addSnapshotListener { [weak self] (itemsSnapshot, itemsError) in
                    guard let self = self else { return }
                    
                    var items: [MenuItem] = []
                    if let itemsSnapshot = itemsSnapshot {
                        items = self.dedupeMenuItemsFromSnapshot(categoryId: categoryId, documents: itemsSnapshot.documents)
                    }
                    
                    DispatchQueue.main.async {
                        if let catIndex = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                            self.menuCategories[catIndex].items = items.sorted { $0.id < $1.id }
                        }
                        
                        // Mark loading complete after first category loads items
                        if self.isLoading {
                            self.isLoading = false
                            self.isFetchingMenu = false
                            self.isRefreshing = false
                            self.lastMenuUpdate = Date()
                            
                            // Cache menu data after first load
                            self.dataCacheManager.cacheMenuCategories(self.menuCategories)
                            
                            // Load cached images immediately and check for updates
                            self.preloadCachedImages()
                        }
                    }
                }
                self.itemListeners[categoryId] = itemListener
            }
        }
        
        // Also fetch menu order
        fetchMenuOrder()
    }
    
    /// One-time fetch for menu order (replaces real-time listener for non-admin users)
    private func fetchMenuOrder() {
        orderDocRef.getDocument { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("⚠️ Error fetching menu order: \(error.localizedDescription)")
                return
            }
            
            guard let document = documentSnapshot, document.exists else {
                return // No menu order document, use default ordering
            }
            
            let data = document.data() ?? [:]
            
            let orderedCategoryIds =
                (data["orderedCategoryIds"] as? [String])
                ?? (data["categories"] as? [String])
                ?? []
            
            let orderedItemIdsByCategory =
                (data["orderedItemIdsByCategory"] as? [String: [String]])
                ?? (data["itemsByCategory"] as? [String: [String]])
                ?? [:]
            
            DispatchQueue.main.async {
                self.orderedCategoryIds = orderedCategoryIds
                self.orderedItemIdsByCategory = orderedItemIdsByCategory
                
                // Cache the menu order
                self.dataCacheManager.cacheMenuOrder(
                    orderedCategoryIds: orderedCategoryIds,
                    orderedItemIdsByCategory: orderedItemIdsByCategory
                )
            }
        }
    }
    
    /// Force refresh menu from network (for pull-to-refresh)
    func forceRefreshMenu() {
        isRefreshing = true
        
        // Invalidate cache to force fresh fetch
        dataCacheManager.invalidateAllCaches()
        
        // Fetch fresh data
        fetchMenu()
        fetchStaticDataIfStale()
    }
    
    // MARK: - Cache Status (for debugging/monitoring)
    
    /// Get current cache status for debugging
    func getCacheStatus() -> String {
        var status = "=== Menu Data Cache Status ===\n"
        
        // Menu categories
        let menuStale = dataCacheManager.isMenuCategoriesStale()
        let menuDate = dataCacheManager.getMenuCategoriesLastFetchDate()?.formatted() ?? "Never"
        status += "Menu Categories: \(menuStale ? "STALE" : "FRESH") (Last: \(menuDate))\n"
        
        // Static data
        status += "Drink Options: \(dataCacheManager.isDrinkOptionsStale() ? "STALE" : "FRESH")\n"
        status += "Drink Flavors: \(dataCacheManager.isDrinkFlavorsStale() ? "STALE" : "FRESH")\n"
        status += "Drink Toppings: \(dataCacheManager.isDrinkToppingsStale() ? "STALE" : "FRESH")\n"
        status += "Allergy Tags: \(dataCacheManager.isAllergyTagsStale() ? "STALE" : "FRESH")\n"
        status += "Config Pricing: \(dataCacheManager.isConfigPricingStale() ? "STALE" : "FRESH")\n"
        
        // Cache size
        status += "Cache Size: \(dataCacheManager.getFormattedCacheSize())\n"
        
        // Current data counts
        status += "\n=== Current Data ===\n"
        status += "Categories: \(menuCategories.count)\n"
        status += "Total Items: \(allMenuItems.count)\n"
        status += "Drink Options: \(drinkOptions.count)\n"
        status += "Drink Flavors: \(drinkFlavors.count)\n"
        status += "Drink Toppings: \(drinkToppings.count)\n"
        status += "Allergy Tags: \(allergyTags.count)\n"
        
        return status
    }
    
    /// Print cache status to console (for debugging)
    func printCacheStatus() {
        print(getCacheStatus())
    }
    
    // MARK: - Image Caching Methods
    
    /// Main orchestration method for image caching
    /// Loads cached images immediately, then checks for updates in background
    private func preloadCachedImages() {
        // Step 1: Load existing cached images immediately (instant display)
        loadCachedCategoryIcons()
        loadCachedMenuItemImages()
        
        // Step 2: Cleanup cache if needed on app launch
        if let cacheManager = imageCacheManager {
            DispatchQueue.global(qos: .utility).async {
                cacheManager.cleanupIfNeeded()
            }
        }
        
        // Step 3: Check for updates and download new/changed images in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.checkForImageUpdates()
        }
    }
    
    /// Public method to reload cached images (useful when app becomes active)
    func reloadCachedImages() {
        // Only reload if we have menu data loaded
        guard !menuCategories.isEmpty else { return }
        
        // Reload cached images from disk
        loadCachedCategoryIcons()
        loadCachedMenuItemImages()
    }
    
    /// Load category icons from disk cache into published dictionary for instant display
    private func loadCachedCategoryIcons() {
        guard let cacheManager = imageCacheManager else { return }
        
        var icons: [String: UIImage] = [:]
        for category in menuCategories {
            if let iconString = effectiveIconString(for: category),
               let url = resolveIconURL(iconString) {
                let urlString = url.absoluteString
                if let cachedImage = cacheManager.getCachedImage(for: urlString) {
                    icons[urlString] = cachedImage
                }
            }
        }
        
        DispatchQueue.main.async {
            self.cachedCategoryIcons = icons
            print("✅ Loaded \(icons.count) cached category icons from disk")
        }
    }
    
    /// Load menu item images from disk cache into published dictionary for instant display
    private func loadCachedMenuItemImages() {
        guard let cacheManager = imageCacheManager else { return }
        
        let allItems = menuCategories.flatMap { category in
            var items: [MenuItem] = []
            if let categoryItems = category.items {
                items.append(contentsOf: categoryItems)
            }
            if let subCategories = category.subCategories {
                for subCategory in subCategories {
                    items.append(contentsOf: subCategory.items)
                }
            }
            return items
        }
        
        // Load in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var images: [String: UIImage] = [:]
            for item in allItems {
                guard !item.imageURL.isEmpty,
                      let url = item.resolvedImageURL else {
                    continue
                }
                let urlString = url.absoluteString
                if let cachedImage = cacheManager.getCachedImage(for: urlString) {
                    images[urlString] = cachedImage
                }
            }
            
            DispatchQueue.main.async {
                self.cachedItemImages = images
                print("✅ Loaded \(images.count) cached menu item images from disk")
            }
        }
    }
    
    /// Check for image updates and download only changed/new images
    private func checkForImageUpdates() {
        guard let cacheManager = imageCacheManager else { return }
        
        // Build category icon URLs with metadata
        var categoryIconURLs: [(url: String, metadata: MenuImageMetadata)] = []
        for category in menuCategories {
            if let iconString = effectiveIconString(for: category),
               let url = resolveIconURL(iconString) {
                let urlString = url.absoluteString
                // Use current timestamp as metadata since Firestore doesn't store image timestamps
                let metadata = MenuImageMetadata(url: urlString, timestamp: Date())
                categoryIconURLs.append((url: urlString, metadata: metadata))
            }
        }
        
        // Preload category icons (high priority)
        if !categoryIconURLs.isEmpty {
            cacheManager.preloadCategoryIcons(urls: categoryIconURLs) { [weak self] in
                guard let self = self else { return }
                // Reload cached icons after preloading completes to include newly cached images
                self.loadCachedCategoryIcons()
                
                // Cleanup cache if needed after preloading
                cacheManager.cleanupIfNeeded()
            }
        }
        
        // Build menu item image URLs with metadata
        let allItems = menuCategories.flatMap { category in
            var items: [MenuItem] = []
            if let categoryItems = category.items {
                items.append(contentsOf: categoryItems)
            }
            if let subCategories = category.subCategories {
                for subCategory in subCategories {
                    items.append(contentsOf: subCategory.items)
                }
            }
            return items
        }
        
        var menuItemURLs: [(url: String, metadata: MenuImageMetadata)] = []
        for item in allItems {
            guard !item.imageURL.isEmpty,
                  let url = item.resolvedImageURL else {
                continue
            }
            let urlString = url.absoluteString
            // Use current timestamp as metadata since Firestore doesn't store image timestamps
            let metadata = MenuImageMetadata(url: urlString, timestamp: Date())
            menuItemURLs.append((url: urlString, metadata: metadata))
        }
        
        // Preload menu items in background (lower priority)
        if !menuItemURLs.isEmpty {
            cacheManager.preloadMenuItems(urls: menuItemURLs, batchSize: 10) { [weak self] loadedCount in
                guard let self = self else { return }
                print("✅ Preloaded \(loadedCount) menu item images")
                // Reload cached images after preloading completes to include newly cached images
                self.loadCachedMenuItemImages()
                
                // Cleanup cache if needed after preloading completes
                cacheManager.cleanupIfNeeded()
            }
        }
    }
    
    /// Helper method to get effective icon string for a category (mirrors CategoryRow logic)
    private func effectiveIconString(for category: MenuCategory) -> String? {
        if !category.icon.isEmpty { return category.icon }
        let key = category.id.lowercased()
        if key == "dumplings" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/Subject.png?alt=media"
        } else if key == "soups" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/wontonsoup-2.png?alt=media"
        } else if key == "appetizers" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/eda.png?alt=media"
        } else if key == "coke products" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/coke.png?alt=media"
        } else if key == "sauces" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/peanut.png?alt=media"
        }
        return nil
    }
    
    /// Helper method to resolve icon URL (mirrors CategoryRow logic)
    private func resolveIconURL(_ icon: String) -> URL? {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("gs://") {
            let components = trimmed.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                let partiallyEncoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                let encodedPath = partiallyEncoded.replacingOccurrences(of: "/", with: "%2F")
                let candidates = [
                    "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media",
                    "https://storage.googleapis.com/\(bucketName)/\(filePath)"
                ]
                for candidate in candidates {
                    if let url = URL(string: candidate) {
                        return url
                    }
                }
            }
        } else if trimmed.hasPrefix("http") {
            return URL(string: trimmed)
        }
        return nil
    }

    // Helper to sync the items array field with the items subcollection
    private func syncItemsArrayField(categoryId: String, completion: (() -> Void)? = nil) {
        let itemsCollection = db.collection("menu").document(categoryId).collection("items")
        itemsCollection.getDocuments { [weak self] (snapshot, error) in
            guard let self = self, let snapshot = snapshot else {
                completion?()
                return
            }
            
            let itemsArray = snapshot.documents.compactMap { try? $0.data(as: MenuItem.self) }
            let itemsDictArray = itemsArray.map { item in
                [
                    "id": item.id,
                    "description": item.description,
                    "price": item.price,
                    "imageURL": item.imageURL,
                    "isAvailable": item.isAvailable,
                    "paymentLinkID": item.paymentLinkID,
                    "isDumpling": item.isDumpling,
                    "toppingModifiersEnabled": item.toppingModifiersEnabled,
                    "milkSubModifiersEnabled": item.milkSubModifiersEnabled,
                    "availableToppingIDs": item.availableToppingIDs,
                    "availableMilkSubIDs": item.availableMilkSubIDs,
                    "allergyTagIDs": item.allergyTagIDs
                ] as [String: Any]
            }
            
            self.db.collection("menu").document(categoryId).updateData([
                "items": itemsDictArray
            ]) { _ in
                completion?()
            }
        }
    }

    /// Adds a new item to a specific category in Firestore
    func addItemToCategory(categoryId: String, item: MenuItem, completion: @escaping (Bool, String?) -> Void) {
        guard !categoryId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false, "Category ID cannot be empty.")
            return
        }
        
        let categoryRef = db.collection("menu").document(categoryId)
        let itemsCollection = categoryRef.collection("items")
        
        // Sanitize the document ID to remove invalid characters
        let sanitizedId = item.id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "(", with: "_")
            .replacingOccurrences(of: ")", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        
        // Add item to subcollection
        itemsCollection.document(sanitizedId).setData([
            "id": item.id,
            "description": item.description,
            "price": item.price,
            "imageURL": item.imageURL,
            "isAvailable": item.isAvailable,
            "paymentLinkID": item.paymentLinkID,
            "isDumpling": item.isDumpling,
            "toppingModifiersEnabled": item.toppingModifiersEnabled,
            "milkSubModifiersEnabled": item.milkSubModifiersEnabled,
            "availableToppingIDs": item.availableToppingIDs,
            "availableMilkSubIDs": item.availableMilkSubIDs,
            "allergyTagIDs": item.allergyTagIDs
        ]) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                self.syncItemsArrayField(categoryId: categoryId) {
                    // If this is Coke products, also add to menu order
                    if categoryId == "Coke products" {
                        self.addItemToMenuOrder(categoryId: categoryId, itemId: item.id) {
                            completion(true, nil)
                        }
                    } else {
                        completion(true, nil)
                    }
                }
            }
        }
    }

    /// Updates an item in a specific category in Firestore
    func updateItemInCategory(categoryId: String, oldItem: MenuItem, newItem: MenuItem, completion: @escaping (Bool, String?) -> Void) {
        let categoryRef = db.collection("menu").document(categoryId)
        let itemsCollection = categoryRef.collection("items")
        
        func sanitizeDocumentId(_ raw: String) -> String {
            raw.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: "(", with: "_")
                .replacingOccurrences(of: ")", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        }
        
        // Sanitize the old and new document IDs
        let oldSanitizedId = sanitizeDocumentId(oldItem.id)
        let newSanitizedId = sanitizeDocumentId(newItem.id)
        
        func verifyWriteAndFinish(updatedDocRef: DocumentReference) {
            let expectedDescription = newItem.description
            
            func cleanupDuplicatesForCurrentItem(done: @escaping () -> Void) {
                let currentItemId = newItem.id
                let preferredCanonicalDocId = newSanitizedId
                let fallbackCanonicalDocId = updatedDocRef.documentID
                
                itemsCollection
                    .whereField("id", isEqualTo: currentItemId)
                    .getDocuments { querySnapshot, queryError in
                        if queryError != nil {
                            done()
                            return
                        }
                        
                        let docs = querySnapshot?.documents ?? []
                        guard docs.count > 1 else {
                            done()
                            return
                        }
                        
                        let docIds = docs.map { $0.documentID }
                        let canonicalDocId = docIds.contains(preferredCanonicalDocId) ? preferredCanonicalDocId : fallbackCanonicalDocId
                        
                        let group = DispatchGroup()
                        for doc in docs {
                            guard doc.documentID != canonicalDocId else { continue }
                            group.enter()
                            doc.reference.delete { _ in
                                group.leave()
                            }
                        }
                        
                        group.notify(queue: .main) {
                            done()
                        }
                    }
            }
            
            func finishSuccess(infoMessage: String?) {
                // Best-effort: clean up duplicates so future reads are deterministic.
                cleanupDuplicatesForCurrentItem {
                    self.syncItemsArrayField(categoryId: categoryId) {
                        completion(true, infoMessage)
                    }
                }
            }
            
            func finishFailure(_ message: String) {
                completion(false, message)
            }
            
            // Prefer server verification. If offline/unavailable, fall back to local cache and
            // return a clear "saved locally" message.
            updatedDocRef.getDocument(source: .server) { snapshot, error in
                if let error = error {
                    print("⚠️ Server verification failed (likely offline): \(error.localizedDescription)")
                    updatedDocRef.getDocument { localSnapshot, localError in
                        if let localError = localError {
                            // We can't verify even locally; still surface a helpful message.
                            print("⚠️ Local verification also failed: \(localError.localizedDescription)")
                            finishSuccess(infoMessage: "Saved locally. Will sync when you're back online.")
                            return
                        }
                        let localDesc = localSnapshot?.data()?["description"] as? String ?? ""
                        if localSnapshot?.exists == true, localDesc == expectedDescription {
                            finishSuccess(infoMessage: "Saved locally. Will sync when you're back online.")
                        } else {
                            finishFailure("Update could not be verified. Please try again when online.")
                        }
                    }
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    finishFailure("Update succeeded but could not be verified on server.")
                    return
                }
                
                let serverDesc = snapshot.data()?["description"] as? String ?? ""
                if serverDesc != expectedDescription {
                    print("❌ Server verification mismatch. Expected: '\(expectedDescription)' Got: '\(serverDesc)'")
                    finishFailure("Update did not persist. Please try again.")
                    return
                }
                
                finishSuccess(infoMessage: nil)
            }
        }
        
        // Build payload once
        let payload: [String: Any] = [
            "id": newItem.id,
            "description": newItem.description,
            "price": newItem.price,
            "imageURL": newItem.imageURL,
            "isAvailable": newItem.isAvailable,
            "paymentLinkID": newItem.paymentLinkID,
            "isDumpling": newItem.isDumpling,
            "toppingModifiersEnabled": newItem.toppingModifiersEnabled,
            "milkSubModifiersEnabled": newItem.milkSubModifiersEnabled,
            "availableToppingIDs": newItem.availableToppingIDs,
            "availableMilkSubIDs": newItem.availableMilkSubIDs,
            "allergyTagIDs": newItem.allergyTagIDs
        ]
        
        // Resolve the correct existing document to update. Some legacy data may have docIDs
        // that don't match today's sanitization, so we fall back to querying by field `id`.
        func resolveOldDocRef(_ done: @escaping (DocumentReference?) -> Void) {
            let sanitizedRef = itemsCollection.document(oldSanitizedId)
            sanitizedRef.getDocument { snapshot, _ in
                if snapshot?.exists == true {
                    done(sanitizedRef)
                    return
                }
                
                itemsCollection
                    .whereField("id", isEqualTo: oldItem.id)
                    .limit(to: 1)
                    .getDocuments { querySnapshot, queryError in
                        if queryError != nil {
                            done(nil)
                            return
                        }
                        if let doc = querySnapshot?.documents.first {
                            done(doc.reference)
                            return
                        }
                        done(nil)
                    }
            }
        }
        
        resolveOldDocRef { resolvedOldRef in
            guard let resolvedOldRef = resolvedOldRef else {
                completion(false, "Item not found in database. It may have been moved/duplicated; try refreshing the menu.")
                return
            }
            
            // If the item name changed, delete the resolved old doc and create a new one at the new sanitized ID.
            if oldSanitizedId != newSanitizedId || oldItem.id != newItem.id {
                resolvedOldRef.delete { deleteError in
                    if let deleteError = deleteError {
                        completion(false, "Failed to delete old item: \(deleteError.localizedDescription)")
                        return
                    }
                    
                    let newRef = itemsCollection.document(newSanitizedId)
                    newRef.setData(payload) { createError in
                        if let createError = createError {
                            completion(false, "Failed to create new item: \(createError.localizedDescription)")
                        } else {
                            verifyWriteAndFinish(updatedDocRef: newRef)
                        }
                    }
                }
            } else {
                resolvedOldRef.setData(payload) { error in
                    if let error = error {
                        completion(false, error.localizedDescription)
                    } else {
                        verifyWriteAndFinish(updatedDocRef: resolvedOldRef)
                    }
                }
            }
        }
    }

    /// Deletes an item from a specific category in Firestore
    func deleteItemFromCategory(categoryId: String, item: MenuItem, completion: @escaping (Bool, String?) -> Void) {
        let categoryRef = db.collection("menu").document(categoryId)
        let itemsCollection = categoryRef.collection("items")
        
        // Sanitize the document ID to remove invalid characters
        let sanitizedId = item.id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "(", with: "_")
            .replacingOccurrences(of: ")", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        
        // First check if the document exists
        itemsCollection.document(sanitizedId).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(false, "Error checking document: \(error.localizedDescription)")
                return
            }
            
            guard let snapshot = snapshot, snapshot.exists else {
                // Try to find the document with a query instead
                itemsCollection.whereField("id", isEqualTo: item.id).getDocuments { querySnapshot, queryError in
                    if let queryError = queryError {
                        completion(false, "Document not found and query failed: \(queryError.localizedDescription)")
                        return
                    }
                    
                    if let doc = querySnapshot?.documents.first {
                        doc.reference.delete { deleteError in
                            if let deleteError = deleteError {
                                completion(false, deleteError.localizedDescription)
                            } else {
                                self.syncItemsArrayField(categoryId: categoryId) {
                                    completion(true, nil)
                                }
                            }
                        }
                    } else {
                        completion(false, "Item not found in database. It may have already been deleted.")
                    }
                }
                return
            }
            
            // Document exists, proceed with deletion
            itemsCollection.document(sanitizedId).delete { error in
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    self.syncItemsArrayField(categoryId: categoryId) {
                        completion(true, nil)
                    }
                }
            }
        }
    }

    // MARK: - Legacy Dumpling Methods (for backward compatibility)
    
    /// Adds a new dumpling MenuItem to the first menu category in Firestore (for testing only)
    func addDumplingToFirebase(name: String, price: Double, description: String, imageURL: String, completion: @escaping (Bool, String?) -> Void) {
        guard let firstCategory = menuCategories.first else {
            completion(false, "No menu category found.")
            return
        }
        let newItem = MenuItem(
            id: name,
            description: description,
            price: price,
            imageURL: imageURL,
            isAvailable: true,
            paymentLinkID: "",
            isDumpling: true,
            toppingModifiersEnabled: false,
            milkSubModifiersEnabled: false,
            availableToppingIDs: [],
            availableMilkSubIDs: []
        )
        addItemToCategory(categoryId: firstCategory.id, item: newItem, completion: completion)
    }

    /// Updates a dumpling MenuItem in the first menu category in Firestore
    func updateDumplingInFirebase(item: MenuItem, completion: @escaping (Bool, String?) -> Void) {
        guard let firstCategory = menuCategories.first else {
            completion(false, "No menu category found.")
            return
        }
        // For backward compatibility, we'll update the item with the same ID
        updateItemInCategory(categoryId: firstCategory.id, oldItem: item, newItem: item, completion: completion)
    }

    /// Deletes a dumpling MenuItem from the first menu category in Firestore
    func deleteDumplingFromFirebase(item: MenuItem, completion: @escaping (Bool, String?) -> Void) {
        guard let firstCategory = menuCategories.first else {
            completion(false, "No menu category found.")
            return
        }
        deleteItemFromCategory(categoryId: firstCategory.id, item: item, completion: completion)
    }

    /// Test function to validate Firebase Storage URLs (for debugging only)
    func testImageURL(_ urlString: String) {
        // This function is for debugging - logs removed for production
        guard urlString.hasPrefix("gs://") else { return }
        
        let components = urlString.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
        guard components.count >= 2 else { return }
        
        let bucketName = components[0]
        let filePath = components.dropFirst().joined(separator: "/")
        let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
        let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
        
        guard let url = URL(string: downloadURL) else { return }
        
        URLSession.shared.dataTask(with: url) { _, _, _ in
            // Silent test - no logging
        }.resume()
    }

    /// Creates a new category in Firestore if it doesn't exist
    func createCategoryIfNeeded(categoryId: String, completion: @escaping (Bool, String?) -> Void) {
        guard !categoryId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false, "Category ID cannot be empty.")
            return
        }
        
        let categoryRef = db.collection("menu").document(categoryId)
        categoryRef.getDocument { (document, error) in
            if let document = document, document.exists {
                completion(true, nil)
            } else {
                // Create the category with empty items
                let newCategory = MenuCategory(id: categoryId, items: [], subCategories: nil)
                do {
                    try categoryRef.setData(from: newCategory) { error in
                        if let error = error {
                            completion(false, error.localizedDescription)
                        } else {
                            completion(true, nil)
                        }
                    }
                } catch {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    /// Rename a category by creating a new document, copying items, updating order, and deleting the old category
    func renameCategory(oldId: String, newId: String, newIsDrinks: Bool, newLemonadeSodaEnabled: Bool, newHideIcon: Bool, completion: @escaping (Bool, String?) -> Void) {
        let trimmedNewId = newId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewId.isEmpty else {
            completion(false, "Category name cannot be empty.")
            return
        }
        guard trimmedNewId != oldId else {
            completion(false, "New name is the same as the current name.")
            return
        }

        let oldRef = db.collection("menu").document(oldId)
        let newRef = db.collection("menu").document(trimmedNewId)

        // Ensure new category doesn't already exist
        newRef.getDocument { [weak self] newDoc, err in
            guard let self = self else { return }
            if let err = err {
                completion(false, err.localizedDescription)
                return
            }
            if let newDoc = newDoc, newDoc.exists {
                completion(false, "A category with that name already exists.")
                return
            }

            // Read old category data
            oldRef.getDocument { oldDoc, oldErr in
                if let oldErr = oldErr {
                    completion(false, oldErr.localizedDescription)
                    return
                }

                let oldData = oldDoc?.data() ?? [:]

                // Create new category doc with old data (without changing structure)
                newRef.setData(oldData) { setErr in
                    if let setErr = setErr {
                        completion(false, setErr.localizedDescription)
                        return
                    }
                    // Ensure new labels are applied
                    newRef.setData(
                        ["isDrinks": newIsDrinks, "lemonadeSodaEnabled": newLemonadeSodaEnabled, "hideIcon": newHideIcon],
                        merge: true
                    )

                    // Copy items subcollection
                    let oldItemsRef = oldRef.collection("items")
                    let newItemsRef = newRef.collection("items")
                    oldItemsRef.getDocuments { snapshot, snapErr in
                        if let snapErr = snapErr {
                            completion(false, snapErr.localizedDescription)
                            return
                        }

                        let group = DispatchGroup()
                        let docs = snapshot?.documents ?? []
                        for doc in docs {
                            group.enter()
                            newItemsRef.document(doc.documentID).setData(doc.data()) { copyErr in
                                if let copyErr = copyErr {
                                    print("❌ Failed to copy item \(doc.documentID): \(copyErr.localizedDescription)")
                                }
                                group.leave()
                            }
                        }

                        group.notify(queue: .main) {
                            // Update menu order document to reflect new category ID
                            self.orderDocRef.getDocument { orderDoc, orderErr in
                                if let orderErr = orderErr {
                                    completion(false, orderErr.localizedDescription)
                                    return
                                }
                                var orderedCats = (orderDoc?.data()?["orderedCategoryIds"] as? [String]) ?? self.orderedCategoryIds
                                var itemsByCat = (orderDoc?.data()?["orderedItemIdsByCategory"] as? [String: [String]]) ?? self.orderedItemIdsByCategory

                                if let idx = orderedCats.firstIndex(of: oldId) {
                                    orderedCats[idx] = trimmedNewId
                                }
                                let oldItemOrder = itemsByCat[oldId]
                                itemsByCat.removeValue(forKey: oldId)
                                if let oldItemOrder = oldItemOrder {
                                    itemsByCat[trimmedNewId] = oldItemOrder
                                }

                                let orderData: [String: Any] = [
                                    "orderedCategoryIds": orderedCats,
                                    "orderedItemIdsByCategory": itemsByCat,
                                    // Also write legacy keys used elsewhere to be safe
                                    "categories": orderedCats,
                                    "itemsByCategory": itemsByCat,
                                    "lastUpdated": FieldValue.serverTimestamp()
                                ]

                                self.orderDocRef.setData(orderData) { orderSetErr in
                                    if let orderSetErr = orderSetErr {
                                        completion(false, orderSetErr.localizedDescription)
                                        return
                                    }

                                    // Delete old items and old category
                                    let deleteGroup = DispatchGroup()
                                    for doc in docs {
                                        deleteGroup.enter()
                                        oldItemsRef.document(doc.documentID).delete { _ in deleteGroup.leave() }
                                    }
                                    deleteGroup.notify(queue: .main) {
                                        oldRef.delete { delErr in
                                            if let delErr = delErr {
                                                print("⚠️ Failed to delete old category doc: \(delErr.localizedDescription)")
                                            }

                                            // Sync items array on new category and refresh
                                            // Apply label to local state and sync
                                            self.syncItemsArrayField(categoryId: trimmedNewId) {
                                                // Update local state optimistically
                                                DispatchQueue.main.async {
                                                    if let i = self.orderedCategoryIds.firstIndex(of: oldId) {
                                                        self.orderedCategoryIds[i] = trimmedNewId
                                                    }
                                                    let oldOrder = self.orderedItemIdsByCategory.removeValue(forKey: oldId)
                                                    if let oldOrder = oldOrder {
                                                        self.orderedItemIdsByCategory[trimmedNewId] = oldOrder
                                                    }
                                                    if let idx = self.menuCategories.firstIndex(where: { $0.id == trimmedNewId }) {
                                                        self.menuCategories[idx].isDrinks = newIsDrinks
                                                        self.menuCategories[idx].lemonadeSodaEnabled = newLemonadeSodaEnabled
                                                    }
                                                    // Trigger a refresh to pick up the new category structure
                                                    self.fetchMenu()
                                                }
                                                completion(true, nil)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Update isDrinks label for an existing category
    func updateCategoryIsDrinks(categoryId: String, isDrinks: Bool, completion: @escaping (Bool, String?) -> Void) {
        let ref = db.collection("menu").document(categoryId)
        ref.setData(["isDrinks": isDrinks], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    if let idx = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                        self.menuCategories[idx].isDrinks = isDrinks
                    }
                    completion(true, nil)
                }
            }
        }
    }

    /// Update isDrinks / lemonadeSodaEnabled / isToppingCategory flags for a category
    func updateCategoryFlags(categoryId: String, isDrinks: Bool, lemonadeSodaEnabled: Bool, isToppingCategory: Bool, completion: @escaping (Bool, String?) -> Void) {
        let ref = db.collection("menu").document(categoryId)
        ref.setData(["isDrinks": isDrinks, "lemonadeSodaEnabled": lemonadeSodaEnabled, "isToppingCategory": isToppingCategory], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    if let idx = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                        self.menuCategories[idx].isDrinks = isDrinks
                        self.menuCategories[idx].lemonadeSodaEnabled = lemonadeSodaEnabled
                        self.menuCategories[idx].isToppingCategory = isToppingCategory
                    }
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Update category icon string (emoji or URL)
    func updateCategoryIcon(categoryId: String, icon: String, completion: @escaping (Bool, String?) -> Void) {
        let ref = db.collection("menu").document(categoryId)
        ref.setData(["icon": icon], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    if let idx = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                        self.menuCategories[idx].icon = icon
                    }
                    completion(true, nil)
                }
            }
        }
    }

    /// Update whether a category should hide its icon (text-only category row)
    func updateCategoryHideIcon(categoryId: String, hideIcon: Bool, completion: @escaping (Bool, String?) -> Void) {
        let ref = db.collection("menu").document(categoryId)
        ref.setData(["hideIcon": hideIcon], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    if let idx = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                        self.menuCategories[idx].hideIcon = hideIcon
                    }
                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - Menu Order Management
    
    func updateMenuOrder(categories: [String], itemsByCategory: [String: [String]], completion: @escaping (Bool) -> Void) {
        print("🔄 Updating menu order...")
        print("Categories: \(categories)")
        print("Items by category: \(itemsByCategory)")
        
        let orderData: [String: Any] = [
            "orderedCategoryIds": categories,
            "orderedItemIdsByCategory": itemsByCategory,
            // Legacy keys still referenced by some older codepaths / migrations
            "categories": categories,
            "itemsByCategory": itemsByCategory,
            "lastUpdated": FieldValue.serverTimestamp()
        ]
        
        orderDocRef.setData(orderData) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error updating menu order: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Menu order updated successfully")
                    // Update local state
                    self?.orderedCategoryIds = categories
                    self?.orderedItemIdsByCategory = itemsByCategory
                    completion(true)
                }
            }
        }
    }
    
    func listenToMenuOrder() {
        print("🔍 Setting up menu order listener...")
        
        // Remove any existing listener first
        orderListener?.remove()
        
        orderListener = orderDocRef.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error listening to menu order: \(error.localizedDescription)")
                // IMPORTANT: Remove the listener on permission errors to prevent Firestore queue re-entrancy crashes
                // This typically happens when a non-admin user tries to listen to admin-only collections
                DispatchQueue.main.async {
                    self.orderListener?.remove()
                    self.orderListener = nil
                    print("⚠️ Menu order listener removed due to error. Non-admin users will use default ordering.")
                }
                return
            }
            
            guard let document = documentSnapshot, document.exists else {
                if self.isAdminUser {
                    print("📄 No menu order document found, creating default (admin)...")
                    // Dispatch to main queue to avoid Firestore queue re-entrancy issues
                    DispatchQueue.main.async {
                        self.createDefaultMenuOrder()
                    }
                } else {
                    print("📄 No menu order document found (non-admin). Using default ordering.")
                }
                return
            }
            
            let data = document.data() ?? [:]
            
            // Read canonical keys first, but fall back to legacy keys to avoid "order disappears" bugs
            // if older writers stored only the legacy schema.
            let orderedCategoryIds =
                (data["orderedCategoryIds"] as? [String])
                ?? (data["categories"] as? [String])
                ?? []
            
            let orderedItemIdsByCategory =
                (data["orderedItemIdsByCategory"] as? [String: [String]])
                ?? (data["itemsByCategory"] as? [String: [String]])
                ?? [:]
            
            print("📋 Received menu order update:")
            print("  Categories: \(orderedCategoryIds)")
            print("  Items by category: \(orderedItemIdsByCategory)")
            
            DispatchQueue.main.async {
                self.orderedCategoryIds = orderedCategoryIds
                self.orderedItemIdsByCategory = orderedItemIdsByCategory
            }
        }
    }
    
    private func createDefaultMenuOrder() {
        print("🆕 Creating default menu order...")
        
        // Get all category IDs from current menu
        let categoryIds = menuCategories.map { $0.id }
        
        // Create default item order for each category
        var defaultItemOrder: [String: [String]] = [:]
        for category in menuCategories {
            let itemIds = category.items?.map { $0.id } ?? []
            defaultItemOrder[category.id] = itemIds
        }
        
        // Save default order
        updateMenuOrder(categories: categoryIds, itemsByCategory: defaultItemOrder) { success in
            if success {
                print("✅ Default menu order created successfully")
            } else {
                print("❌ Failed to create default menu order")
            }
        }
    }
    
    // MARK: - Config/Pricing

    /// Fetch config pricing (one-time fetch, replaces real-time listener)
    func fetchConfig() {
        // Only fetch if cache is stale
        guard dataCacheManager.isConfigPricingStale() else {
            print("✅ Config loaded from cache")
            return
        }
        
        configListener?.remove()
        configListener = nil
        
        configDocRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let data = snapshot?.data() {
                let price = data["halfAndHalfPrice"] as? Double ?? 13.99
                self.halfAndHalfPrice = price
                self.dataCacheManager.cacheConfigPricing(halfAndHalfPrice: price)
                print("✅ Fetched and cached config pricing")
            }
        }
    }
    
    /// Start real-time listener for config (only for admin editing)
    func startConfigListenerForAdmin() {
        configListener?.remove()
        configListener = configDocRef.addSnapshotListener { [weak self] snapshot, error in
            if let data = snapshot?.data() {
                self?.halfAndHalfPrice = data["halfAndHalfPrice"] as? Double ?? 13.99
            }
        }
    }
    
    // Update half and half price
    func updateHalfAndHalfPrice(_ newPrice: Double, completion: ((Error?) -> Void)? = nil) {
        configDocRef.setData(["halfAndHalfPrice": newPrice]) { error in
            if let error = error {
                print("❌ Failed to update half and half price: \(error.localizedDescription)")
            } else {
                self.halfAndHalfPrice = newPrice
                print("✅ Updated half and half price to: $\(newPrice)")
            }
            completion?(error)
        }
    }

    // Add a single item to the menu order for a specific category
    func addItemToMenuOrder(categoryId: String, itemId: String, completion: (() -> Void)? = nil) {
        print("🔍 addItemToMenuOrder called for category: '\(categoryId)', item: '\(itemId)'")
        
        // First, ensure the category is in the ordered categories
        if !orderedCategoryIds.contains(categoryId) {
            print("🔍 Adding category '\(categoryId)' to ordered categories")
            orderedCategoryIds.append(categoryId)
        }
        
        // Then, ensure the item is in the ordered items for that category
        if orderedItemIdsByCategory[categoryId] == nil {
            orderedItemIdsByCategory[categoryId] = []
        }
        
        if !orderedItemIdsByCategory[categoryId]!.contains(itemId) {
            print("🔍 Adding item '\(itemId)' to ordered items for category '\(categoryId)'")
            orderedItemIdsByCategory[categoryId]!.append(itemId)
        }
        
        // Update the menu order in Firestore
        updateMenuOrder(categories: orderedCategoryIds, itemsByCategory: orderedItemIdsByCategory) { success in
            if success {
                print("✅ Successfully added item '\(itemId)' to menu order for category '\(categoryId)'")
            } else {
                print("❌ Failed to add item to menu order (unknown error)")
            }
            completion?()
        }
    }

    // Use the order arrays to sort categories and items for display
    var orderedCategories: [MenuCategory] {
        if orderedCategoryIds.isEmpty { return menuCategories }
        return orderedCategoryIds.compactMap { id in menuCategories.first(where: { $0.id == id }) }
    }
    func orderedItems(for category: MenuCategory) -> [MenuItem] {
        guard let items = category.items else { return [] }
        
        // If no order is defined, return all items
        guard let itemOrder = orderedItemIdsByCategory[category.id], !itemOrder.isEmpty else {
            return items
        }
        
        // If order is defined, return ordered items first, then any remaining items
        var orderedItems: [MenuItem] = []
        var remainingItems: [MenuItem] = []
        
        // Add items in the specified order
        for itemId in itemOrder {
            if let item = items.first(where: { $0.id == itemId }) {
                orderedItems.append(item)
            }
        }
        
        // Add any items that aren't in the order
        for item in items {
            if !itemOrder.contains(item.id) {
                remainingItems.append(item)
            }
        }
        
        // Return ordered items first, then remaining items
        return orderedItems + remainingItems
    }

    /// Preload all menu item images (including subcategories) to cache them for smooth display
    func preloadMenuImages() {
        var urls: [URL] = []
        for category in menuCategories {
            if let items = category.items {
                for item in items {
                    if let url = URL(string: item.imageURL) {
                        urls.append(url)
                    }
                }
            }
            if let subCategories = category.subCategories {
                for subCategory in subCategories {
                    for item in subCategory.items {
                        if let url = URL(string: item.imageURL) {
                            urls.append(url)
                        }
                    }
                }
            }
        }
        ImagePrefetcher(urls: urls).start()
    }

    /// Duplicates an item in a specific category in Firestore
    func duplicateItemInCategory(categoryId: String, item: MenuItem, completion: @escaping (Bool, String?) -> Void) {
        // Create a new item with a new id (e.g., append ' Copy' and ensure uniqueness)
        var newId = item.id + " Copy"
        let category = menuCategories.first(where: { $0.id == categoryId })
        var existingIds: [String] = []
        if let items = category?.items {
            existingIds = items.map { $0.id }
        }
        var copyIndex = 2
        while existingIds.contains(newId) {
            newId = item.id + " Copy " + String(copyIndex)
            copyIndex += 1
        }
        let duplicatedItem = MenuItem(
            id: newId,
            description: item.description,
            price: item.price,
            imageURL: item.imageURL,
            isAvailable: item.isAvailable,
            paymentLinkID: item.paymentLinkID,
            isDumpling: item.isDumpling,
            toppingModifiersEnabled: item.toppingModifiersEnabled,
            milkSubModifiersEnabled: item.milkSubModifiersEnabled,
            availableToppingIDs: item.availableToppingIDs,
            availableMilkSubIDs: item.availableMilkSubIDs
        )
        addItemToCategory(categoryId: categoryId, item: duplicatedItem, completion: completion)
    }

    /// Batch update: Mark all items with 'dumpling' in their id as isDumpling = true in Firestore
    func markDumplingItemsInFirestore(completion: ((Int, Int) -> Void)? = nil) {
        db.collection("menu").getDocuments { (snapshot, error) in
            guard let documents = snapshot?.documents, error == nil else {
                print("❌ Error fetching menu documents: \(error?.localizedDescription ?? "Unknown error")")
                completion?(0, 0)
                return
            }
            var updated = 0
            var total = 0
            let group = DispatchGroup()
            for doc in documents {
                total += 1
                let data = doc.data()
                if let id = data["id"] as? String, id.lowercased().contains("dumpling") {
                    group.enter()
                    doc.reference.updateData(["isDumpling": true]) { err in
                        if let err = err {
                            print("❌ Failed to update \(id): \(err.localizedDescription)")
                        } else {
                            print("✅ Marked \(id) as dumpling")
                            updated += 1
                        }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                print("✅ Done marking dumpling items. Updated \(updated) out of \(total) items.")
                completion?(updated, total)
            }
        }
    }

    /// Scan all menu items in Firestore and print any documents missing required fields
    func checkMenuItemsForMissingFields() {
        db.collection("menu").getDocuments { (snapshot, error) in
            guard let documents = snapshot?.documents, error == nil else {
                print("❌ Error fetching menu documents: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            let requiredFields: [String] = ["id", "description", "price", "imageURL", "isAvailable", "paymentLinkID"]
            var missingCount = 0
            for doc in documents {
                let data = doc.data()
                var missing: [String] = []
                for field in requiredFields {
                    if data[field] == nil {
                        missing.append(field)
                    }
                }
                if !missing.isEmpty {
                    print("❌ Document \(doc.documentID) is missing fields: \(missing.joined(separator: ", "))")
                    missingCount += 1
                }
            }
            if missingCount == 0 {
                print("✅ All menu items have the required fields.")
            } else {
                print("❌ Found \(missingCount) menu items with missing fields.")
            }
        }
    }

    /// Migrate menu items from 'items' array in each category document to an 'items' subcollection
    func migrateMenuItemsToSubcollections(completion: (() -> Void)? = nil) {
        db.collection("menu").getDocuments { (snapshot, error) in
            guard let documents = snapshot?.documents, error == nil else {
                print("❌ Error fetching menu documents: \(error?.localizedDescription ?? "Unknown error")")
                completion?()
                return
            }
            let group = DispatchGroup()
            var migratedCategories = 0
            for doc in documents {
                let data = doc.data()
                if let items = data["items"] as? [[String: Any]], !items.isEmpty {
                    let categoryId = doc.documentID
                    let itemsCollection = doc.reference.collection("items")
                    print("Migrating \(items.count) items for category: \(categoryId)")
                    for itemData in items {
                        if let id = itemData["id"] as? String {
                            // Sanitize the document ID to remove invalid characters
                            let sanitizedId = id.replacingOccurrences(of: "/", with: "_")
                                .replacingOccurrences(of: "\\", with: "_")
                                .replacingOccurrences(of: ".", with: "_")
                                .replacingOccurrences(of: "(", with: "_")
                                .replacingOccurrences(of: ")", with: "_")
                                .replacingOccurrences(of: " ", with: "_")
                            
                            group.enter()
                            itemsCollection.document(sanitizedId).setData(itemData) { err in
                                if let err = err {
                                    print("❌ Failed to migrate item \(id) (sanitized: \(sanitizedId)) in category \(categoryId): \(err.localizedDescription)")
                                } else {
                                    print("✅ Migrated item \(id) (sanitized: \(sanitizedId)) in category \(categoryId)")
                                }
                                group.leave()
                            }
                        }
                    }
                    // Remove the 'items' array field from the category document
                    group.enter()
                    doc.reference.updateData(["items": FieldValue.delete()]) { err in
                        if let err = err {
                            print("❌ Failed to remove 'items' field from category \(categoryId): \(err.localizedDescription)")
                        } else {
                            print("✅ Removed 'items' field from category \(categoryId)")
                        }
                        group.leave()
                    }
                    migratedCategories += 1
                }
            }
            group.notify(queue: .main) {
                print("✅ Migration complete. Migrated \(migratedCategories) categories.")
                completion?()
            }
        }
    }

    /// Create a backup of the entire menu from Firestore
    func createMenuBackup(completion: ((Bool, String) -> Void)? = nil) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupCollectionName = "menu_backup_\(dateFormatter.string(from: Date()))"
        print("Creating backup: \(backupCollectionName)")
        
        db.collection("menu").getDocuments { (snapshot, error) in
            guard let documents = snapshot?.documents, error == nil else {
                print("❌ Error fetching menu documents: \(error?.localizedDescription ?? "Unknown error")")
                completion?(false, "Failed to fetch menu documents")
                return
            }
            let group = DispatchGroup()
            var backupCount = 0
            var errorCount = 0
            for doc in documents {
                let categoryId = doc.documentID
                let data = doc.data()
                let backupDocRef = self.db.collection(backupCollectionName).document(categoryId)
                
                // Backup the category document
                group.enter()
                backupDocRef.setData(data) { err in
                    if let err = err {
                        print("❌ Failed to backup category \(categoryId): \(err.localizedDescription)")
                        errorCount += 1
                    } else {
                        print("✅ Backed up category: \(categoryId)")
                        backupCount += 1
                    }
                    group.leave()
                }
                
                // Backup items subcollection if it exists
                let itemsCollection = doc.reference.collection("items")
                itemsCollection.getDocuments { (itemsSnapshot, itemsError) in
                    if let itemsDocs = itemsSnapshot?.documents, !itemsDocs.isEmpty {
                        print("Backing up \(itemsDocs.count) items for category: \(categoryId)")
                        for itemDoc in itemsDocs {
                            group.enter()
                            let itemData = itemDoc.data()
                            // Sanitize the document ID to remove invalid characters
                            let sanitizedId = itemDoc.documentID.replacingOccurrences(of: "/", with: "_")
                                .replacingOccurrences(of: "\\", with: "_")
                                .replacingOccurrences(of: ".", with: "_")
                                .replacingOccurrences(of: "(", with: "_")
                                .replacingOccurrences(of: ")", with: "_")
                                .replacingOccurrences(of: " ", with: "_")
                            let backupItemRef = backupDocRef.collection("items").document(sanitizedId)
                            backupItemRef.setData(itemData) { err in
                                if let err = err {
                                    print("❌ Failed to backup item \(itemDoc.documentID) (sanitized: \(sanitizedId)) in category \(categoryId): \(err.localizedDescription)")
                                    errorCount += 1
                                } else {
                                    print("✅ Backed up item: \(itemDoc.documentID) (sanitized: \(sanitizedId)) in category \(categoryId)")
                                    backupCount += 1
                                }
                                group.leave()
                            }
                        }
                    }
                }
            }
            group.notify(queue: .main) {
                let message = "Backup complete: \(backupCollectionName). Backed up \(backupCount) documents with \(errorCount) errors."
                print("✅ \(message)")
                completion?(errorCount == 0, message)
            }
        }
    }

    /// Manually refresh the menu data
    func refreshMenu() {
        print("🔄 refreshMenu() called - forcing fresh data fetch")
        forceRefreshMenu()
    }
    
    /// Force refresh a specific category's items
    func refreshCategoryItems(categoryId: String) {
        print("🔄 refreshCategoryItems called for category: \(categoryId)")
        // Mark this category as loading
        DispatchQueue.main.async {
            self.loadingCategories.insert(categoryId)
        }
        
        // Remove existing listener for this category
        if let existingListener = itemListeners[categoryId] {
            existingListener.remove()
            itemListeners.removeValue(forKey: categoryId)
        }
        
        // Set up new listener for this category
        let categoryRef = db.collection("menu").document(categoryId)
        let itemListener = categoryRef.collection("items").addSnapshotListener { [weak self] (itemsSnapshot, itemsError) in
            guard let self = self else { return }
            var items: [MenuItem] = []
            if let itemsSnapshot = itemsSnapshot {
                print("🔄 Items snapshot received for category '\(categoryId)': \(itemsSnapshot.documents.count) items")
                items = self.dedupeMenuItemsFromSnapshot(categoryId: categoryId, documents: itemsSnapshot.documents)
                print("🔄 Fetched items for category \(categoryId): \(items.map { $0.id })")
            }
            DispatchQueue.main.async {
                if let catIndex = self.menuCategories.firstIndex(where: { $0.id == categoryId }) {
                    self.menuCategories[catIndex].items = items
                    print("🔄 Updated category '\(categoryId)' with \(items.count) items")
                } else {
                    print("❌ Category '\(categoryId)' not found in menuCategories")
                }
                // Category finished loading (regardless of item count)
                self.loadingCategories.remove(categoryId)
            }
        }
        itemListeners[categoryId] = itemListener
    }

    /// Restore menu data from a backup collection
    func restoreFromBackup(backupCollectionName: String, completion: ((Bool, String) -> Void)? = nil) {
        print("🔄 Restoring from backup: \(backupCollectionName)")
        
        db.collection(backupCollectionName).getDocuments { (snapshot, error) in
            guard let documents = snapshot?.documents, error == nil else {
                print("❌ Error fetching backup documents: \(error?.localizedDescription ?? "Unknown error")")
                completion?(false, "Failed to fetch backup documents")
                return
            }
            let group = DispatchGroup()
            var restoredCount = 0
            var errorCount = 0
            
            for doc in documents {
                let categoryId = doc.documentID
                let data = doc.data()
                let categoryRef = self.db.collection("menu").document(categoryId)
                
                // Restore the category document
                group.enter()
                categoryRef.setData(data) { err in
                    if let err = err {
                        print("❌ Failed to restore category \(categoryId): \(err.localizedDescription)")
                        errorCount += 1
                    } else {
                        print("✅ Restored category: \(categoryId)")
                        restoredCount += 1
                    }
                    group.leave()
                }
                
                // Restore items subcollection if it exists
                let backupItemsCollection = doc.reference.collection("items")
                backupItemsCollection.getDocuments { (itemsSnapshot, itemsError) in
                    if let itemsDocs = itemsSnapshot?.documents, !itemsDocs.isEmpty {
                        print("Restoring \(itemsDocs.count) items for category: \(categoryId)")
                        let itemsCollection = categoryRef.collection("items")
                        
                        for itemDoc in itemsDocs {
                            group.enter()
                            let itemData = itemDoc.data()
                            itemsCollection.document(itemDoc.documentID).setData(itemData) { err in
                                if let err = err {
                                    print("❌ Failed to restore item \(itemDoc.documentID) in category \(categoryId): \(err.localizedDescription)")
                                    errorCount += 1
                                } else {
                                    print("✅ Restored item: \(itemDoc.documentID) in category \(categoryId)")
                                    restoredCount += 1
                                }
                                group.leave()
                            }
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                let message = "Restore complete from \(backupCollectionName). Restored \(restoredCount) documents with \(errorCount) errors."
                print("✅ \(message)")
                completion?(errorCount == 0, message)
            }
        }
    }

    func syncAllCategoriesItemsArray(completion: (() -> Void)? = nil) {
        db.collection("menu").getDocuments { [weak self] (snapshot, error) in
            guard let self = self, let documents = snapshot?.documents else {
                completion?()
                return
            }
            let group = DispatchGroup()
            for document in documents {
                let categoryId = document.documentID
                group.enter()
                self.syncItemsArrayField(categoryId: categoryId) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                completion?()
            }
        }
    }

    // MARK: - Allergy Tags (Reusable)
    
    func fetchAllergyTags() {
        // OPTIMIZED: Use one-time fetch with caching (7-day cache for static data)
        allergyTagsListener?.remove()
        allergyTagsListener = nil
        
        db.collection("allergyTags").getDocuments { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("❌ Error fetching allergy tags: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.allergyTags = []
                return
            }
            let tags = documents.compactMap { doc in
                try? doc.data(as: AllergyTag.self)
            }.sorted { $0.order < $1.order }
            
            self.allergyTags = tags
            self.dataCacheManager.cacheAllergyTags(tags)
            print("✅ Fetched and cached \(tags.count) allergy tags")
        }
    }
    
    /// Start real-time listener for allergy tags (only for admin editing)
    func startAllergyTagsListenerForAdmin() {
        allergyTagsListener?.remove()
        allergyTagsListener = db.collection("allergyTags").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("Error fetching allergy tags: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.allergyTags = []
                return
            }
            self.allergyTags = documents.compactMap { doc in
                try? doc.data(as: AllergyTag.self)
            }.sorted { $0.order < $1.order }
        }
    }
    
    func addAllergyTag(_ tag: AllergyTag, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("allergyTags").document(tag.id)
            var tagWithOrder = tag
            tagWithOrder.order = self.allergyTags.count
            
            do {
                try ref.setData(from: tagWithOrder) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "add an allergy tag"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func updateAllergyTag(_ tag: AllergyTag, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("allergyTags").document(tag.id)
            do {
                try ref.setData(from: tag) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "update an allergy tag"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func deleteAllergyTag(_ tag: AllergyTag, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("allergyTags").document(tag.id)
            ref.delete { error in
                if let error = error {
                    if self.isPermissionDeniedError(error) {
                        completion?(false, self.friendlyPermissionDeniedMessage(action: "delete an allergy tag"))
                    } else {
                        completion?(false, error.localizedDescription)
                    }
                } else {
                    completion?(true, nil)
                }
            }
        }
    }

    // MARK: - Global DrinkOption Firestore Logic

    func fetchDrinkOptions() {
        // OPTIMIZED: Use one-time fetch with caching (7-day cache for static data)
        drinkOptionsListener?.remove()
        drinkOptionsListener = nil
        
        db.collection("drinkOptions").getDocuments { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("❌ Error fetching drink options: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.drinkOptions = []
                return
            }
            let options = documents.compactMap { doc in
                try? doc.data(as: DrinkOption.self)
            }.sorted { $0.order < $1.order }
            
            self.drinkOptions = options
            self.dataCacheManager.cacheDrinkOptions(options)
            print("✅ Fetched and cached \(options.count) drink options")
        }
    }
    
    /// Start real-time listener for drink options (only for admin editing)
    func startDrinkOptionsListenerForAdmin() {
        drinkOptionsListener?.remove()
        drinkOptionsListener = db.collection("drinkOptions").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("Error fetching drink options: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.drinkOptions = []
                return
            }
            self.drinkOptions = documents.compactMap { doc in
                try? doc.data(as: DrinkOption.self)
            }.sorted { $0.order < $1.order }
        }
    }

    func addDrinkOption(_ option: DrinkOption, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkOptions").document(option.id)
            
            // Set order to be at the end of the list
            var optionWithOrder = option
            optionWithOrder.order = self.drinkOptions.count
            
            do {
                try ref.setData(from: optionWithOrder) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "add a drink option"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }

    func updateDrinkOption(_ option: DrinkOption, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkOptions").document(option.id)
            do {
                try ref.setData(from: option) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "update a drink option"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }

    func deleteDrinkOption(_ option: DrinkOption, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkOptions").document(option.id)
            ref.delete { error in
                if let error = error {
                    if self.isPermissionDeniedError(error) {
                        completion?(false, self.friendlyPermissionDeniedMessage(action: "delete a drink option"))
                    } else {
                        completion?(false, error.localizedDescription)
                    }
                } else {
                    completion?(true, nil)
                }
            }
        }
    }
    
    // MARK: - Drink Flavor Management
    
    @Published var drinkFlavors: [DrinkFlavor] = [] // All drink flavors for lemonades and sodas
    private var drinkFlavorsListener: ListenerRegistration?
    @Published var drinkToppings: [DrinkTopping] = [] // All drink-specific toppings for lemonades and sodas
    private var drinkToppingsListener: ListenerRegistration?
    
    func fetchDrinkFlavors() {
        // OPTIMIZED: Use one-time fetch with caching (7-day cache for static data)
        drinkFlavorsListener?.remove()
        drinkFlavorsListener = nil
        
        db.collection("drinkFlavors").getDocuments { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("❌ Error fetching drink flavors: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.drinkFlavors = []
                return
            }
            let flavors = documents.compactMap { doc in
                try? doc.data(as: DrinkFlavor.self)
            }.sorted { $0.order < $1.order }
            
            self.drinkFlavors = flavors
            self.dataCacheManager.cacheDrinkFlavors(flavors)
            print("✅ Fetched and cached \(flavors.count) drink flavors")
        }
    }
    
    /// Start real-time listener for drink flavors (only for admin editing)
    func startDrinkFlavorsListenerForAdmin() {
        drinkFlavorsListener?.remove()
        drinkFlavorsListener = db.collection("drinkFlavors").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("Error fetching drink flavors: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.drinkFlavors = []
                return
            }
            self.drinkFlavors = documents.compactMap { doc in
                try? doc.data(as: DrinkFlavor.self)
            }.sorted { $0.order < $1.order }
        }
    }
    
    func addDrinkFlavor(_ flavor: DrinkFlavor, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkFlavors").document(flavor.id)
            
            // Set order to be at the end of the list
            var flavorWithOrder = flavor
            flavorWithOrder.order = self.drinkFlavors.count
            
            do {
                try ref.setData(from: flavorWithOrder) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "add a drink flavor"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func updateDrinkFlavor(_ flavor: DrinkFlavor, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkFlavors").document(flavor.id)
            do {
                try ref.setData(from: flavor) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "update a drink flavor"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func deleteDrinkFlavor(_ flavor: DrinkFlavor, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkFlavors").document(flavor.id)
            ref.delete { error in
                if let error = error {
                    if self.isPermissionDeniedError(error) {
                        completion?(false, self.friendlyPermissionDeniedMessage(action: "delete a drink flavor"))
                    } else {
                        completion?(false, error.localizedDescription)
                    }
                } else {
                    completion?(true, nil)
                }
            }
        }
    }
    
    func createDefaultDrinkFlavors() {
        let defaultLemonades = [
            ("Classic Lemonade", "🍋"),
            ("Strawberry Lemonade", "🍓"),
            ("Mango Lemonade", "🥭"),
            ("Raspberry Lemonade", "🫐"),
            ("Blueberry Lemonade", "🫐")
        ]
        
        let defaultSodas = [
            ("Cola", "🥤"),
            ("Sprite", "🥤"),
            ("Root Beer", "🥤"),
            ("Orange Soda", "🍊"),
            ("Grape Soda", "🍇")
        ]
        
        // Add lemonades
        for (index, (name, icon)) in defaultLemonades.enumerated() {
            let flavor = DrinkFlavor(
                id: "lemonade_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                name: name,
                isLemonade: true,
                isAvailable: true,
                order: index,
                icon: icon
            )
            addDrinkFlavor(flavor)
        }
        
        // Add sodas
        for (index, (name, icon)) in defaultSodas.enumerated() {
            let flavor = DrinkFlavor(
                id: "soda_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                name: name,
                isLemonade: false,
                isAvailable: true,
                order: index + defaultLemonades.count,
                icon: icon
            )
            addDrinkFlavor(flavor)
        }
    }
    
    // MARK: - Drink Toppings Management
    
    func fetchDrinkToppings() {
        // OPTIMIZED: Use one-time fetch with caching (7-day cache for static data)
        drinkToppingsListener?.remove()
        drinkToppingsListener = nil
        
        db.collection("drinkToppings").getDocuments { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("❌ Error fetching drink toppings: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.drinkToppings = []
                return
            }
            let toppings = documents.compactMap { doc in
                try? doc.data(as: DrinkTopping.self)
            }.sorted { $0.order < $1.order }
            
            self.drinkToppings = toppings
            self.dataCacheManager.cacheDrinkToppings(toppings)
            print("✅ Fetched and cached \(toppings.count) drink toppings")
        }
    }
    
    /// Start real-time listener for drink toppings (only for admin editing)
    func startDrinkToppingsListenerForAdmin() {
        drinkToppingsListener?.remove()
        drinkToppingsListener = db.collection("drinkToppings").addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self else { return }
            if let error = error {
                print("Error fetching drink toppings: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else {
                self.drinkToppings = []
                return
            }
            self.drinkToppings = documents.compactMap { doc in
                try? doc.data(as: DrinkTopping.self)
            }.sorted { $0.order < $1.order }
        }
    }
    
    func addDrinkTopping(_ topping: DrinkTopping, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkToppings").document(topping.id)
            
            // Set order to be at the end of the list
            var toppingWithOrder = topping
            toppingWithOrder.order = self.drinkToppings.count
            
            do {
                try ref.setData(from: toppingWithOrder) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "add a drink topping"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func updateDrinkTopping(_ topping: DrinkTopping, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkToppings").document(topping.id)
            do {
                try ref.setData(from: topping) { error in
                    if let error = error {
                        if self.isPermissionDeniedError(error) {
                            completion?(false, self.friendlyPermissionDeniedMessage(action: "update a drink topping"))
                        } else {
                            completion?(false, error.localizedDescription)
                        }
                    } else {
                        completion?(true, nil)
                    }
                }
            } catch {
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func deleteDrinkTopping(_ topping: DrinkTopping, completion: ((Bool, String?) -> Void)? = nil) {
        requireAdmin { [weak self] ok, err in
            guard let self = self else { return }
            guard ok else { completion?(false, err); return }
            
            let ref = self.db.collection("drinkToppings").document(topping.id)
            ref.delete { error in
                if let error = error {
                    if self.isPermissionDeniedError(error) {
                        completion?(false, self.friendlyPermissionDeniedMessage(action: "delete a drink topping"))
                    } else {
                        completion?(false, error.localizedDescription)
                    }
                } else {
                    completion?(true, nil)
                }
            }
        }
    }
    
    func createDefaultDrinkToppings() {
        // Get existing global drink options (toppings only)
        let globalToppings = drinkOptions.filter { !$0.isMilkSub }
        
        if globalToppings.isEmpty {
            print("No global drink toppings found. Please create global drink options first.")
            return
        }
        
        // Create drink toppings that correspond to existing global toppings
        for (index, globalTopping) in globalToppings.enumerated() {
            let drinkTopping = DrinkTopping(
                id: globalTopping.id, // Use the same ID as the global topping
                name: globalTopping.name,
                price: globalTopping.price,
                isAvailable: true,
                order: index
            )
            addDrinkTopping(drinkTopping)
        }
        
        print("Created \(globalToppings.count) drink toppings for Lemonades and Sodas")
    }
    
    // MARK: - Image Debugging
    
    /// Debug function to test all image URLs in the current menu
    func debugAllImageURLs() {
        print("🔍 Debugging all image URLs in menu...")
        var totalItems = 0
        var validURLs = 0
        var invalidURLs = 0
        
        for category in menuCategories {
            for item in category.items ?? [] {
                totalItems += 1
                print("\n--- Item: \(item.id) ---")
                print("Raw imageURL: '\(item.imageURL)'")
                
                // Test the URL conversion
                if let url = convertImageURL(item.imageURL) {
                    validURLs += 1
                    print("✅ Valid URL: \(url)")
                    
                    // Test network access
                    testImageURLAccess(url) { success in
                        if success {
                            print("✅ Image accessible")
                        } else {
                            print("❌ Image not accessible")
                        }
                    }
                } else {
                    invalidURLs += 1
                    print("❌ Invalid URL")
                }
            }
        }
        
        print("\n📊 Summary:")
        print("Total items: \(totalItems)")
        print("Valid URLs: \(validURLs)")
        print("Invalid URLs: \(invalidURLs)")
    }
    
    /// Convert image URL using the same logic as MenuItemCard
    private func convertImageURL(_ imageURL: String) -> URL? {
        guard !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        if imageURL.hasPrefix("gs://") {
            let components = imageURL.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
                return URL(string: downloadURL)
            }
        } else if imageURL.hasPrefix("https://firebasestorage.googleapis.com") {
            return URL(string: imageURL)
        } else if imageURL.hasPrefix("http") {
            return URL(string: imageURL)
        }
        
        return nil
    }
    
    /// Test if an image URL is accessible
    private func testImageURLAccess(_ url: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "HEAD" // Just check if the resource exists
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error: \(error.localizedDescription)")
                    completion(false)
                } else if let httpResponse = response as? HTTPURLResponse {
                    let success = httpResponse.statusCode == 200
                    print("📡 HTTP Status: \(httpResponse.statusCode) - \(success ? "✅" : "❌")")
                    completion(success)
                } else {
                    print("❌ No HTTP response")
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Drink Options Debugging
    
    /// Debug function to test drink options configuration
    func debugDrinkOptions() {
        print("🔍 Debugging drink options...")
        print("Total drink options: \(drinkOptions.count)")
        
        let toppings = drinkOptions.filter { !$0.isMilkSub }
        let milkSubs = drinkOptions.filter { $0.isMilkSub }
        
        print("Toppings: \(toppings.count)")
        for topping in toppings {
            print("  - \(topping.name) (ID: \(topping.id), Price: $\(topping.price))")
        }
        
        print("Milk Substitutions: \(milkSubs.count)")
        for milkSub in milkSubs {
            print("  - \(milkSub.name) (ID: \(milkSub.id), Price: $\(milkSub.price))")
        }
        
        print("\n📊 Menu Items with Drink Options:")
        for category in menuCategories {
            for item in category.items ?? [] {
                // Check items that have topping or milk sub modifiers enabled
                if item.toppingModifiersEnabled || item.milkSubModifiersEnabled {
                    print("\n--- Item: \(item.id) (Category: \(category.id)) ---")
                    print("  toppingModifiersEnabled: \(item.toppingModifiersEnabled)")
                    print("  milkSubModifiersEnabled: \(item.milkSubModifiersEnabled)")
                    print("  availableToppingIDs: \(item.availableToppingIDs)")
                    print("  availableMilkSubIDs: \(item.availableMilkSubIDs)")
                    
                    // Test available options
                    let availableToppings = item.availableToppingIDs.compactMap { toppingID in
                        drinkOptions.first(where: { $0.id == toppingID && !$0.isMilkSub })
                    }
                    let availableMilkSubs = item.availableMilkSubIDs.compactMap { milkID in
                        drinkOptions.first(where: { $0.id == milkID && $0.isMilkSub })
                    }
                    
                    print("  Available toppings: \(availableToppings.count)")
                    print("  Available milk subs: \(availableMilkSubs.count)")
                }
            }
        }
    }
}
