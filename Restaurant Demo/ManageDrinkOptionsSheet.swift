import SwiftUI

struct ManageDrinkOptionsSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var editingOption: DrinkOption? = nil
    @State private var newName = ""
    @State private var newPrice = ""
    @State private var isMilkSub = false
    @State private var isAvailable = true
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(menuVM.drinkOptions) { option in
                    HStack {
                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                        
                        VStack(alignment: .leading) {
                            Text(option.name)
                                .font(.headline)
                            Text(option.isMilkSub ? "Milk Substitution" : "Topping")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "$%.2f", option.price))
                                .font(.caption)
                        }
                        Spacer()
                        Toggle("Available", isOn: Binding(
                            get: { option.isAvailable },
                            set: { newValue in
                                var updated = option
                                updated.isAvailable = newValue
                                menuVM.updateDrinkOption(updated)
                            }
                        ))
                        .labelsHidden()
                        Button(action: {
                            editingOption = option
                            newName = option.name
                            newPrice = String(option.price)
                            isMilkSub = option.isMilkSub
                            isAvailable = option.isAvailable
                        }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Button(action: {
                            menuVM.deleteDrinkOption(option)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .onMove(perform: moveOptions)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage Drink Options")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isAdding = true
                        newName = ""
                        newPrice = ""
                        isMilkSub = false
                        isAvailable = true
                    }) {
                        Label("Add Option", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                optionForm(isEditing: false)
            }
            .sheet(item: $editingOption) { _ in
                optionForm(isEditing: true)
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                menuVM.fetchDrinkOptions()
            }
        }
    }
    
    private func moveOptions(from source: IndexSet, to destination: Int) {
        var options = menuVM.drinkOptions
        options.move(fromOffsets: source, toOffset: destination)
        
        // Update the order in Firestore
        for (index, option) in options.enumerated() {
            var updatedOption = option
            updatedOption.order = index
            menuVM.updateDrinkOption(updatedOption)
        }
    }
    
    @ViewBuilder
    private func optionForm(isEditing: Bool) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newName)
                TextField("Price", text: $newPrice)
                    .keyboardType(.decimalPad)
                Toggle("Is Milk Substitution", isOn: $isMilkSub)
                Toggle("Available", isOn: $isAvailable)
            }
            .navigationTitle(isEditing ? "Edit Option" : "Add Option")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isEditing { editingOption = nil } else { isAdding = false }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Add") {
                        guard !newName.isEmpty, let price = Double(newPrice) else {
                            alertMessage = "Please enter a valid name and price."
                            showAlert = true
                            return
                        }
                        let id: String
                        if isEditing, let existingOption = editingOption {
                            id = existingOption.id
                        } else {
                            id = UUID().uuidString
                        }
                        let option = DrinkOption(id: id, name: newName, price: price, isMilkSub: isMilkSub, isAvailable: isAvailable)
                        if isEditing {
                            menuVM.updateDrinkOption(option)
                            editingOption = nil
                        } else {
                            menuVM.addDrinkOption(option)
                            isAdding = false
                        }
                    }
                }
            }
        }
    }
} 