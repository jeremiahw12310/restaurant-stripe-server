import SwiftUI
import Combine
import UIKit
import Kingfisher
import os.log
import Network

// MARK: - Performance Manager
class PerformanceManager: ObservableObject {
    @Published var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var memoryUsage: Double = 0.0
    @Published var isOptimizedMode = false
    @Published var networkQuality: NetworkQuality = .excellent
    @Published var performanceMetrics = SystemPerformanceMetrics()
    
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "RestaurantDemo", category: "Performance")
    private let memoryWarningSubject = PassthroughSubject<Void, Never>()
    
    static let shared = PerformanceManager()
    
    private init() {
        setupPerformanceMonitoring()
        setupLowPowerModeObserver()
        setupMemoryWarningObserver()
        startPerformanceTracking()
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: 2.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePerformanceMetrics()
            }
            .store(in: &cancellables)
    }
    
    private func setupLowPowerModeObserver() {
        NotificationCenter.default
            .publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                    self?.adjustPerformanceSettings()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func updatePerformanceMetrics() {
        memoryUsage = getCurrentMemoryUsage()
        performanceMetrics.updateMetrics(
            memoryUsage: memoryUsage,
            isLowPowerMode: isLowPowerModeEnabled
        )
        
        if memoryUsage > 0.8 {
            optimizeMemoryUsage()
        }
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / 1024.0 / 1024.0 // MB
            let availableMemory = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0 / 1024.0 // GB
            return usedMemory / (availableMemory * 1024.0)
        }
        
        return 0.0
    }
    
    func adjustPerformanceSettings() {
        isOptimizedMode = isLowPowerModeEnabled || memoryUsage > 0.7
        
        if isOptimizedMode {
            ImageCacheManager.shared.enableLowMemoryMode()
            NetworkManager.shared.enableDataSaving()
        } else {
            ImageCacheManager.shared.disableLowMemoryMode()
            NetworkManager.shared.disableDataSaving()
        }
        
        logger.info("Performance settings adjusted: optimized=\(self.isOptimizedMode)")
    }
    
    private func handleMemoryWarning() {
        logger.warning("Memory warning received - cleaning up caches")
        ImageCacheManager.shared.clearCache()
        // Performance: Also clear menu and promo image memory caches
        MenuImageCacheManager.shared.clearMemoryCache()
        PromoImageCacheManager.shared.clearMemoryCache()
        LazyLoadingManager.shared.purgeInactiveContent()
        memoryWarningSubject.send()
    }
    
    private func optimizeMemoryUsage() {
        Task {
            await MainActor.run {
                ImageCacheManager.shared.optimizeCache()
                LazyLoadingManager.shared.optimizeLoadedContent()
            }
        }
    }
    
    private func startPerformanceTracking() {
        performanceMetrics.startTracking()
    }
}

// MARK: - System Performance Metrics
struct SystemPerformanceMetrics {
    var avgMemoryUsage: Double = 0.0
    var peakMemoryUsage: Double = 0.0
    var totalLazyLoads: Int = 0
    var cacheHitRate: Double = 0.0
    var networkRequests: Int = 0
    var energyLevel: EnergyLevel = .normal
    
    private var memoryReadings: [Double] = []
    
    mutating func updateMetrics(memoryUsage: Double, isLowPowerMode: Bool) {
        memoryReadings.append(memoryUsage)
        if memoryReadings.count > 20 {
            memoryReadings.removeFirst()
        }
        
        avgMemoryUsage = memoryReadings.reduce(0, +) / Double(memoryReadings.count)
        peakMemoryUsage = max(peakMemoryUsage, memoryUsage)
        energyLevel = isLowPowerMode ? .low : (memoryUsage > 0.7 ? .high : .normal)
    }
    
    func startTracking() {
        // Initialize performance tracking
    }
}

// MARK: - Lazy Loading Manager
class LazyLoadingManager: ObservableObject {
    @Published var loadedContent: Set<String> = []
    @Published var isLoadingContent: Set<String> = []
    
    private var contentCache: [String: Any] = [:]
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    
    static let shared = LazyLoadingManager()
    
    private init() {}
    
    func loadContent<T>(id: String, loader: @escaping () async -> T) async -> T? {
        if let cached = contentCache[id] as? T {
            return cached
        }
        
        if isLoadingContent.contains(id) {
            // Wait for existing task
            await loadingTasks[id]?.value
            return contentCache[id] as? T
        }
        
        _ = await MainActor.run {
            isLoadingContent.insert(id)
        }
        
        let task = Task {
            let content = await loader()
            await MainActor.run {
                self.contentCache[id] = content
                self.loadedContent.insert(id)
                self.isLoadingContent.remove(id)
                self.loadingTasks.removeValue(forKey: id)
            }
        }
        
        loadingTasks[id] = task
        await task.value
        
        return contentCache[id] as? T
    }
    
