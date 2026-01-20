import SwiftUI
import CoreData
import Network
import Combine
import FirebaseFirestore
import Kingfisher

// MARK: - Offline Mode Manager
class OfflineModeManager: ObservableObject {
    @Published var isOnline = true
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0.0
    @Published var pendingActions: [OfflineAction] = []
    @Published var lastSyncDate: Date?
    @Published var cachedItemsCount = 0
    
    private var monitor: NWPathMonitor
    private var queue = DispatchQueue(label: "NetworkMonitor")
    private var cancellables = Set<AnyCancellable>()
    private let syncManager = OfflineSyncManager()
    private let cacheManager = OfflineCacheManager()
    
    static let shared = OfflineModeManager()
    
    private init() {
        monitor = NWPathMonitor()
        setupNetworkMonitoring()
        loadCachedData()
        loadPendingActions()
    }
    
    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied
                
                // Auto-sync when coming back online
                if wasOffline && self?.isOnline == true {
                    self?.syncPendingActions()
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    // MARK: - Cache Management
    func cacheData(_ data: Any, forKey key: String, type: CacheType) {
        cacheManager.cache(data, forKey: key, type: type)
        updateCachedItemsCount()
    }
    
    func getCachedData(forKey key: String, type: CacheType) -> Any? {
        return cacheManager.getCachedData(forKey: key, type: type)
    }
    
    func clearCache() {
        cacheManager.clearCache()
        updateCachedItemsCount()
    }
    
    private func loadCachedData() {
        cachedItemsCount = cacheManager.getTotalCachedItems()
        lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    private func updateCachedItemsCount() {
        cachedItemsCount = cacheManager.getTotalCachedItems()
    }
    
    // MARK: - Offline Actions
    func queueAction(_ action: OfflineAction) {
        pendingActions.append(action)
        savePendingActions()
        
        // Try to execute immediately if online
        if isOnline {
            syncPendingActions()
        }
    }
    
    func syncPendingActions() {
        guard isOnline && !isSyncing else { return }
        
        isSyncing = true
        syncProgress = 0.0
        
        syncManager.syncActions(pendingActions) { [weak self] progress in
            DispatchQueue.main.async {
                self?.syncProgress = progress
            }
        } completion: { [weak self] success, completedActions in
            DispatchQueue.main.async {
                self?.isSyncing = false
                self?.syncProgress = 1.0
                
                if success {
                    self?.pendingActions.removeAll { action in
                        completedActions.contains(action.id)
                    }
                    self?.lastSyncDate = Date()
                    UserDefaults.standard.set(self?.lastSyncDate, forKey: "lastSyncDate")
                    self?.savePendingActions()
                }
                
                // Reset progress after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.syncProgress = 0.0
                }
            }
        }
    }
    
    // FIXED: Add method to clear all potentially problematic data from UserDefaults
    func clearAllUserDefaultsData() {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys
        
        for key in keys {
            // Clear all potentially large data
            if key.contains("pendingActions") || 
               key.contains("videos_") || 
               key.contains("posts_") || 
               key.contains("comments_") ||
               key.contains("userProfiles_") ||
               key.contains("menuItems_") {
                userDefaults.removeObject(forKey: key)
                print("🧹 Cleared UserDefaults key: \(key)")
            }
        }
        
        // Clear pending actions specifically
        pendingActions.removeAll()
        savePendingActions()
        
        print("✅ All UserDefaults data cleared to prevent storage bloat")
    }
    
    // FIXED: Add size limit to pending actions to prevent storage bloat
    private func savePendingActions() {
        // Limit pending actions to prevent storage bloat
        if pendingActions.count > 50 {
            // Keep only the most recent 50 actions
            pendingActions = Array(pendingActions.suffix(50))
            print("⚠️ Limited pending actions to 50 to prevent storage bloat")
        }
        
        if let data = try? JSONEncoder().encode(pendingActions) {
            // Check if data is too large (over 1MB)
            if data.count > 1024 * 1024 {
                print("⚠️ Pending actions data too large (\(data.count) bytes), clearing old actions")
                // Keep only the most recent 10 actions
                pendingActions = Array(pendingActions.suffix(10))
                if let newData = try? JSONEncoder().encode(pendingActions) {
                    UserDefaults.standard.set(newData, forKey: "pendingActions")
                }
            } else {
                UserDefaults.standard.set(data, forKey: "pendingActions")
            }
        }
    }
    
    private func loadPendingActions() {
        guard let data = UserDefaults.standard.data(forKey: "pendingActions"),
              let actions = try? JSONDecoder().decode([OfflineAction].self, from: data) else { return }
        pendingActions = actions
    }
}

// MARK: - Offline Action Model
struct OfflineAction: Codable, Identifiable {
    let id: UUID
    let type: ActionType
    let data: Data
    let timestamp: Date
    let retryCount: Int
    
