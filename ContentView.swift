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