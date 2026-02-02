import SwiftUI
import Kingfisher

struct HalfAndHalfSelection {
    var firstFlavor: MenuItem?
    var secondFlavor: MenuItem?
    var cookingStyle: String = "Steamed"
    var quantity: Int = 1
    var fixedPrice: Double = 13.99 // Default price, will be updated from MenuViewModel
    
    var isValid: Bool {
        firstFlavor != nil && secondFlavor != nil && firstFlavor != secondFlavor
    }
    
    var totalPrice: Double {
        return fixedPrice * Double(quantity)
    }
}

struct HalfAndHalfView: View {
    let dumplingItems: [MenuItem]
    @ObservedObject var menuVM: MenuViewModel

    @Environment(\.dismiss) var dismiss
    @State private var selection = HalfAndHalfSelection()
    @State private var showSafariView = false

    
    private let cookingStyles = ["Boiled", "Steamed", "Pan-fried"]
    private let piecesPerOrder = 12
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Half & Half")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Choose 2 different dumpling flavors")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                        
                        // First Flavor Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("First Flavor")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(dumplingItems) { item in
                                    FlavorSelectionCard(
                                        item: item,
                                        isSelected: selection.firstFlavor?.id == item.id,
                                        isDisabled: selection.secondFlavor?.id == item.id
                                    ) {
                                        selection.firstFlavor = item
                                    }
                                }
                            }
                        }
                        
                        // Second Flavor Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Second Flavor")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(dumplingItems) { item in
                                    FlavorSelectionCard(
                                        item: item,
                                        isSelected: selection.secondFlavor?.id == item.id,
                                        isDisabled: selection.firstFlavor?.id == item.id
                                    ) {
                                        selection.secondFlavor = item
                                    }
                                }
                            }
                        }
                        
                        // Cooking Style Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cooking Style")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Picker("Cooking Style", selection: $selection.cookingStyle) {
                                ForEach(cookingStyles, id: \.self) { style in
                                    Text(style).tag(style)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        
                        // Quantity Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quantity")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            HStack {
                                Stepper(value: $selection.quantity, in: 1...10) {
                                    Text("\(selection.quantity)")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .frame(width: 40)
                                }
                                .labelsHidden()
                                
                                Spacer()
                                
                                Text("\(selection.quantity) × \(piecesPerOrder)pc = \(selection.quantity * piecesPerOrder)pc")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        
                        // Price Display
                        if selection.isValid {
                            VStack(spacing: 8) {
                                Text("Total Price")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Text(String(format: "$%.2f", selection.totalPrice))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                            }
                            .padding(.vertical, 16)
                        }
                        
                        // Order Online Button
                        Button(action: {
                            showSafariView = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Order Online")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red)
                                    .shadow(color: Color.red.opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Half & Half")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                selection.fixedPrice = menuVM.halfAndHalfPrice
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
}

struct FlavorSelectionCard: View {
    let item: MenuItem
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Image
                ZStack {
                    if let imageURL = item.resolvedImageURL {
                        KFImage(imageURL)
                            .resizable()
                            .placeholder { ProgressView() }
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray)
                            )
                            .frame(height: 80)
                    }
                    
                    // Selection indicator
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 30, y: -30)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Name
                Text(item.id)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDisabled ? .secondary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected ? Color.blue.opacity(0.1) :
                        isDisabled ? Color(.systemGray6) :
                        Color(.systemBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .disabled(isDisabled)
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HalfAndHalfView(dumplingItems: [
        MenuItem(id: "Pork & Chive", description: "Classic pork and chive dumplings", price: 12.99, imageURL: "", isAvailable: true, paymentLinkID: "", isDumpling: true, toppingModifiersEnabled: false, milkSubModifiersEnabled: false, availableToppingIDs: [], availableMilkSubIDs: []),
        MenuItem(id: "Beef & Onion", description: "Savory beef and onion dumplings", price: 13.99, imageURL: "", isAvailable: true, paymentLinkID: "", isDumpling: true, toppingModifiersEnabled: false, milkSubModifiersEnabled: false, availableToppingIDs: [], availableMilkSubIDs: []),
        MenuItem(id: "Shrimp & Pork", description: "Delicious shrimp and pork dumplings", price: 14.99, imageURL: "", isAvailable: true, paymentLinkID: "", isDumpling: true, toppingModifiersEnabled: false, milkSubModifiersEnabled: false, availableToppingIDs: [], availableMilkSubIDs: []),
        MenuItem(id: "Vegetable", description: "Fresh vegetable dumplings", price: 11.99, imageURL: "", isAvailable: true, paymentLinkID: "", isDumpling: true, toppingModifiersEnabled: false, milkSubModifiersEnabled: false, availableToppingIDs: [], availableMilkSubIDs: [])
    ], menuVM: MenuViewModel())
} 