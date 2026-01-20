import SwiftUI

struct ManageDrinkToppingsSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddTopping = false
    @State private var newToppingName = ""
    @State private var newToppingPrice = ""
    @State private var editingTopping: DrinkTopping? = nil
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("This controls which global drink toppings are available for Lemonades and Sodas")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 10)
                
                Text("Global toppings: \(menuVM.drinkOptions.filter { !$0.isMilkSub }.count) available")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                List {
                    ForEach(menuVM.drinkToppings) { topping in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(topping.name)
                                    .font(.headline)
                                Text("$\(String(format: "%.2f", topping.price))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack {
                                Button(action: {
                                    var updated = topping
                                    updated.isAvailable.toggle()
                                    menuVM.updateDrinkTopping(updated)
                                }) {
                                    Image(systemName: topping.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(topping.isAvailable ? .green : .red)
                                }
                                
                                Button(action: {
                                    editingTopping = topping
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                
                                Button(action: {
                                    menuVM.deleteDrinkTopping(topping)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .onMove { from, to in
                        var toppings = menuVM.drinkToppings
                        toppings.move(fromOffsets: from, toOffset: to)
                        
                        // Update order for all items
                        for (index, topping) in toppings.enumerated() {
                            var updatedTopping = topping
                            updatedTopping.order = index
                            menuVM.updateDrinkTopping(updatedTopping)
                        }
                    }
                }
                
                Button("Sync with Global Toppings") {
                    menuVM.createDefaultDrinkToppings()
                }
                .foregroundColor(.green)
                .padding()
                
                Text("This will create drink toppings for all available global toppings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .navigationTitle("Manage Lemonade/Soda Toppings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showAddTopping = true
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddTopping) {
                AddDrinkToppingSheet(menuVM: menuVM, isPresented: $showAddTopping)
            }
            .sheet(item: $editingTopping) { topping in
                EditDrinkToppingSheet(menuVM: menuVM, topping: topping, isPresented: .constant(true))
            }
            .onAppear {
                menuVM.fetchDrinkToppings()
            }
        }
    }
}

struct AddDrinkToppingSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var price = ""
    @State private var isAvailable = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Lemonade/Soda Topping Details") {
                    TextField("Name", text: $name)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                    Toggle("Available for Lemonades/Sodas", isOn: $isAvailable)
                }
            }
            .navigationTitle("Add Topping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let priceValue = Double(price), !name.isEmpty {
                            let topping = DrinkTopping(
                                id: "drink_topping_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
                                name: name,
                                price: priceValue,
                                isAvailable: isAvailable
                            )
                            menuVM.addDrinkTopping(topping)
                            isPresented = false
                        }
                    }
                    .disabled(name.isEmpty || price.isEmpty)
                }
            }
        }
    }
}

struct EditDrinkToppingSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let topping: DrinkTopping
    @Binding var isPresented: Bool
    @State private var name: String
    @State private var price: String
    @State private var isAvailable: Bool
    
    init(menuVM: MenuViewModel, topping: DrinkTopping, isPresented: Binding<Bool>) {
        self.menuVM = menuVM
        self.topping = topping
        self._isPresented = isPresented
        self._name = State(initialValue: topping.name)
        self._price = State(initialValue: String(format: "%.2f", topping.price))
        self._isAvailable = State(initialValue: topping.isAvailable)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Lemonade/Soda Topping Details") {
                    TextField("Name", text: $name)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                    Toggle("Available for Lemonades/Sodas", isOn: $isAvailable)
                }
            }
            .navigationTitle("Edit Topping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let priceValue = Double(price), !name.isEmpty {
                            let updatedTopping = DrinkTopping(
                                id: topping.id,
                                name: name,
                                price: priceValue,
                                isAvailable: isAvailable,
                                order: topping.order
                            )
                            menuVM.updateDrinkTopping(updatedTopping)
                            isPresented = false
                        }
                    }
                    .disabled(name.isEmpty || price.isEmpty)
                }
            }
        }
    }
} 
