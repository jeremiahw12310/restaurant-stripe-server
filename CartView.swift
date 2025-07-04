import SwiftUI
import SafariServices
import Restaurant_Demo // If needed for TipSelectionView and SafariView
// Add this import if TipSelectionView is in a separate file
// import TipSelectionView

struct CartView: View {
    @EnvironmentObject var cartManager: CartManager
    @Environment(\.colorScheme) var colorScheme
    
    // This state controls showing the web checkout page.
    @State private var showSuccessAlert = false
    @State private var showTipSelection = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Adaptive background that works in both light and dark mode
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                VStack {
                    if cartManager.items.isEmpty {
                        emptyCartView
                    } else {
                        cartContentView
                    }
                }
            }
            .navigationTitle("Cart")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        cartManager.clearCart()
                    }
                    .foregroundColor(.red)
                    .disabled(cartManager.items.isEmpty)
                    .opacity(cartManager.items.isEmpty ? 0 : 1)
                }
            }
        }
        .sheet(isPresented: $showTipSelection) {
            TipSelectionView()
                .environmentObject(cartManager)
        }
        .alert("Payment Successful!", isPresented: $showSuccessAlert) {
            Button("OK") {
                // Handle successful payment
            }
        } message: {
            Text("Thank you for your order! We'll notify you when it's ready.")
        }
    }
    
    // MARK: - Subviews
    
    private var emptyCartView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 16) {
                Text("Your Cart is Empty")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Add some delicious items to get started")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    private var cartContentView: some View {
        VStack {
            // Cart items list
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(cartManager.items) { item in
                        CartItemCard(item: item, cartManager: cartManager)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            
            // Beautiful order summary card
            orderSummaryView
        }
    }
    
    private var orderSummaryView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                HStack {
                    Text("Subtotal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("$\(cartManager.subtotal, specifier: "%.2f")")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text("Tax")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("$\(cartManager.subtotal * 0.09, specifier: "%.2f")")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Divider()
                    .background(Color(.separator))
                
                HStack {
                    Text("Total")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("$\(cartManager.subtotal * 1.09, specifier: "%.2f")")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.1), radius: 15, x: 0, y: 8)
            )
            
            // Beautiful checkout button
            Button("Proceed to Checkout") {
                showTipSelection = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(cartManager.items.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .background(
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .ignoresSafeArea()
        )
    }
}

// Beautiful cart item card
struct CartItemCard: View {
    let item: CartItem
    let cartManager: CartManager
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Item image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange,
                            Color.orange.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                )
                .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.1), radius: 8, x: 0, y: 4)
            
            // Item details
            VStack(alignment: .leading, spacing: 8) {
                Text(item.menuItem.id)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("$\(item.menuItem.price, specifier: "%.2f")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                
                // Quantity controls
                HStack(spacing: 12) {
                    Button(action: {
                        if item.quantity > 1 {
                            cartManager.updateQuantity(for: item, quantity: item.quantity - 1)
                        } else {
                            cartManager.removeFromCart(item)
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text("\(item.quantity)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(minWidth: 30)
                    
                    Button(action: {
                        cartManager.updateQuantity(for: item, quantity: item.quantity + 1)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Text("$\(item.menuItem.price * Double(item.quantity), specifier: "%.2f")")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 10, x: 0, y: 5)
        )
    }
}