    func preloadContent<T>(id: String, loader: @escaping () async -> T) {
        guard !loadedContent.contains(id) && !isLoadingContent.contains(id) else { return }
        
        Task {
            await loadContent(id: id, loader: loader)
        }
    }
    
    func purgeInactiveContent() {
        let activeContentIds = Set(loadedContent.prefix(10)) // Keep only recent 10
        for id in loadedContent {
            if !activeContentIds.contains(id) {
                contentCache.removeValue(forKey: id)
                loadedContent.remove(id)
            }
        }
    }
    
    func optimizeLoadedContent() {
        if loadedContent.count > 50 {
            let oldestContent = loadedContent.prefix(loadedContent.count - 30)
            for id in oldestContent {
                contentCache.removeValue(forKey: id)
                loadedContent.remove(id)
            }
        }
    }
}

// MARK: - Image Cache Manager
class ImageCacheManager: ObservableObject {
    @Published var cacheSize: Int64 = 0
    @Published var isLowMemoryMode = false
    
    private let maxCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
    private let lowMemoryCacheSize: Int64 = 50 * 1024 * 1024 // 50MB
    
    static let shared = ImageCacheManager()
    
    private init() {
        setupImageCache()
    }
    
    private func setupImageCache() {
        let cache = KingfisherManager.shared.cache
        
        // Configure memory cache
        cache.memoryStorage.config.totalCostLimit = isLowMemoryMode ? 20 * 1024 * 1024 : 50 * 1024 * 1024
        cache.memoryStorage.config.countLimit = isLowMemoryMode ? 50 : 100
        
        // Configure disk cache
        cache.diskStorage.config.sizeLimit = UInt(isLowMemoryMode ? lowMemoryCacheSize : maxCacheSize)
        cache.diskStorage.config.expiration = .seconds(604800) // 1 week
        
        // Set up cache size monitoring
        updateCacheSize()
    }
    
    func enableLowMemoryMode() {
        isLowMemoryMode = true
        setupImageCache()
        
        // Clear excess cache
        let cache = KingfisherManager.shared.cache
        cache.clearMemoryCache()
        
        Task {
            // Clear cache to reduce size when in low memory mode
            cache.clearMemoryCache()
            cache.clearDiskCache()
        }
    }
    
    func disableLowMemoryMode() {
        isLowMemoryMode = false
        setupImageCache()
    }
    
    func clearCache() {
        let cache = KingfisherManager.shared.cache
        cache.clearMemoryCache()
        cache.clearDiskCache()
        cacheSize = 0
    }
    
    func optimizeCache() {
        let cache = KingfisherManager.shared.cache
        
        Task {
            // Clear cache when it gets too large
            cache.clearMemoryCache()
            
            await MainActor.run {
                updateCacheSize()
            }
        }
    }
    
    private func updateCacheSize() {
        Task {
            // Use simplified cache size calculation
            await MainActor.run {
                self.cacheSize = 0 // Simplified for now
            }
        }
    }
}

// MARK: - Network Manager
class NetworkManager: ObservableObject {
    @Published var isDataSavingEnabled = false
    @Published var networkQuality: NetworkQuality = .excellent
    
    private var reachability: NetworkReachability?
    
    static let shared = NetworkManager()
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        reachability = NetworkReachability()
        reachability?.startMonitoring { [weak self] quality in
            DispatchQueue.main.async {
                self?.networkQuality = quality
                self?.adjustNetworkSettings()
            }
        }
    }
    
    private func adjustNetworkSettings() {
        let shouldEnableDataSaving = networkQuality == .poor || PerformanceManager.shared.isLowPowerModeEnabled
        
        if shouldEnableDataSaving != isDataSavingEnabled {
            isDataSavingEnabled = shouldEnableDataSaving
            configureImageLoading()
        }
    }
    
    func enableDataSaving() {
        isDataSavingEnabled = true
        configureImageLoading()
    }
    
    func disableDataSaving() {
        isDataSavingEnabled = false
        configureImageLoading()
    }
    
    private func configureImageLoading() {
        let processor: ImageProcessor = isDataSavingEnabled ? 
            ResizingImageProcessor(referenceSize: CGSize(width: 200, height: 200)) |>
            BlurImageProcessor(blurRadius: 1.0) :
            DefaultImageProcessor.default
        
        KingfisherManager.shared.defaultOptions = [
            .processor(processor),
            .cacheSerializer(FormatIndicatedCacheSerializer.png),
            .scaleFactor(isDataSavingEnabled ? 1.0 : UIScreen.main.scale)
        ]
    }
}

