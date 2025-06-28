import SwiftUI

// The main entry point for the menu.
struct OrderView: View {
    @StateObject private var menuVM = MenuViewModel()
    @EnvironmentObject var cartManager: CartManager // Access the shared cart.
    
    // State to manage which item detail card is being shown.
    @State private var selectedItem: MenuItem?

    var body: some View {
        NavigationStack {
            ZStack {
                // Beautiful gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.98, green: 0.98, blue: 1.0),
                        Color(red: 1.0, green: 0.98, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack {
                    if menuVM.isLoading {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(Color(red: 0.2, green: 0.6, blue: 0.9))
                            Text("Loading our delicious menu...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    } else if !menuVM.errorMessage.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            Text(menuVM.errorMessage)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(menuVM.menuCategories) { category in
                                    NavigationLink(destination: CategoryDetailView(category: category)) {
                                        CategoryRow(category: category)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }
                    }
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.large)
        }
        .environmentObject(menuVM) // Pass the menu data down the hierarchy
    }
}

// A beautiful view for a row in the main category list.
struct CategoryRow: View {
    let category: MenuCategory

    var body: some View {
        HStack(spacing: 20) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.6, blue: 0.9),
                                Color(red: 0.3, green: 0.7, blue: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
                
                Image(systemName: categoryIcon(for: category.id))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(category.id)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Explore our \(category.id.lowercased()) selection")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        )
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case let c where c.contains("appetizer"): return "leaf.fill"
        case let c where c.contains("main"): return "fork.knife"
        case let c where c.contains("dessert"): return "birthday.cake.fill"
        case let c where c.contains("drink"): return "cup.and.saucer.fill"
        case let c where c.contains("soup"): return "drop.fill"
        case let c where c.contains("salad"): return "leaf.circle.fill"
        default: return "circle.fill"
        }
    }
}

// A view that shows the contents of a selected category.
struct CategoryDetailView: View {
    let category: MenuCategory
    @State private var selectedItem: MenuItem?

    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.98, blue: 1.0),
                    Color(red: 1.0, green: 0.98, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 25) {
                    // Check if the category has sub-categories or direct items.
                    if let subCategories = category.subCategories {
                        // Display list of sub-categories
                        ForEach(subCategories) { subCategory in
                            NavigationLink(destination: MenuItemListView(title: subCategory.id, items: subCategory.items)) {
                                SubCategoryCard(subCategory: subCategory)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else if let items = category.items {
                        // Display direct items in a grid
                        MenuItemGridView(items: items, selectedItem: $selectedItem)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .navigationTitle(category.id)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedItem) { item in
            // When an item is selected, show the detail card as a sheet.
            ItemDetailView(item: item)
        }
    }
}

// Beautiful sub-category card
struct SubCategoryCard: View {
    let subCategory: MenuSubCategory
    
    var body: some View {
        HStack(spacing: 20) {
            // Sub-category Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.8, green: 0.4, blue: 0.2),
                                Color(red: 0.9, green: 0.5, blue: 0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: Color(red: 0.8, green: 0.4, blue: 0.2).opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(subCategory.id)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("\(subCategory.items.count) items available")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        )
    }
}

// A view for showing items in a sub-category.
struct MenuItemListView: View {
    let title: String
    let items: [MenuItem]
    @State private var selectedItem: MenuItem?

    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.98, blue: 1.0),
                    Color(red: 1.0, green: 0.98, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                MenuItemGridView(items: items, selectedItem: $selectedItem)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item)
        }
    }
}

// A beautiful grid for displaying menu items.
struct MenuItemGridView: View {
    let items: [MenuItem]
    @Binding var selectedItem: MenuItem?
    
    // Defines a flexible grid layout.
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(items) { item in
                if item.isAvailable {
                    Button(action: { selectedItem = item }) {
                        MenuItemCard(item: item)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// Beautiful menu item card
struct MenuItemCard: View {
    let item: MenuItem
    
    var body: some View {
        VStack(spacing: 0) {
            // Image with overlay
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: item.imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                    }
                }
                .frame(height: 140)
                .clipped()
                
                // Price tag
                Text(String(format: "$%.2f", item.price))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.8, blue: 0.4),
                                        Color(red: 0.3, green: 0.9, blue: 0.5)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                    .padding(10)
            }
            
            // Content
            VStack(spacing: 8) {
                Text(item.id)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 15)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.ultraThinMaterial, lineWidth: 1)
        )
    }
}

// The beautiful pop-up card for an individual menu item.
struct ItemDetailView: View {
    let item: MenuItem
    @EnvironmentObject var cartManager: CartManager
    @Environment(\.dismiss) var dismiss // To close the sheet

    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Image section
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: item.imageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Color.gray.opacity(0.2)
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(height: 300)
                    .clipped()
                    
                    // Close button
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Circle().fill(.black.opacity(0.3)))
                    }
                    .padding(15)
                }

                // Content section
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.id)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                        }
                    }
                    
                    Spacer()
                    
                    // Price and Add to Cart
                    VStack(spacing: 20) {
                        HStack {
                            Text("Price")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", item.price))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                        }
                        
                        Button(action: {
                            cartManager.addToCart(item: item)
                            dismiss() // Close the sheet after adding to cart.
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Add to Cart")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.2, green: 0.6, blue: 0.9),
                                                Color(red: 0.3, green: 0.7, blue: 1.0)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                        }
                    }
                }
                .padding(30)
            }
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 50)
        }
    }
}
