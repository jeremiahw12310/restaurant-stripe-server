import SwiftUI

struct DrinksListView: View {
    let category: MenuCategory
    let items: [MenuItem]
    @Binding var selectedItem: MenuItem?
    @ObservedObject var menuVM: MenuViewModel
    let showAdminTools: Bool
    let disableItemSelection: Bool
    @State private var pressedItemId: String? = nil
    
    init(category: MenuCategory, items: [MenuItem], selectedItem: Binding<MenuItem?>, menuVM: MenuViewModel, showAdminTools: Bool, disableItemSelection: Bool = false) {
        self.category = category
        self.items = items
        self._selectedItem = selectedItem
        self.menuVM = menuVM
        self.showAdminTools = showAdminTools
        self.disableItemSelection = disableItemSelection
    }
    
    var body: some View {
        let _ = DebugLogger.debug("🍹 DrinksListView - category: \(category.id), disableItemSelection: \(disableItemSelection)", category: "Menu")
        ScrollView {
            LazyVStack(spacing: 0) {
                // Admin tools if needed
                if showAdminTools {
                    VStack(spacing: 10) {
                        Button("Organize Items") {
                            // Placeholder for future organization feature
                        }
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .bold))
                    }
                    .padding(.vertical, 16)
                }
                
                // List of drinks - Performance: Use LazyVStack and stable IDs
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if disableItemSelection {
                        // View-only mode: render row without button interaction
                        DrinkListRow(item: item, isPressed: false)
                            .allowsHitTesting(false)
                    } else {
                        // Normal mode: render row with button interaction
                        Button(action: {
                            // Handle tap with animation
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                pressedItemId = item.id
                            }
                            
                            // Show item detail after brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    pressedItemId = nil
                                }
                                selectedItem = item
                            }
                        }) {
                            DrinkListRow(item: item, isPressed: pressedItemId == item.id)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Divider between items (except last item)
                    if index < items.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.15))
                            .padding(.horizontal, 24)
                    }
                }
                
                // Bottom spacing for the global Order Online pill (rendered by parent view)
                Spacer()
                    .frame(height: 110)
            }
            .padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    let sampleItems = [
        MenuItem(
            id: "Jasmine Milk Tea",
            description: "Refreshing jasmine milk tea",
            price: 6.50,
            imageURL: "",
            isAvailable: true,
            paymentLinkID: ""
        ),
        MenuItem(
            id: "Taro Milk Tea",
            description: "Classic taro milk tea",
            price: 6.50,
            imageURL: "",
            isAvailable: true,
            paymentLinkID: ""
        ),
        MenuItem(
            id: "Thai Milk Tea",
            description: "Traditional Thai milk tea",
            price: 6.50,
            imageURL: "",
            isAvailable: true,
            paymentLinkID: ""
        ),
        MenuItem(
            id: "Brown Sugar Boba",
            description: "Sweet brown sugar boba",
            price: 7.00,
            imageURL: "",
            isAvailable: true,
            paymentLinkID: ""
        )
    ]
    
    return DrinksListView(
        category: MenuCategory(id: "Milk Tea", items: sampleItems, subCategories: nil, isDrinks: true),
        items: sampleItems,
        selectedItem: .constant(nil),
        menuVM: MenuViewModel(),
        showAdminTools: false
    )
}

