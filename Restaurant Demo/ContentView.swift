import SwiftUI
import FirebaseAuth
import os

extension Notification.Name {
    static let switchToHomeTab = Notification.Name("switchToHomeTab")
    static let switchToCommunityTab = Notification.Name("switchToCommunityTab")
    static let switchToMoreTab = Notification.Name("switchToMoreTab")
    static let incomingReferralCode = Notification.Name("incomingReferralCode")
}

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var themeManager = DynamicThemeManager()
    @StateObject private var visualIntelligence = VisualIntelligenceManager()
    @StateObject private var smartLayout = SmartLayoutManager()
    @StateObject private var userVM = UserViewModel()
    @StateObject private var sharedRewardsVM = RewardsViewModel()
    @StateObject private var notificationService = NotificationService.shared
    
    // Performance signposts (visible in Instruments → Points of Interest)
    private let perfLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "RestaurantDemo", category: "Perf")

    @Namespace private var heroNamespace

    // Deep link support: show ReferralView when an incoming code arrives while logged in
    @State private var showReferralSheet: Bool = false
    @State private var referralSheetCode: String = ""

    var body: some View {
        ZStack {
            // Dynamic themed background
            ThemedBackground()
                .environmentObject(themeManager)
            
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)
                
                MenuView()
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("Menu")
                    }
                    .tag(1)
                
                ReceiptScanView()
                    .tabItem {
                        Image(systemName: "camera.fill")
                        Text("Scan Receipt")
                    }
                    .tag(2)
                
                UnifiedRewardsScreen(mode: .tabRoot)
                    .tabItem {
                        Image(systemName: "gift.fill")
                        Text("Rewards")
                    }
                    .tag(3)
                
                MoreView()
                    .tabItem {
                        Image(systemName: "line.3.horizontal")
                        Text("More")
                    }
                    .badge(notificationService.unreadNotificationCount > 0 ? "\(notificationService.unreadNotificationCount)" : nil)
                    .tag(4)
            }
            .accentColor(Color(red: 0.7, green: 0.5, blue: 0.1))
            .environmentObject(userVM)
            .environmentObject(sharedRewardsVM)
            .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                selectedTab = 0
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToCommunityTab)) { _ in
                selectedTab = 4
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToMoreTab)) { _ in
                selectedTab = 4
            }
            .onAppear {
                setupThemeTracking()
                // Start/attach the user snapshot listener once for the app session.
                userVM.loadUserData()
                // Clear old cache format that may contain https:// URLs
                ReferralCache.clearLegacyCache()
                preloadReferralCodeForAuthenticatedUser()
                consumePendingReferralCodeIfPresent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .incomingReferralCode)) { notif in
                let code = (notif.userInfo?["code"] as? String) ?? ""
                handleIncomingReferral(code: code)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("didTapPushNotification"))) { notif in
                if let userInfo = notif.userInfo as? [String: Any] {
                    NotificationService.shared.handlePushNotificationTap(userInfo: userInfo)
                }
            }
            .alert("Account Banned", isPresented: $userVM.showBannedAlert) {
                Button("OK", role: .cancel) {
                    userVM.showBannedAlert = false
                }
            } message: {
                Text("Your account has been banned. You will be signed out. Please contact support if you believe this is an error.")
            }
            .onChange(of: selectedTab) { _, newTab in
                updateThemeContext(for: newTab)
                trackUserInteraction(for: newTab)
                os_signpost(.event, log: perfLog, name: "TabSwitch", "%{public}d", newTab)
            }
        }
        .sheet(isPresented: $showReferralSheet) {
            ReferralView(initialCode: referralSheetCode)
        }
    }
    
    // MARK: - Theme Management
    private func setupThemeTracking() {
        updateThemeContext(for: selectedTab)
    }
    
    private func updateThemeContext(for tab: Int) {
        switch tab {
        case 0: // Home
            themeManager.contentContext = .menu
        case 1: // Menu
            themeManager.contentContext = .menu
        case 2: // Scan Receipt
            themeManager.contentContext = .ordering
        case 3: // Rewards
            themeManager.contentContext = .menu
        case 4: // Community
            themeManager.contentContext = .community
        default:
            themeManager.contentContext = .menu
        }
        themeManager.determineThemeBasedOnContext()
    }
    
    private func trackUserInteraction(for tab: Int) {
        // Analytics tracking for tab interactions
        print("User switched to tab: \(tab)")
    }
    
    // MARK: - Referral Code Preload
    
    /// Pre-fetches and caches the user's referral code for instant loading in ReferralView
    private func preloadReferralCodeForAuthenticatedUser() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        
        // Check if already cached to avoid unnecessary network calls
        if let _ = ReferralCache.load(userId: uid) {
            print("✅ Referral code already cached, skipping preload")
            return
        }
        
        print("🔄 Pre-loading referral code for instant access...")
        
        user.getIDToken { token, err in
            guard let token = token, err == nil else {
                print("⚠️ Failed to get token for referral preload")
                return
            }
            
            guard let url = URL(string: "\(Config.backendURL)/referrals/create") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard let http = resp as? HTTPURLResponse,
                      http.statusCode >= 200 && http.statusCode < 300,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = json["code"] as? String,
                      let shareUrl = (json["webUrl"] as? String) ?? (json["shareUrl"] as? String),
                      !code.isEmpty else {
                    print("⚠️ Failed to preload referral code")
                    return
                }
                
                // Cache the referral code using the same cache system as ReferralView
                ReferralCache.save(code: code, shareUrl: shareUrl, userId: uid)
                print("✅ Referral code preloaded and cached for instant loading")
            }.resume()
        }
    }

    // MARK: - Referral Deep Link Handling (logged-in)
    private func consumePendingReferralCodeIfPresent() {
        guard let code = ReferralDeepLinkStore.getPending() else { return }
        // Clear immediately so we don't repeatedly pop the sheet
        ReferralDeepLinkStore.clearPending()
        handleIncomingReferral(code: code)
    }

    private func handleIncomingReferral(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        referralSheetCode = trimmed
        showReferralSheet = true
    }
}

// MARK: - Referral Cache (shared with ReferralView and AuthenticationViewModel)
fileprivate struct ReferralCache {
    // Updated cache key to v4: bust cache after referral code reset/migration
    private static let cacheKeyPrefix = "referral_cache_v4_"
    
    struct CachedData: Codable {
        let code: String
        let shareUrl: String
        let timestamp: Date
    }
    
    static func save(code: String, shareUrl: String, userId: String) {
        let data = CachedData(code: code, shareUrl: shareUrl, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: cacheKeyPrefix + userId)
        }
    }
    
    static func load(userId: String) -> (code: String, shareUrl: String)? {
        guard let data = UserDefaults.standard.data(forKey: cacheKeyPrefix + userId),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        return (cached.code, cached.shareUrl)
    }
    
    static func clearLegacyCache() {
        // Clear old cache formats (v1 and v2) that may contain wrong URLs
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("referral_cache_") && !key.hasPrefix(cacheKeyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
            print("🗑️ Cleared legacy referral cache: \(key)")
        }
    }
}

// MARK: - Hero Namespace Environment Key
struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

// MARK: - Dumpling Gold Color (for backward compatibility)
extension Color {
    static let dumplingGold = Color(red: 0.9, green: 0.7, blue: 0.3)
}