// MARK: - Network Reachability
class NetworkReachability {
    private var monitor: Any?
    
    func startMonitoring(callback: @escaping (NetworkQuality) -> Void) {
        if #available(iOS 12.0, *) {
            let monitor = NWPathMonitor()
            self.monitor = monitor
            
            monitor.pathUpdateHandler = { path in
                let quality: NetworkQuality
                
                if path.status == .satisfied {
                    if path.isExpensive {
                        quality = .poor
                    } else if path.availableInterfaces.contains(where: { $0.type == .wifi }) {
                        quality = .excellent
                    } else {
                        quality = .good
                    }
                } else {
                    quality = .offline
                }
                
                callback(quality)
            }
            
            let queue = DispatchQueue(label: "NetworkMonitor")
            monitor.start(queue: queue)
        }
    }
}

// MARK: - Supporting Types
enum NetworkQuality: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case poor = "Poor"
    case offline = "Offline"
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .yellow
        case .poor: return .orange
        case .offline: return .red
        }
    }
}

enum EnergyLevel: String, CaseIterable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .normal: return .blue
        case .high: return .red
        }
    }
}

// MARK: - Performance-Optimized Views
struct LazyImageView: View {
    let url: URL?
    let placeholder: String
    @StateObject private var performanceManager = PerformanceManager.shared
    @StateObject private var imageCache = ImageCacheManager.shared
    
    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: placeholder)
                .foregroundColor(.gray)
        }
        .onAppear {
            if let url = url {
                KingfisherManager.shared.retrieveImage(with: url) { _ in }
            }
        }
    }
}

struct LazyContentView<Content: View>: View {
    let id: String
    let content: () -> Content
    let placeholder: () -> Content
    
    @StateObject private var lazyLoader = LazyLoadingManager.shared
    @State private var isLoaded = false
    
    var body: some View {
        Group {
            if isLoaded || lazyLoader.loadedContent.contains(id) {
                content()
            } else {
                placeholder()
                    .onAppear {
                        loadContent()
                    }
            }
        }
    }
    
    private func loadContent() {
        Task {
            await lazyLoader.loadContent(id: id) {
                await MainActor.run {
                    isLoaded = true
                }
            }
        }
    }
}

// MARK: - Performance Dashboard
struct PerformanceDashboard: View {
    @StateObject private var performanceManager = PerformanceManager.shared
    @StateObject private var imageCache = ImageCacheManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        NavigationView {
            List {
                Section("System Performance") {
                    PerformanceMetricRow(
                        title: "Memory Usage",
                        value: "\(Int(performanceManager.memoryUsage * 100))%",
                        color: performanceManager.memoryUsage > 0.8 ? .red : .green
                    )
                    
                    PerformanceMetricRow(
                        title: "Energy Level",
                        value: performanceManager.performanceMetrics.energyLevel.rawValue,
                        color: performanceManager.performanceMetrics.energyLevel.color
                    )
                    
                    PerformanceMetricRow(
                        title: "Low Power Mode",
                        value: performanceManager.isLowPowerModeEnabled ? "Enabled" : "Disabled",
                        color: performanceManager.isLowPowerModeEnabled ? .orange : .green
                    )
                }
                
                Section("Network & Caching") {
                    PerformanceMetricRow(
                        title: "Network Quality",
                        value: networkManager.networkQuality.rawValue,
                        color: networkManager.networkQuality.color
                    )
                    
                    PerformanceMetricRow(
                        title: "Data Saving",
                        value: networkManager.isDataSavingEnabled ? "Enabled" : "Disabled",
                        color: networkManager.isDataSavingEnabled ? .green : .blue
                    )
                    
                    PerformanceMetricRow(
                        title: "Cache Size",
                        value: formatBytes(imageCache.cacheSize),
                        color: .blue
                    )
                }
                
                Section("Optimization") {
                    Button("Clear Cache") {
                        imageCache.clearCache()
                    }
                    .foregroundColor(.red)
                    
                    Button("Optimize Performance") {
                        performanceManager.adjustPerformanceSettings()
                    }
                    .foregroundColor(.blue)
                    
                    Toggle("Low Memory Mode", isOn: .constant(imageCache.isLowMemoryMode))
                        .disabled(true)
                }
            }
            .navigationTitle("Performance")
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct PerformanceMetricRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Performance Modifiers
extension View {
    func optimizedForPerformance() -> some View {
        self.drawingGroup(opaque: false, colorMode: .nonLinear)
    }
    
    func lazyLoad(threshold: CGFloat = 50) -> some View {
        self.onAppear {
            // Preload nearby content
        }
    }
    
    func memoryEfficient() -> some View {
        self.clipped()
            .drawingGroup()
    }
} 