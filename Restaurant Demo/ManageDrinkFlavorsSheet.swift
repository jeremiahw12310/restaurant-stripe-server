import SwiftUI

struct ManageDrinkFlavorsSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var editingFlavor: DrinkFlavor? = nil
    @State private var newName = ""
    @State private var isLemonade = true
    @State private var isAvailable = true
    @State private var newIcon = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(menuVM.drinkFlavors) { flavor in
                    HStack {
                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                        
                        VStack(alignment: .leading) {
                            HStack {
                                if !flavor.icon.isEmpty {
                                    if let url = flavor.resolvedIconURL {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 24)
                                        } placeholder: {
                                            Image(systemName: "photo")
                                                .frame(width: 24, height: 24)
                                                .foregroundColor(.gray)
                                        }
                                    } else {
                                        // Emoji
                                        Text(flavor.icon)
                                            .font(.title2)
                                    }
                                } else {
                                    Image(systemName: flavor.isLemonade ? "drop.fill" : "bubble.left.and.bubble.right.fill")
                                        .foregroundColor(flavor.isLemonade ? .yellow : .blue)
                                }
                                Text(flavor.name)
                                    .font(.headline)
                            }
                            Text(flavor.isLemonade ? "Lemonade" : "Soda")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("Available", isOn: Binding(
                            get: { flavor.isAvailable },
                            set: { newValue in
                                var updated = flavor
                                updated.isAvailable = newValue
                                menuVM.updateDrinkFlavor(updated)
                            }
                        ))
                        .labelsHidden()
                        Button(action: {
                            editingFlavor = flavor
                            newName = flavor.name
                            isLemonade = flavor.isLemonade
                            isAvailable = flavor.isAvailable
                            newIcon = flavor.icon
                        }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Button(action: {
                            menuVM.deleteDrinkFlavor(flavor)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .onMove(perform: moveFlavors)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage Drink Flavors")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isAdding = true
                        newName = ""
                        isLemonade = true
                        isAvailable = true
                        newIcon = ""
                    }) {
                        Label("Add Flavor", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                flavorForm(isEditing: false)
            }
            .sheet(item: $editingFlavor) { _ in
                flavorForm(isEditing: true)
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                menuVM.fetchDrinkFlavors()
            }
        }
    }
    
    private func moveFlavors(from source: IndexSet, to destination: Int) {
        var flavors = menuVM.drinkFlavors
        flavors.move(fromOffsets: source, toOffset: destination)
        
        // Update the order in Firestore
        for (index, flavor) in flavors.enumerated() {
            var updatedFlavor = flavor
            updatedFlavor.order = index
            menuVM.updateDrinkFlavor(updatedFlavor)
        }
    }
    
    @ViewBuilder
    private func flavorForm(isEditing: Bool) -> some View {
        NavigationStack {
            Form {
                TextField("Flavor Name", text: $newName)
                
                Section("Icon") {
                    TextField("Emoji (e.g., 🍋) or PNG URL", text: $newIcon)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if !newIcon.isEmpty {
                        HStack {
                            Text("Preview:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let url = resolvedPreviewIconURL() {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 32, height: 32)
                                } placeholder: {
                                    Image(systemName: "photo")
                                        .frame(width: 32, height: 32)
                                        .foregroundColor(.gray)
                                }
                            } else {
                                // Emoji
                                Text(newIcon)
                                    .font(.title)
                            }
                        }
                    }
                }
                
                Toggle("Is Lemonade", isOn: $isLemonade)
                Toggle("Available", isOn: $isAvailable)
            }
            .navigationTitle(isEditing ? "Edit Flavor" : "Add Flavor")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isEditing { editingFlavor = nil } else { isAdding = false }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Add") {
                        guard !newName.isEmpty else {
                            alertMessage = "Please enter a valid flavor name."
                            showAlert = true
                            return
                        }
                        let id = isEditing ? editingFlavor!.id : UUID().uuidString
                        let flavor = DrinkFlavor(id: id, name: newName, isLemonade: isLemonade, isAvailable: isAvailable, icon: newIcon)
                        if isEditing {
                            menuVM.updateDrinkFlavor(flavor)
                            editingFlavor = nil
                        } else {
                            menuVM.addDrinkFlavor(flavor)
                            isAdding = false
                        }
                    }
                }
            }
        }
    }
    
    private func resolvedPreviewIconURL() -> URL? {
        if newIcon.hasPrefix("gs://") {
            let components = newIcon.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
                return URL(string: downloadURL)
            }
        } else if newIcon.hasPrefix("http") {
            return URL(string: newIcon)
        }
        return nil
    }
} 