import SwiftUI

struct ContentView: View {
    // ✅ NEW: Create a single instance of the CartManager to be shared across all tabs.
    @StateObject private var cartManager = CartManager()

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            OrderView()
                .tabItem {
                    Label("Order", systemImage: "menucard.fill")
                }
            
            // ✅ NEW: The Cart tab.
            CartView()
                .tabItem {
                    Label("Cart", systemImage: "cart.fill")
                }
                // Show a badge with the number of items in the cart.
                .badge(cartManager.totalQuantity > 0 ? "\(cartManager.totalQuantity)" : nil)
        }
        // ✅ NEW: Provide the CartManager to all child views in the environment.
        .environmentObject(cartManager)
    }
}
#Preview {
    ContentView()
}
