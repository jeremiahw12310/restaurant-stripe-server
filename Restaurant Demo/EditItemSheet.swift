import SwiftUI

struct EditItemSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let categoryId: String
    let item: MenuItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var itemName: String
    @State private var itemPrice: String
    @State private var itemDescription: String
    @State private var itemImageURL: String
    @State private var isDumpling: Bool
    @State private var toppingModifiersEnabled: Bool
    @State private var milkSubModifiersEnabled: Bool
    @State private var availableToppingIDs: [String]
    @State private var availableMilkSubIDs: [String]
    @State private var allergyTagIDs: [String]
    @State private var isShowingAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    @State private var showDeleteAlert = false
    
    init(menuVM: MenuViewModel, categoryId: String, item: MenuItem) {
        self.menuVM = menuVM
        self.categoryId = categoryId
        self.item = item
        self._itemName = State(initialValue: item.id)
        self._itemPrice = State(initialValue: String(format: "%.2f", item.price))
        self._itemDescription = State(initialValue: item.description)
        self._itemImageURL = State(initialValue: item.imageURL)
        self._isDumpling = State(initialValue: item.isDumpling)
        self._toppingModifiersEnabled = State(initialValue: item.toppingModifiersEnabled)
        self._milkSubModifiersEnabled = State(initialValue: item.milkSubModifiersEnabled)
        self._availableToppingIDs = State(initialValue: item.availableToppingIDs)
        self._availableMilkSubIDs = State(initialValue: item.availableMilkSubIDs)
        self._allergyTagIDs = State(initialValue: item.allergyTagIDs)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item Name", text: $itemName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Price", text: $itemPrice)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                    
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                    
                    TextField("Image URL (gs://...)", text: $itemImageURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Toggle("Is Dumpling Item", isOn: $isDumpling)
                        .font(.system(size: 16, weight: .medium))
                    
                    Toggle("Enable Topping Modifiers", isOn: $toppingModifiersEnabled)
                    if toppingModifiersEnabled {
                        VStack(alignment: .leading) {
                            Text("Toppings:").font(.headline)
                            ForEach(menuVM.drinkOptions.filter { !$0.isMilkSub && $0.isAvailable }) { option in
                                Toggle(option.name + String(format: " ($%.2f)", option.price), isOn: Binding(
                                    get: { availableToppingIDs.contains(option.id) },
                                    set: { enabled in
                                        if enabled {
                                            availableToppingIDs.append(option.id)
                                        } else {
                                            availableToppingIDs.removeAll { $0 == option.id }
                                        }
                                    }
                                ))
                            }
                        }
                    }
                    Toggle("Enable Milk Substitution Modifiers", isOn: $milkSubModifiersEnabled)
                    if milkSubModifiersEnabled {
                        VStack(alignment: .leading) {
                            Text("Milk Substitutions:").font(.headline)
                            ForEach(menuVM.drinkOptions.filter { $0.isMilkSub && $0.isAvailable }) { option in
                                Toggle(option.name + String(format: " ($%.2f)", option.price), isOn: Binding(
                                    get: { availableMilkSubIDs.contains(option.id) },
                                    set: { enabled in
                                        if enabled {
                                            availableMilkSubIDs.append(option.id)
                                        } else {
                                            availableMilkSubIDs.removeAll { $0 == option.id }
                                        }
                                    }
                                ))
                            }
                        }
                    }
                }

                Section("Allergy Info") {
                    if menuVM.allergyTags.isEmpty {
                        Text("No allergy tags yet. Add them in Menu Admin → Allergy Tags.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(menuVM.allergyTags) { tag in
                            Toggle(tag.title, isOn: Binding(
                                get: { allergyTagIDs.contains(tag.id) },
                                set: { enabled in
                                    if enabled {
                                        if !allergyTagIDs.contains(tag.id) { allergyTagIDs.append(tag.id) }
                                    } else {
                                        allergyTagIDs.removeAll { $0 == tag.id }
                                    }
                                }
                            ))
                        }
                    }
                }
                
                Section {
                    Button("Update \(categoryId.singularized())") {
                        updateItem()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                    )
                    .disabled(itemName.isEmpty || itemPrice.isEmpty || itemDescription.isEmpty)
                }
                
                Section {
                    Button("Duplicate Item") {
                        duplicateItem()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green)
                    )
                }
                
                Section {
                    Button("Delete \(categoryId.singularized())") {
                        showDeleteAlert = true
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red)
                    )
                }
            }
            .navigationTitle("Edit \(categoryId.singularized())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                menuVM.fetchAllergyTags()
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $isShowingAlert) {
                Button("OK") {
                    if isSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .alert("Delete \(categoryId.singularized())", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteItem()
                }
            } message: {
                Text("Are you sure you want to delete '\(itemName)'? This action cannot be undone.")
            }
        }
    }
    
    private func updateItem() {
        guard let price = Double(itemPrice) else {
            alertMessage = "Please enter a valid price"
            isSuccess = false
            isShowingAlert = true
            return
        }
        
        let updatedItem = MenuItem(
            id: itemName,
            description: itemDescription,
            price: price,
            imageURL: itemImageURL.isEmpty ? "gs://dumplinghouseapp.firebasestorage.app/default.png" : itemImageURL,
            isAvailable: true,
            paymentLinkID: "",
            isDumpling: isDumpling,
            toppingModifiersEnabled: toppingModifiersEnabled,
            milkSubModifiersEnabled: milkSubModifiersEnabled,
            availableToppingIDs: availableToppingIDs,
            availableMilkSubIDs: availableMilkSubIDs,
            allergyTagIDs: allergyTagIDs
        )
        
        menuVM.updateItemInCategory(categoryId: categoryId, oldItem: item, newItem: updatedItem) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "\(categoryId.singularized()) updated successfully!"
                    isSuccess = true
                    self.menuVM.refreshMenu()
                } else {
                    alertMessage = error ?? "Failed to update \(categoryId.singularized())"
                    isSuccess = false
                }
                isShowingAlert = true
            }
        }
    }
    
    private func deleteItem() {
        menuVM.deleteItemFromCategory(categoryId: categoryId, item: item) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "\(categoryId.singularized()) deleted successfully!"
                    isSuccess = true
                    self.menuVM.refreshMenu()
                } else {
                    alertMessage = error ?? "Failed to delete \(categoryId.singularized())"
                    isSuccess = false
                }
                isShowingAlert = true
            }
        }
    }

    private func duplicateItem() {
        menuVM.duplicateItemInCategory(categoryId: categoryId, item: item) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Item duplicated successfully!"
                    isSuccess = true
                    self.menuVM.refreshMenu()
                } else {
                    alertMessage = error ?? "Failed to duplicate item."
                    isSuccess = false
                }
                isShowingAlert = true
            }
        }
    }
}

extension String {
    func singularized() -> String {
        if self.hasSuffix("ies") {
            return String(self.dropLast(3)) + "y"
        } else if self.hasSuffix("s") && !self.hasSuffix("ss") {
            return String(self.dropLast())
        } else {
            return self
        }
    }
} 