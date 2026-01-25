import SwiftUI

struct MenuItemListView: View {
    let title: String
    let items: [MenuItem]
    let categoryId: String
    @State private var selectedItem: MenuItem?
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var menuVM: MenuViewModel
    @Binding var showAdminTools: Bool


    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    MenuItemGridView(items: items, selectedItem: $selectedItem, menuVM: menuVM, showAdminTools: showAdminTools, categoryId: categoryId)
                    
                    // Bottom spacing for the global Order Online pill (matches DrinksListView)
                    Spacer()
                        .frame(height: 110)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, menuVM: menuVM)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.black)
        }
    }
} 