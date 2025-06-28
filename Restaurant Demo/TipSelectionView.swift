import SwiftUI

public struct TipSelectionView: View {
    @EnvironmentObject var cartManager: CartManager
    @StateObject private var checkoutManager = StripeCheckoutManager()
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTipPercentage: Double = 0.15 // 15% default
    @State private var customTipAmount: String = ""
    @State private var showCustomTipField = false
    @State private var showCheckout = false
    @State private var showSuccessAlert = false
    
    private let tipOptions: [(percentage: Double, label: String)] = [
        (0.10, "10%"),
        (0.15, "15%"),
        (0.18, "18%"),
        (0.20, "20%"),
        (0.25, "25%")
    ]
    
    private var subtotal: Double {
        cartManager.items.reduce(0) { $0 + ($1.menuItem.price * Double($1.quantity)) }
    }
    
    private var tipAmount: Double {
        if showCustomTipField && !customTipAmount.isEmpty {
            return Double(customTipAmount) ?? 0
        }
        return subtotal * selectedTipPercentage
    }
    
    private var total: Double {
        subtotal + tipAmount
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                gradientBackground
                ScrollView {
                    VStack(spacing: 30) {
                        headerSection
                        orderSummarySection
                        tipOptionsSection
                        if showCustomTipField { customTipSection }
                        noTipButton
                        Button(action: {
                            showCheckout = true
                        }) {
                            Text("Proceed to Payment")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 15)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color(red: 0.2, green: 0.6, blue: 0.9), Color(red: 0.3, green: 0.7, blue: 1.0)]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .disabled(cartManager.items.isEmpty)
                    }
                }
            }
        }
        .navigationTitle("Add Tip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
            }
        }
        .sheet(isPresented: $showCheckout, onDismiss: { showCheckout = false }) {
            if let url = checkoutManager.checkoutURL {
                SafariView(url: url)
            }
        }
        .onReceive(checkoutManager.$paymentSuccess) { success in
            if success {
                showSuccessAlert = true
                cartManager.clearCart()
            }
        }
        .alert("Payment Successful!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for your order! We'll notify you when it's ready.")
        }
        .onChange(of: showCheckout) { newValue in
            if newValue {
                // Create checkout session with tip included
                let lineItems = cartManager.items.map { item in
                    [
                        "price_data": [
                            "currency": "usd",
                            "product_data": [
                                "name": item.menuItem.id
                            ],
                            "unit_amount": Int(item.menuItem.price * 100)
                        ],
                        "quantity": item.quantity
                    ]
                }
                var itemsWithTip = lineItems
                if tipAmount > 0 {
                    itemsWithTip.append([
                        "price_data": [
                            "currency": "usd",
                            "product_data": [
                                "name": "Tip"
                            ],
                            "unit_amount": Int(tipAmount * 100)
                        ],
                        "quantity": 1
                    ])
                }
                Task {
                    await checkoutManager.createCheckoutSession(lineItems: itemsWithTip)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showCustomTipField)
        .animation(.easeInOut(duration: 0.2), value: selectedTipPercentage)
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 1.0, green: 0.98, blue: 0.95)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundColor(.pink)
                .shadow(color: .pink.opacity(0.3), radius: 10, x: 0, y: 5)
            Text("Add a Tip")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("Show your appreciation to our team")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    private var orderSummarySection: some View {
        VStack(spacing: 20) {
            Text("Order Summary")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            VStack(spacing: 12) {
                HStack {
                    Text("Subtotal")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text("$\(subtotal, specifier: "%.2f")")
                        .font(.system(size: 16, weight: .semibold))
                }
                HStack {
                    Text("Tip")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Text("$\(tipAmount, specifier: "%.2f")")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.pink)
                }
                Divider().background(.ultraThinMaterial)
                HStack {
                    Text("Total")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Text("$\(total, specifier: "%.2f")")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
    }
    
    private func tipOptionButton(for option: (percentage: Double, label: String)) -> some View {
        Button(action: {
            selectedTipPercentage = option.percentage
            showCustomTipField = false
            customTipAmount = ""
        }) {
            VStack(spacing: 8) {
                Text(option.label)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(selectedTipPercentage == option.percentage ? .white : .primary)
                Text(String(format: "$%.2f", subtotal * option.percentage))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedTipPercentage == option.percentage ? .white.opacity(0.9) : .secondary)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        selectedTipPercentage == option.percentage ?
                            AnyShapeStyle(LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.6, blue: 0.9),
                                    Color(red: 0.3, green: 0.7, blue: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )) :
                            AnyShapeStyle(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(selectedTipPercentage == option.percentage ? Color(red: 0.2, green: 0.6, blue: 0.9) : .clear, lineWidth: 2)
                    )
            )
            .shadow(color: selectedTipPercentage == option.percentage ? Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3) : .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var tipOptionsSection: some View {
        VStack(spacing: 16) {
            Text("Choose Tip Amount")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(tipOptions, id: \.percentage) { option in
                    tipOptionButton(for: option)
                }
                Button(action: {
                    showCustomTipField = true
                    selectedTipPercentage = 0
                }) {
                    VStack(spacing: 8) {
                        Text("Custom")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(showCustomTipField ? .white : .primary)
                        Text("Amount")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showCustomTipField ? .white.opacity(0.9) : .secondary)
                    }
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(
                                showCustomTipField
                                    ? AnyShapeStyle(LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.2, green: 0.6, blue: 0.9),
                                            Color(red: 0.3, green: 0.7, blue: 1.0)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    : AnyShapeStyle(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(showCustomTipField ? Color(red: 0.2, green: 0.6, blue: 0.9) : .clear, lineWidth: 2)
                            )
                    )
                    .shadow(color: showCustomTipField ? Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3) : .black.opacity(0.05), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var customTipSection: some View {
        VStack(spacing: 12) {
            Text("Enter Custom Amount")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            HStack {
                Text("$")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("0.00", text: $customTipAmount)
                    .font(.system(size: 18, weight: .medium))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.ultraThinMaterial, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var noTipButton: some View {
        Button(action: {
            selectedTipPercentage = 0
            showCustomTipField = false
            customTipAmount = ""
        }) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("No Tip")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(selectedTipPercentage == 0 && !showCustomTipField ? Color(red: 0.2, green: 0.6, blue: 0.9) : .secondary)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 10)
    }
} 