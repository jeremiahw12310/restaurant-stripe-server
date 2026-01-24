import SwiftUI

struct CategoryDetailView: View {
    let category: MenuCategory
    @State private var selectedItem: MenuItem?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var menuVM: MenuViewModel
    @Binding var showAdminTools: Bool
    let isViewOnly: Bool
    @State private var showOrganizeItems = false
    @State private var showHalfAndHalf = false
    @State private var showOrderWebView = false
    
    init(category: MenuCategory, menuVM: MenuViewModel, showAdminTools: Binding<Bool>, isViewOnly: Bool = false) {
        self.category = category
        self.menuVM = menuVM
        self._showAdminTools = showAdminTools
        self.isViewOnly = isViewOnly
    }
    
    /// Disable item selection if explicitly set to view-only OR if this is a toppings category
    private var shouldDisableItemSelection: Bool {
        let isToppings = isViewOnly || category.isToppingCategory || category.id.lowercased().contains("topping")
        print("🔒 CategoryDetailView - category: \(category.id), isViewOnly: \(isViewOnly), isToppingCategory: \(category.isToppingCategory), shouldDisable: \(isToppings)")
        return isToppings
    }

    var body: some View {
        let _ = print("📂 CategoryDetailView BODY - category: \(category.id), isDrinks: \(category.isDrinks), isToppingCategory: \(category.isToppingCategory), shouldDisable: \(shouldDisableItemSelection)")
        ZStack {
            Color.black.ignoresSafeArea()
            // Dumpling rain only for Dumplings category (hidden while loading)
            if category.id.lowercased() == "dumplings" && !isLoadingCategory {
                DumplingRainView()
            }
            
            // Boba rain for Milk Tea category (hidden while loading)
            if category.id.lowercased() == "milk tea" && !isLoadingCategory {
                BobaRainView()
            }
            
            // Special handling for Half and Half Dumplings category
            if category.id.lowercased() == "half and half dumplings" {
                VStack(spacing: 20) {
                    Text("Choose Two Flavors")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.top, 40)
                    
                    Text("Select two different dumpling flavors for your 12-piece order")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    Button(action: {
                        showHalfAndHalf = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.grid.2x2.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Start Selection")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.2, green: 0.8, blue: 0.4),
                                            Color(red: 0.3, green: 0.9, blue: 0.5)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.3), radius: 10, x: 0, y: 5)
                        )
                    }
                    
                    Spacer()
                }
            } else if category.isDrinks {
                // Special drinks list view - no images, just list with prices
                if let items = category.items {
                    let displayItems = (menuVM.orderedItemIdsByCategory[category.id]?.isEmpty == false) ? menuVM.orderedItems(for: category) : items
                    DrinksListView(
                        category: category,
                        items: displayItems,
                        selectedItem: $selectedItem,
                        menuVM: menuVM,
                        showAdminTools: showAdminTools,
                        disableItemSelection: shouldDisableItemSelection
                    )
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        sectionHeader
                        if let subCategories = category.subCategories {
                            ForEach(subCategories) { subCategory in
                                NavigationLink(destination: MenuItemListView(title: subCategory.id, items: subCategory.items, categoryId: category.id, menuVM: menuVM, showAdminTools: $showAdminTools)) {
                                    SubCategoryCard(subCategory: subCategory)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } else if let items = category.items {
                            if showAdminTools {
                                VStack(spacing: 10) {
                                    Button("Organize Items") {
                                        showOrganizeItems = true
                                    }
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16, weight: .bold))
                                    
                                    Button("Debug Image URLs") {
                                        menuVM.debugAllImageURLs()
                                    }
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14, weight: .medium))
                                    
                                    Button("Debug Drink Options") {
                                        menuVM.debugDrinkOptions()
                                    }
                                    .foregroundColor(.purple)
                                    .font(.system(size: 14, weight: .medium))
                                    
                                    Button("Create Default Drink Flavors") {
                                        menuVM.createDefaultDrinkFlavors()
                                    }
                                    .foregroundColor(.green)
                                    .font(.system(size: 14, weight: .medium))
                                }
                                .padding(.bottom, 10)
                            }
                            
                            // Unified grid: show all items without Half & Half insertion
                            let displayItems = (menuVM.orderedItemIdsByCategory[category.id]?.isEmpty == false) ? menuVM.orderedItems(for: category) : (category.items ?? [])
                            MenuItemGridView(items: displayItems, selectedItem: $selectedItem, menuVM: menuVM, showAdminTools: showAdminTools, categoryId: category.id, disableItemSelection: shouldDisableItemSelection)
                        }

                        // Bottom spacing so the last row can scroll above the floating Order Online pill
                        Spacer()
                            .frame(height: 110)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 0)
                }
                .refreshable {
                    print("🔄 Pull-to-refresh triggered for category: \(category.id)")
                    menuVM.refreshMenu()
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .fullScreenCover(item: $selectedItem) { item in
            ItemDetailView(item: item, menuVM: menuVM)
        }
        .sheet(isPresented: $showOrganizeItems) {
            OrganizeItemsSheet(menuVM: menuVM, category: category, isPresented: $showOrganizeItems)
        }
        .sheet(isPresented: $showHalfAndHalf) {
            HalfAndHalfView(dumplingItems: getAllDumplingItems(), menuVM: menuVM)
        }
        // Bottom-floating Order Online pill (match MenuView implementation)
        .overlay(alignment: .bottom) {
            if !isLoadingCategory {
                Button(action: { showOrderWebView = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("ORDER ONLINE")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(0.6)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.red,
                                        Color.red.opacity(0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear {
            // Items already loaded via fetchMenu() listeners - no refresh needed
            // This prevents the "Gathering your..." loading screen from showing
            // Reload cached images when view appears (in case they were cleared)
            if !menuVM.menuCategories.isEmpty {
                menuVM.reloadCachedImages()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Reload cached images when app becomes active (after being in background)
            if newPhase == .active && oldPhase != .active && !menuVM.menuCategories.isEmpty {
                menuVM.reloadCachedImages()
            }
        }
        // Loading overlay (no animation)
        .overlay(
            Group {
                if isLoadingCategory {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 14) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 90)
                                .opacity(0.95)
                            Text("Gathering your \(category.id)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .transition(.identity)
                    .zIndex(10)
                }
            }
        )
        .sheet(isPresented: $showOrderWebView) {
            if let url = URL(string: "https://dumplinghousetn.kwickmenu.com/") {
                SimplifiedSafariView(
                    url: url,
                    onDismiss: {
                        showOrderWebView = false
                    }
                )
            }
        }
    }
    
    // Helper method to get all dumpling items from all categories
    private func getAllDumplingItems() -> [MenuItem] {
        var allDumplingItems: [MenuItem] = []
        
        for category in menuVM.menuCategories {
            if let items = category.items {
                for item in items {
                    if item.isDumpling {
                        allDumplingItems.append(item)
                    }
                }
            }
        }
        
        return allDumplingItems
    }
    
    private var sectionHeader: some View {
        HStack {
            Spacer()
            Text(category.id)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.top, 0)
    }

    private var isLoadingCategory: Bool {
        menuVM.loadingCategories.contains(category.id)
    }
}

struct CategoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryDetailView(
            category: MenuCategory(id: "Desserts", items: [], subCategories: nil),
            menuVM: MenuViewModel(),
            showAdminTools: .constant(false),
            isViewOnly: false
        )
    }
} 