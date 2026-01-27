import SwiftUI

struct MenuItemGridView: View {
    let items: [MenuItem]
    @Binding var selectedItem: MenuItem?
    @ObservedObject var menuVM: MenuViewModel
    let showAdminTools: Bool
    let categoryId: String
    let disableItemSelection: Bool
    @State private var editingItem: MenuItem? = nil
    @State private var pressedItemId: String? = nil
    private let columns = [GridItem(.fixed(220)), GridItem(.fixed(220))]
    
    init(items: [MenuItem], selectedItem: Binding<MenuItem?>, menuVM: MenuViewModel, showAdminTools: Bool, categoryId: String, disableItemSelection: Bool = false) {
        self.items = items
        self._selectedItem = selectedItem
        self.menuVM = menuVM
        self.showAdminTools = showAdminTools
        self.categoryId = categoryId
        self.disableItemSelection = disableItemSelection
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                // DEBUG: Log all items and their availability status
                let _ = DebugLogger.debug("🔍 MenuItemGridView - Item: \(item.id), isAvailable: \(item.isAvailable), disableItemSelection: \(disableItemSelection)", category: "Menu")
                
                // PERMANENT FIX: Show all items regardless of availability
                ZStack(alignment: .topTrailing) {
                    if disableItemSelection {
                        // View-only mode: render card without button interaction
                        MenuItemCard(item: item, isPressed: false)
                            .environmentObject(menuVM)
                    } else {
                        // Normal mode: render card with button interaction
                        Button(action: {
                            DebugLogger.debug("🎯 Tapped item card: \(item.id)", category: "Menu")
                            
                            // Handle press animation
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                pressedItemId = item.id
                            }
                            
                            // Set selected item after a brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    pressedItemId = nil
                                }
                                DebugLogger.debug("🎯 Setting selectedItem to: \(item.id)", category: "Menu")
                                selectedItem = item
                            }
                        }) {
                            MenuItemCard(item: item, isPressed: pressedItemId == item.id)
                                .environmentObject(menuVM)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if showAdminTools {
                        Button(action: { editingItem = item }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                                .shadow(radius: 2)
                        }
                        .offset(x: -8, y: 8)
                    }
                    
                    // DEBUG: Show availability status on each item
                    if !item.isAvailable {
                        VStack {
                            HStack {
                                Spacer()
                                Text("HIDDEN")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            Spacer()
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                }
                .allowsHitTesting(!disableItemSelection)
            }
        }
        .padding(.horizontal, 10)
        .sheet(item: $editingItem) { item in
            EditItemSheet(menuVM: menuVM, categoryId: categoryId, item: item)
        }
        .onAppear {
            DebugLogger.debug("MenuItemGridView items: \(items.map { $0.id })", category: "Menu")
        }
    }
} 