    init(type: ActionType, data: Data, timestamp: Date = Date(), retryCount: Int = 0) {
        self.id = UUID()
        self.type = type
        self.data = data
        self.timestamp = timestamp
        self.retryCount = retryCount
    }
    
    enum ActionType: String, Codable {
        case createPost
        case updatePost
        case deletePost
        case addComment
        case updateComment
        case deleteComment
        case likePost
        case unlikePost
        case updateProfile
        case uploadImage
    }
}

// MARK: - Cache Types
enum CacheType {
    case menuItems
    case posts
    case comments
    case userProfiles
    case images
    case videos
}

// MARK: - Offline Cache Manager
class OfflineCacheManager {
    private let userDefaults = UserDefaults.standard
    private let imageCache = ImageCache.default
    
    // FIXED: Remove video data storage from UserDefaults to prevent storage bloat
    // Videos should not be cached in UserDefaults as they can be very large
    func cache(_ data: Any, forKey key: String, type: CacheType) {
        let fullKey = "\(type)_\(key)"
        
        switch type {
        case .images:
            // Images are handled by Kingfisher
            break
        case .videos:
            // FIXED: Don't store video data in UserDefaults - it causes storage bloat
            // Videos should be streamed from Firebase Storage, not cached locally
            print("⚠️ Video caching disabled to prevent storage bloat")
            break
        default:
            if let encodableData = try? JSONSerialization.data(withJSONObject: data) {
                userDefaults.set(encodableData, forKey: fullKey)
            }
        }
    }
    
    func getCachedData(forKey key: String, type: CacheType) -> Any? {
        let fullKey = "\(type)_\(key)"
        
        switch type {
        case .images:
            return nil // Handled by Kingfisher
        case .videos:
            // FIXED: Don't retrieve video data from UserDefaults
            return nil
        default:
            guard let data = userDefaults.data(forKey: fullKey) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }
    
    func clearCache() {
        let keys = userDefaults.dictionaryRepresentation().keys
        for key in keys {
            if key.contains("menuItems_") || key.contains("posts_") || 
               key.contains("comments_") || key.contains("userProfiles_") {
                userDefaults.removeObject(forKey: key)
            }
        }
        imageCache.clearCache()
        
        // FIXED: Clear any remaining video data that might have been stored before this fix
        for key in keys {
            if key.contains("videos_") {
                userDefaults.removeObject(forKey: key)
                print("🧹 Cleared video data from UserDefaults: \(key)")
            }
        }
    }
    
    func getTotalCachedItems() -> Int {
        let keys = userDefaults.dictionaryRepresentation().keys
        let dataItemsCount = keys.filter { key in
            key.contains("menuItems_") || key.contains("posts_") || 
            key.contains("comments_") || key.contains("userProfiles_")
        }.count
        
        // Add estimated image cache count (simplified approach)
        return dataItemsCount + 10 // Rough estimate for demo purposes
    }
    
    // FIXED: Add method to get cache size for monitoring
    func getCacheSize() -> Int64 {
        let keys = userDefaults.dictionaryRepresentation().keys
        var totalSize: Int64 = 0
        
        for key in keys {
            if key.contains("menuItems_") || key.contains("posts_") || 
               key.contains("comments_") || key.contains("userProfiles_") {
                if let data = userDefaults.data(forKey: key) {
                    totalSize += Int64(data.count)
                }
            }
        }
        
        return totalSize
    }
}

// MARK: - Offline Sync Manager
class OfflineSyncManager {
    private let db = Firestore.firestore()
    
    func syncActions(_ actions: [OfflineAction], 
                    progressCallback: @escaping (Double) -> Void,
                    completion: @escaping (Bool, [UUID]) -> Void) {
        
        guard !actions.isEmpty else {
            completion(true, [])
            return
        }
        
        var completedActions: [UUID] = []
        let totalActions = actions.count
        var processedActions = 0
        
        for action in actions {
            syncSingleAction(action) { success in
                processedActions += 1
                
                if success {
                    completedActions.append(action.id)
                }
                
                let progress = Double(processedActions) / Double(totalActions)
                progressCallback(progress)
                
                if processedActions == totalActions {
                    completion(true, completedActions)
                }
            }
        }
    }
    
