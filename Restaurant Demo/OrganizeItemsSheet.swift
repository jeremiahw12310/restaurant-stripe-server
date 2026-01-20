import SwiftUI

struct OrganizeItemsSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let category: MenuCategory
    @Binding var isPresented: Bool
    @State private var itemIds: [String] = []
    @Environment(\.dismiss) private var dismiss
    @State private var showManageDrinkOptions = false
    @State private var showManageDrinkFlavors = false
    @State private var showManageDrinkToppings = false

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(itemIds, id: \.self) { id in
                        if let item = category.items?.first(where: { $0.id == id }) {
                            Text(item.id)
                        }
                    }
                    .onMove(perform: move)
                }
                .navigationTitle("Organize Items")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { isPresented = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Save") {
                            var newItemsByCategory = menuVM.orderedItemIdsByCategory
                            newItemsByCategory[category.id] = itemIds
                            menuVM.updateMenuOrder(categories: menuVM.orderedCategoryIds, itemsByCategory: newItemsByCategory) { _ in
                                menuVM.orderedItemIdsByCategory = newItemsByCategory
                                isPresented = false
                            }
                        }
                        .font(.headline)
                    }
                }
                .onAppear {
                    if let ids = menuVM.orderedItemIdsByCategory[category.id], !ids.isEmpty {
                        itemIds = ids
                    } else {
                        itemIds = category.items?.map { $0.id } ?? []
                    }
                }
                Button(action: { showManageDrinkOptions = true }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Manage Toppings & Milk Substitutions")
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showManageDrinkOptions) {
                    ManageDrinkOptionsSheet(menuVM: menuVM)
                }
                
                Button(action: { showManageDrinkFlavors = true }) {
                    HStack {
                        Image(systemName: "drop.fill")
                        Text("Manage Drink Flavors")
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showManageDrinkFlavors) {
                    ManageDrinkFlavorsSheet(menuVM: menuVM)
                }
                
                Button(action: { showManageDrinkToppings = true }) {
                    HStack {
                        Image(systemName: "circle.fill")
                        Text("Manage Drink Toppings")
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showManageDrinkToppings) {
                    ManageDrinkToppingsSheet(menuVM: menuVM)
                }
            }
        }
    }
    private func move(from source: IndexSet, to destination: Int) {
        itemIds.move(fromOffsets: source, toOffset: destination)
    }
} 