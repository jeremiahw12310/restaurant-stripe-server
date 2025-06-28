import SwiftUI

// The main entry point for the menu.
struct OrderView: View {
    @StateObject private var menuVM = MenuViewModel()
    @EnvironmentObject var cartManager: CartManager // Access the shared cart.
    
    // State to manage which item detail card is being shown.
    @State private var selectedItem: MenuItem?

    var body: some View {
        NavigationStack {
            VStack {
                if menuVM.isLoading {
                    ProgressView("Loading Menu...")
                } else if !menuVM.errorMessage.isEmpty {
                    Text(menuVM.errorMessage)
                } else {
                    List(menuVM.menuCategories) { category in
                        // Each category is a navigation link to its list of items.
                        NavigationLink(destination: CategoryDetailView(category: category)) {
                           CategoryRow(category: category)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Order")
        }
        .environmentObject(menuVM) // Pass the menu data down the hierarchy
    }
}

// A view for a row in the main category list.
struct CategoryRow: View {
    let category: MenuCategory

    var body: some View {
        Text(category.id)
            .font(.headline)
            .padding(.vertical, 8)
    }
}


// A view that shows the contents of a selected category.
struct CategoryDetailView: View {
    let category: MenuCategory
    @State private var selectedItem: MenuItem?

    var body: some View {
        ScrollView {
            // Check if the category has sub-categories or direct items.
            if let subCategories = category.subCategories {
                // Display list of sub-categories
                ForEach(subCategories) { subCategory in
                    NavigationLink(destination: MenuItemListView(title: subCategory.id, items: subCategory.items)) {
                        Text(subCategory.id)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
            } else if let items = category.items {
                // Display direct items in a grid
                MenuItemGridView(items: items, selectedItem: $selectedItem)
            }
        }
        .navigationTitle(category.id)
        .sheet(item: $selectedItem) { item in
            // When an item is selected, show the detail card as a sheet.
            ItemDetailView(item: item)
        }
    }
}

// A view for showing items in a sub-category.
struct MenuItemListView: View {
    let title: String
    let items: [MenuItem]
    @State private var selectedItem: MenuItem?

    var body: some View {
        ScrollView {
            MenuItemGridView(items: items, selectedItem: $selectedItem)
        }
        .navigationTitle(title)
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item)
        }
    }
}

// A reusable grid for displaying menu items.
struct MenuItemGridView: View {
    let items: [MenuItem]
    @Binding var selectedItem: MenuItem?
    
    // Defines a flexible grid layout.
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 15) {
            ForEach(items) { item in
                if item.isAvailable {
                    Button(action: { selectedItem = item }) {
                        VStack {
                            AsyncImage(url: URL(string: item.imageURL)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.gray.opacity(0.3) }
                            .frame(height: 120)
                            .clipped()
                            
                            Text(item.id)
                                .font(.caption).bold()
                                .foregroundColor(.primary)
                                .padding(.horizontal, 5)
                            
                            Text(String(format: "$%.2f", item.price))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .shadow(radius: 2)
                    }
                }
            }
        }
        .padding()
    }
}

// The pop-up card for an individual menu item.
struct ItemDetailView: View {
    let item: MenuItem
    @EnvironmentObject var cartManager: CartManager
    @Environment(\.dismiss) var dismiss // To close the sheet

    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: URL(string: item.imageURL)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.gray.opacity(0.3) }
            .frame(height: 300)
            .clipped()

            VStack(alignment: .leading, spacing: 16) {
                Text(item.id)
                    .font(.largeTitle).bold()
                
                Text(item.description)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack {
                    Text("Price")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "$%.2f", item.price))
                        .font(.title2).bold()
                        .foregroundColor(.green)
                }
                
                Button(action: {
                    cartManager.addToCart(item: item)
                    dismiss() // Close the sheet after adding to cart.
                }) {
                    Label("Add to Cart", systemImage: "cart.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .padding(30)
        }
    }
}