    private func syncSingleAction(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        switch action.type {
        case .createPost:
            syncCreatePost(action, completion: completion)
        case .updatePost:
            syncUpdatePost(action, completion: completion)
        case .deletePost:
            syncDeletePost(action, completion: completion)
        case .addComment:
            syncAddComment(action, completion: completion)
        case .likePost:
            syncLikePost(action, completion: completion)
        case .updateProfile:
            syncUpdateProfile(action, completion: completion)
        default:
            completion(false)
        }
    }
    
    private func syncCreatePost(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        // Implement post creation sync
        // This would decode the action data and create the post in Firestore
        completion(true) // Placeholder
    }
    
    private func syncUpdatePost(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        // Implement post update sync
        completion(true) // Placeholder
    }
    
    private func syncDeletePost(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        // Implement post deletion sync
        completion(true) // Placeholder
    }
    
    private func syncAddComment(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        // Implement comment sync
        completion(true) // Placeholder
    }
    
    private func syncLikePost(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        // Implement like sync
        completion(true) // Placeholder
    }
    
    private func syncUpdateProfile(_ action: OfflineAction, completion: @escaping (Bool) -> Void) {
        // Implement profile update sync
        completion(true) // Placeholder
    }
}

// MARK: - Offline Mode UI Components
struct OfflineModeIndicator: View {
    @ObservedObject var offlineManager = OfflineModeManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if !offlineManager.isOnline {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                    Text("Offline Mode")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))
                .cornerRadius(20)
            }
            
            if offlineManager.isSyncing {
                HStack {
                    ProgressView(value: offlineManager.syncProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 100)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.1))
                .cornerRadius(20)
            }
        }
    }
}

struct OfflineModeSettings: View {
    @ObservedObject var offlineManager = OfflineModeManager.shared
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Connection Status") {
                    HStack {
                        Circle()
                            .fill(offlineManager.isOnline ? .green : .red)
                            .frame(width: 12, height: 12)
                        Text(offlineManager.isOnline ? "Online" : "Offline")
                            .font(.headline)
                        Spacer()
                        if offlineManager.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                
                Section("Cache Information") {
                    HStack {
                        Text("Cached Items")
                        Spacer()
                        Text("\(offlineManager.cachedItemsCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastSync = offlineManager.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Pending Actions")
                        Spacer()
                        Text("\(offlineManager.pendingActions.count)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Actions") {
                    Button("Sync Now") {
                        offlineManager.syncPendingActions()
                    }
                    .disabled(!offlineManager.isOnline || offlineManager.isSyncing)
                    
                    Button("Clear Cache") {
                        showingClearAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                if !offlineManager.pendingActions.isEmpty {
                    Section("Pending Actions") {
                        ForEach(offlineManager.pendingActions) { action in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(action.type.rawValue.capitalized)
                                        .font(.headline)
                                    Text(action.timestamp, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if action.retryCount > 0 {
                                    Text("\(action.retryCount) retries")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Offline Mode")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Clear Cache", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                offlineManager.clearCache()
            }
        } message: {
            Text("This will clear all cached data and you'll need to reload content when back online.")
        }
    }
}

// MARK: - Offline-Aware Components
struct OfflineAwareAsyncImage: View {
    let url: URL?
    let cacheKey: String
    @ObservedObject private var offlineManager = OfflineModeManager.shared
    
    var body: some View {
        Group {
            if let url = url {
                KFImage(url)
                    .cacheOriginalImage()
                    .fade(duration: 0.3)
                    .onSuccess { result in
                        // Cache successful loads
                        offlineManager.cacheData(url.absoluteString, forKey: cacheKey, type: .images)
                    }
                    .placeholder {
                        ProgressView()
                            .frame(width: 50, height: 50)
                    }
                    .retry(maxCount: offlineManager.isOnline ? 3 : 0)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Offline Data Extensions
extension View {
    func withOfflineSupport() -> some View {
        self.overlay(
            OfflineModeIndicator(),
            alignment: .top
        )
    }
}

// MARK: - Network-Aware Modifier
struct NetworkAwareModifier: ViewModifier {
    @ObservedObject private var offlineManager = OfflineModeManager.shared
    
    func body(content: Content) -> some View {
        content
            .disabled(!offlineManager.isOnline)
            .opacity(offlineManager.isOnline ? 1.0 : 0.6)
            .overlay(
                Group {
                    if !offlineManager.isOnline {
                        VStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                            Text("Requires Internet")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            )
    }
}

extension View {
    func requiresInternet() -> some View {
        self.modifier(NetworkAwareModifier())
    }
} 