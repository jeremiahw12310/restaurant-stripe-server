import SwiftUI

struct OrganizeCategoriesSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Binding var isPresented: Bool
    @State private var categories: [String] = []
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Add a hardcoded list of all possible categories
    private let hardcodedCategories = [
        "Appetizers",
        "Soups",
        "Pizza",
        "Dumplings",
        "Fruit tea",
        "Milk tea",
        "Coffee",
        "Sauces",
        "Lemonades",
        "Coke products"
    ]

    var body: some View {
        NavigationStack {
            VStack {
                if categories.isEmpty {
                    ProgressView("Loading categories...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(categories, id: \.self) { categoryId in
                            HStack {
                                // Show all categories, even if not in Firestore yet
                                if let category = menuVM.menuCategories.first(where: { $0.id == categoryId }) {
                                    Text(category.id)
                                        .font(.system(size: 16, weight: .medium))
                                } else {
                                    Text(categoryId)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Show item count if category exists
                                if let category = menuVM.menuCategories.first(where: { $0.id == categoryId }) {
                                    Text("\(category.items?.count ?? 0) items")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove(perform: move)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Organize Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { 
                        isPresented = false 
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(action: saveOrder) {
                        if isSaving {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            }
                        } else {
                            Text("Save Order")
                                .font(.headline)
                        }
                    }
                    .disabled(isSaving || categories.isEmpty)
                }
            }
            .onAppear {
                loadCategories()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func loadCategories() {
        // Merge Firestore and hardcoded categories, remove duplicates, preserve order
        let firestoreCategories = menuVM.menuCategories.map { $0.id }
        var seen = Set<String>()
        let merged = (menuVM.orderedCategoryIds + firestoreCategories + hardcodedCategories).filter { seen.insert($0).inserted }
        categories = merged
    }

    private func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }
    
    private func saveOrder() {
        isSaving = true
        
        // Create itemsByCategory dictionary from current menu state
        var itemsByCategory: [String: [String]] = [:]
        for category in menuVM.menuCategories {
            let itemIds = category.items?.map { $0.id } ?? []
            itemsByCategory[category.id] = itemIds
        }
        
        // Add empty arrays for categories that don't exist yet
        for categoryId in categories {
            if itemsByCategory[categoryId] == nil {
                itemsByCategory[categoryId] = []
            }
        }
        
        menuVM.updateMenuOrder(categories: categories, itemsByCategory: itemsByCategory) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    isPresented = false
                } else {
                    errorMessage = "Failed to save category order. Please try again."
                    showError = true
                }
            }
        }
    }
} 