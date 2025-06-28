import SwiftUI
import SafariServices

struct CartView: View {
    @EnvironmentObject var cartManager: CartManager
    @StateObject private var checkoutManager = StripeCheckoutManager()
    
    // This state controls showing the web checkout page.
    @State private var showCheckout = false
    @State private var showSuccessAlert = false

    var body: some View {
        NavigationStack {
            VStack {
                if cartManager.items.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Your cart is empty").font(.headline)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(cartManager.items) { cartItem in
                            HStack {
                                Text("\(cartItem.quantity)x").bold()
                                Text(cartItem.menuItem.id)
                                Spacer()
                                Text(cartItem.menuItem.price * Double(cartItem.quantity), format: .currency(code: "USD"))
                            }
                        }
                        .onDelete(perform: deleteItems)
                        
                        Section("Total") {
                            HStack {
                                Text("Total").bold()
                                Spacer()
                                Text(cartManager.subtotal, format: .currency(code: "USD")).bold()
                            }
                        }
                    }
                    
                    VStack {
                        if checkoutManager.isLoading {
                            ProgressView()
                                .padding()
                        } else {
                            Button("Proceed to Checkout") {
                                // This now calls an async function.
                                Task {
                                    await checkoutManager.createCheckoutSession(from: cartManager.items)
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                        
                        // ✅ This will now show a specific error message if something goes wrong.
                        if let errorMessage = checkoutManager.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("My Cart")
        }
        // This watches for the checkoutManager to get a valid URL.
        .onReceive(checkoutManager.$checkoutURL) { url in
            if url != nil {
                showCheckout = true // If we get a URL, trigger the sheet to present.
            }
        }
        // This watches for payment success
        .onReceive(checkoutManager.$paymentSuccess) { success in
            if success {
                showSuccessAlert = true
                // Clear the cart after successful payment
                cartManager.items.removeAll()
            }
        }
        // This sheet presents the secure Safari view with the Stripe Checkout page.
        .sheet(isPresented: $showCheckout) {
            if let url = checkoutManager.checkoutURL {
                SafariView(url: url, onDismiss: {
                    // Handle when the Safari view is dismissed
                    if checkoutManager.paymentSuccess {
                        checkoutManager.handlePaymentSuccess()
                    } else {
                        checkoutManager.handlePaymentCancellation()
                    }
                })
                .ignoresSafeArea()
            }
        }
        .alert("Payment Successful!", isPresented: $showSuccessAlert) {
            Button("OK") {
                showSuccessAlert = false
                checkoutManager.paymentSuccess = false
            }
        } message: {
            Text("Your order has been placed successfully. Thank you for your purchase!")
        }
    }
    
    func deleteItems(at offsets: IndexSet) {
        cartManager.items.remove(atOffsets: offsets)
    }
}

// This helper view is still needed to show the Safari window.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        let safariViewController = SFSafariViewController(url: url)
        safariViewController.delegate = context.coordinator
        return safariViewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariView
        
        init(_ parent: SafariView) {
            self.parent = parent
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.onDismiss()
        }
    }
}
