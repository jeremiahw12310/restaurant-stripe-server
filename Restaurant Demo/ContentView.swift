import SwiftUI

extension Notification.Name {
    static let switchToHomeTab = Notification.Name("switchToHomeTab")
}

struct ContentView: View {
    // ✅ NEW: Create a single instance of the CartManager to be shared across all tabs.
    @StateObject private var cartManager = CartManager()
    @State private var selectedTab = 0
    @State private var showCartModal = false

    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 1.0, green: 0.98, blue: 0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Flying dumpling animation overlay
            FlyingDumplingView(isVisible: $cartManager.showFlyingDumpling)
                .environmentObject(cartManager)
                .zIndex(1000)
            
            // Flying boba animation overlay
            FlyingBobaView(isVisible: $cartManager.showFlyingBoba)
                .environmentObject(cartManager)
                .zIndex(1000)
            
            // Floating cart card triggers modal
            FloatingCartCard(selectedTab: $selectedTab, showCartModal: $showCartModal)
                .zIndex(1001)
            
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)
                
                CommunityView()
                    .tabItem {
                        Label("Community", systemImage: "person.3.fill")
                    }
                    .tag(1)
                
                OrderView()
                    .tabItem {
                        Label("Menu", systemImage: "fork.knife.circle.fill")
                    }
                    .tag(2)
                
                ReceiptScanView()
                    .tabItem {
                        Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                    }
                    .tag(3)
            }
            .accentColor(Color(red: 0.2, green: 0.6, blue: 0.9))
            .onAppear {
                // Customize tab bar appearance
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
                appearance.shadowColor = .clear
                
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
                
                // Listen for tab switch notifications
                NotificationCenter.default.addObserver(
                    forName: .switchToHomeTab,
                    object: nil,
                    queue: .main
                ) { _ in
                    // Switch immediately for seamless transition
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 0
                    }
                }
            }
        }
        // ✅ NEW: Provide the CartManager to all child views in the environment.
        .environmentObject(cartManager)
        .sheet(isPresented: $showCartModal) {
            CartView()
                .environmentObject(cartManager)
        }
    }
}
#Preview {
    ContentView()
}
