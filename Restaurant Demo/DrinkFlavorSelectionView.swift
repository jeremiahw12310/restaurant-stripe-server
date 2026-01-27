import SwiftUI

struct DrinkFlavorSelectionView: View {
    @ObservedObject var menuVM: MenuViewModel

    @Environment(\.dismiss) private var dismiss
    
    let isLemonade: Bool
    @State private var selectedFlavor: DrinkFlavor?
    @State private var selectedToppings: Set<String> = []
    @State private var showSafariView = false

    
    private var availableFlavors: [DrinkFlavor] {
        menuVM.drinkFlavors.filter { $0.isLemonade == isLemonade && $0.isAvailable }
    }
    
    private var availableToppings: [DrinkOption] {
        // Use global drink options (toppings only, not milk subs) for lemonades and sodas
        // Filter by drink toppings that are available for this category
        let globalToppings = menuVM.drinkOptions.filter { !$0.isMilkSub && $0.isAvailable }
        let availableToppingIDs = Set(menuVM.drinkToppings.filter { $0.isAvailable }.map { $0.id })
        
        // Only show global toppings that have corresponding drink toppings enabled
        return globalToppings.filter { topping in
            availableToppingIDs.contains(topping.id)
        }
    }
    
    private var totalPrice: Double {
        var price = 4.99 // Base price for drinks
        for toppingID in selectedToppings {
            if let topping = availableToppings.first(where: { $0.id == toppingID }) {
                price += topping.price
            }
        }
        return price
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Choose Your \(isLemonade ? "Lemonade" : "Soda") Flavor")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Select your favorite flavor and customize with toppings")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Flavor Selection
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Flavors")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 15) {
                            ForEach(availableFlavors) { flavor in
                                Button(action: {
                                    selectedFlavor = flavor
                                }) {
                                    VStack(spacing: 12) {
                                        // Debug logging
                                        let _ = DebugLogger.debug("🔍 Debug: Flavor '\(flavor.name)' - icon: '\(flavor.icon)' - resolvedURL: \(flavor.resolvedIconURL?.absoluteString ?? "nil")", category: "Menu")
                                        
                                        if !flavor.icon.isEmpty {
                                            if let url = flavor.resolvedIconURL {
                                                AsyncImage(url: url) { image in
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(width: 40, height: 40)
                                                } placeholder: {
                                                    Image(systemName: isLemonade ? "drop.fill" : "bubble.left.and.bubble.right.fill")
                                                        .font(.system(size: 30, weight: .semibold))
                                                        .foregroundColor(isLemonade ? .yellow : .blue)
                                                }
                                            } else {
                                                // Emoji
                                                Text(flavor.icon)
                                                    .font(.system(size: 40))
                                            }
                                        } else {
                                            Image(systemName: isLemonade ? "drop.fill" : "bubble.left.and.bubble.right.fill")
                                                .font(.system(size: 30, weight: .semibold))
                                                .foregroundColor(isLemonade ? .yellow : .blue)
                                        }
                                        
                                        Text(flavor.name)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(height: 120)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(selectedFlavor?.id == flavor.id ? (isLemonade ? Color.yellow.opacity(0.2) : Color.blue.opacity(0.2)) : Color(.systemGray6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(selectedFlavor?.id == flavor.id ? (isLemonade ? Color.yellow : Color.blue) : Color.clear, lineWidth: 2)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Toppings Selection
                    if !availableToppings.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Toppings")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(availableToppings) { topping in
                                    Button(action: {
                                        if selectedToppings.contains(topping.id) {
                                            selectedToppings.remove(topping.id)
                                        } else {
                                            selectedToppings.insert(topping.id)
                                        }
                                    }) {
                                        HStack {
                                            Text(topping.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Text("+$\(String(format: "%.2f", topping.price))")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                            
                                            if selectedToppings.contains(topping.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(isLemonade ? .yellow : .blue)
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedToppings.contains(topping.id) ? (isLemonade ? Color.yellow.opacity(0.1) : Color.blue.opacity(0.1)) : Color(.systemGray6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(selectedToppings.contains(topping.id) ? (isLemonade ? Color.yellow : Color.blue) : Color.clear, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Order Online Button
                    VStack(spacing: 15) {
                        HStack {
                            Text("Price:")
                                .font(.system(size: 18, weight: .bold))
                            Spacer()
                            Text("$\(String(format: "%.2f", totalPrice))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 20)
                        
                        Button(action: {
                            showSafariView = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.system(size: 20, weight: .semibold))
                                Text("Order Online")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 32)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red)
                                    .shadow(color: Color.red.opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("\(isLemonade ? "Lemonade" : "Soda") Flavors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }

        .onAppear {
            menuVM.fetchDrinkFlavors()
        }
        .sheet(isPresented: $showSafariView) {
            if let url = URL(string: "https://dumplinghousetn.kwickmenu.com/") {
                SimplifiedSafariView(
                    url: url,
                    onDismiss: { showSafariView = false }
                )
            }
        }
    }
    

} 