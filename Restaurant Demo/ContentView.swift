import SwiftUI

struct ContentView: View {
    // ✅ NEW: Create a single instance of the CartManager to be shared across all tabs.
    @StateObject private var cartManager = CartManager()

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
            
            TabView {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                
                OrderView()
                    .tabItem {
                        Label("Menu", systemImage: "fork.knife.circle.fill")
                    }
                
                ReceiptScanView()
                    .tabItem {
                        Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                    }
                
                // ✅ NEW: The Cart tab.
                CartView()
                    .tabItem {
                        Label("Cart", systemImage: "bag.fill")
                    }
                    // Show a badge with the number of items in the cart.
                    .badge(cartManager.totalQuantity > 0 ? "\(cartManager.totalQuantity)" : nil)
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
            }
        }
        // ✅ NEW: Provide the CartManager to all child views in the environment.
        .environmentObject(cartManager)
    }
}
#Preview {
    ContentView()
}
