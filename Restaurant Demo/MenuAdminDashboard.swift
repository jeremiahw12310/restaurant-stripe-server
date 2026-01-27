import SwiftUI
import FirebaseFirestore
import FirebaseStorage // Added for image upload

struct MenuAdminDashboard: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedTab = 0
    @State private var showAddCategory = false
    @State private var selectedCategory: MenuCategory?
    @State private var isLoading = false
    @State private var showEditCategory = false
    @State private var showReorderCategories = false
    @State private var showReorderItems = false
    @State private var categoryIdForItemReorder: String?
    @State private var showAddItem = false

    // Inline reorder (keep sheets too)
    @State private var isReorderingCategoriesInline = false
    @State private var categoryOrderDraft: [String] = []
    @State private var isSavingCategoryOrderInline = false
    @State private var categoriesEditMode: EditMode = .inactive

    @State private var isReorderingItemsInline = false
    @State private var itemOrderDraftByCategory: [String: [String]] = [:]
    @State private var isSavingItemOrderInline = false
    @State private var itemsEditMode: EditMode = .inactive
    
    // Allergy Tags (reusable)
    @State private var showAddAllergyTag = false
    @State private var editingAllergyTag: AllergyTag? = nil
    
    // Enhanced color scheme for professional admin interface
    private let primaryBlue = Color(red: 0.2, green: 0.6, blue: 1.0)
    private let secondaryBlue = Color(red: 0.1, green: 0.4, blue: 0.8)
    private let accentGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    private let accentOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    private let accentRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    private let backgroundGray = Color(red: 0.95, green: 0.95, blue: 0.97)
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                backgroundGray
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Tab Selector
                    tabSelectorView
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        // Categories Tab
                        categoriesTab
                            .tag(0)
                        
                        // Items Tab
                        itemsTab
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategorySheet(menuVM: menuVM)
        }
        .sheet(isPresented: $showEditCategory) {
            if let category = selectedCategory {
                CategoryEditSheet(menuVM: menuVM, category: category)
            }
        }
        .sheet(isPresented: $showReorderCategories) {
            ReorderCategoriesSheet(menuVM: menuVM)
        }
        .sheet(isPresented: $showReorderItems) {
            if let categoryIdForItemReorder {
                ReorderItemsSheet(menuVM: menuVM, categoryId: categoryIdForItemReorder)
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddItemSheet(menuVM: menuVM)
        }
        .sheet(isPresented: $showAddAllergyTag) {
            AddAllergyTagSheet(menuVM: menuVM)
        }
        .sheet(item: $editingAllergyTag) { tag in
            EditAllergyTagSheet(menuVM: menuVM, tag: tag)
        }
        .onAppear {
            // Enable real-time listeners for admin editing
            menuVM.enableAdminEditingMode()
        }
        .onDisappear {
            // Disable real-time listeners and cache current data for other users
            menuVM.disableAdminEditingMode()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu Admin")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Manage your restaurant menu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Quick Stats
                HStack(spacing: 12) {
                    StatCard(title: "Categories", value: "\(menuVM.menuCategories.count)", color: primaryBlue)
                    StatCard(title: "Items", value: "\(menuVM.allMenuItems.count + menuVM.drinkFlavors.count)", color: accentGreen)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
        }
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Tab Selector
    
    private var tabSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(0..<2) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 8) {
                        Image(systemName: tabIcon(for: index))
                            .font(.system(size: 20, weight: .medium))
                        Text(tabTitle(for: index))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(selectedTab == index ? primaryBlue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(selectedTab == index ? primaryBlue.opacity(0.1) : Color.clear)
                    )
                }
            }
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Categories Tab
    
    private var categoriesTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                // Primary actions (always available)
                HStack(spacing: 12) {
                    Button(action: { showAddCategory = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Add Category")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(primaryBlue)
                        )
                    }
                    
                    Button(action: { showReorderCategories = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 16))
                            Text("Reorder Sheet")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(accentOrange)
                        )
                    }
                }
                
                // Inline reorder controls
                if isReorderingCategoriesInline {
                    HStack(spacing: 12) {
                        Button(action: { cancelInlineCategoryReorder() }) {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray)
                                )
                        }
                        .disabled(isSavingCategoryOrderInline)
                        
                        Button(action: { saveInlineCategoryReorder() }) {
                            HStack(spacing: 8) {
                                if isSavingCategoryOrderInline {
                                    ProgressView().tint(.white)
                                }
                                Text(isSavingCategoryOrderInline ? "Saving..." : "Save Order")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(accentGreen)
                            )
                        }
                        .disabled(isSavingCategoryOrderInline)
                    }
                } else {
                    Button(action: { startInlineCategoryReorder() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16))
                            Text("Edit Order (Drag)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(secondaryBlue)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            if isReorderingCategoriesInline {
                List {
                    ForEach(categoryOrderDraft, id: \.self) { catId in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                            Text(catId)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .onMove { indices, newOffset in
                        categoryOrderDraft.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .environment(\.editMode, $categoriesEditMode)
                .listStyle(.plain)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(menuVM.orderedCategories, id: \.id) { category in
                            CategoryAdminCard(
                                category: category,
                                menuVM: menuVM,
                                onEdit: {
                                    selectedCategory = category
                                    showEditCategory = true
                                },
                                onDelete: {
                                    deleteCategory(category)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    private func deleteCategory(_ category: MenuCategory) {
        // Delete all items in the category first
        if let items = category.items {
            for item in items {
                menuVM.deleteItemFromCategory(categoryId: category.id, item: item) { _, _ in
                    // Continue with deletion even if some items fail
                }
            }
        }
        
        // Delete the category document
        let categoryRef = Firestore.firestore().collection("menu").document(category.id)
        categoryRef.delete { error in
            DispatchQueue.main.async {
                if let error = error {
                    DebugLogger.debug("Error deleting category: \(error.localizedDescription)", category: "Admin")
                } else {
                    DebugLogger.debug("Category deleted successfully: \(category.id)", category: "Admin")
                    menuVM.fetchMenu() // Refresh the menu
                }
            }
        }
    }

    // MARK: - Inline Reorder Helpers

    private func currentCategoryOrderForSaving() -> [String] {
        menuVM.orderedCategoryIds.isEmpty
            ? menuVM.menuCategories.map { $0.id }
            : menuVM.orderedCategoryIds
    }

    private func startInlineCategoryReorder() {
        categoryOrderDraft = currentCategoryOrderForSaving()
        isReorderingCategoriesInline = true
        categoriesEditMode = .active
    }

    private func cancelInlineCategoryReorder() {
        isReorderingCategoriesInline = false
        isSavingCategoryOrderInline = false
        categoriesEditMode = .inactive
        categoryOrderDraft = []
    }

    private func saveInlineCategoryReorder() {
        guard !isSavingCategoryOrderInline else { return }
        isSavingCategoryOrderInline = true
        menuVM.updateMenuOrder(categories: categoryOrderDraft, itemsByCategory: menuVM.orderedItemIdsByCategory) { success in
            DispatchQueue.main.async {
                isSavingCategoryOrderInline = false
                if success {
                    isReorderingCategoriesInline = false
                    categoriesEditMode = .inactive
                }
            }
        }
    }

    private func startInlineItemsReorder() {
        // Build a complete per-category list using the current display order (ordered + remaining)
        var draft: [String: [String]] = [:]
        for category in menuVM.orderedCategories {
            draft[category.id] = menuVM.orderedItems(for: category).map { $0.id }
        }
        itemOrderDraftByCategory = draft
        isReorderingItemsInline = true
        itemsEditMode = .active
    }

    private func cancelInlineItemsReorder() {
        isReorderingItemsInline = false
        isSavingItemOrderInline = false
        itemsEditMode = .inactive
        itemOrderDraftByCategory = [:]
    }

    private func saveInlineItemsReorder() {
        guard !isSavingItemOrderInline else { return }
        isSavingItemOrderInline = true

        var itemsByCat = menuVM.orderedItemIdsByCategory
        for (catId, ids) in itemOrderDraftByCategory {
            itemsByCat[catId] = ids
        }

        let categoriesOrder = currentCategoryOrderForSaving()
        menuVM.updateMenuOrder(categories: categoriesOrder, itemsByCategory: itemsByCat) { success in
            DispatchQueue.main.async {
                isSavingItemOrderInline = false
                if success {
                    isReorderingItemsInline = false
                    itemsEditMode = .inactive
                }
            }
        }
    }
    
    // MARK: - Items Tab
    
    private var itemsTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                // Add Item Button
                HStack(spacing: 12) {
                    Button(action: { showAddItem = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Add Item")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(accentGreen)
                        )
                    }
                }
                
                // Inline reorder controls
                if isReorderingItemsInline {
                    HStack(spacing: 12) {
                        Button(action: { cancelInlineItemsReorder() }) {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray)
                                )
                        }
                        .disabled(isSavingItemOrderInline)
                        
                        Button(action: { saveInlineItemsReorder() }) {
                            HStack(spacing: 8) {
                                if isSavingItemOrderInline {
                                    ProgressView().tint(.white)
                                }
                                Text(isSavingItemOrderInline ? "Saving..." : "Save Order")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(accentGreen)
                            )
                        }
                        .disabled(isSavingItemOrderInline)
                    }
                } else {
                    Button(action: { startInlineItemsReorder() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16))
                            Text("Edit Order (Drag)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(secondaryBlue)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            if isReorderingItemsInline {
                List {
                    ForEach(menuVM.orderedCategories, id: \.id) { category in
                        let catId = category.id
                        Section(header: Text(catId)) {
                            let ids = itemOrderDraftByCategory[catId] ?? []
                            ForEach(ids, id: \.self) { itemId in
                                HStack(spacing: 12) {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundColor(.secondary)
                                    Text(itemId)
                                        .font(.system(size: 15, weight: .medium))
                                }
                            }
                            .onMove { indices, newOffset in
                                var arr = itemOrderDraftByCategory[catId] ?? []
                                arr.move(fromOffsets: indices, toOffset: newOffset)
                                itemOrderDraftByCategory[catId] = arr
                            }
                        }
                    }
                }
                .environment(\.editMode, $itemsEditMode)
                .listStyle(.insetGrouped)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Items by Category - Use ordered categories and ordered items
                        ForEach(menuVM.orderedCategories, id: \.id) { category in
                            let items = menuVM.orderedItems(for: category)
                            if !items.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(category.id)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Text("\(items.count) items")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        Button(action: {
                                            categoryIdForItemReorder = category.id
                                            showReorderItems = true
                                        }) {
                                            Image(systemName: "arrow.up.arrow.down.circle")
                                                .font(.system(size: 16))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    
                                    ForEach(items) { item in
                                        ItemAdminCard(
                                            item: item,
                                            category: category,
                                            menuVM: menuVM
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Drink Flavors Section
                        if !menuVM.drinkFlavors.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Drink Flavors")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text("\(menuVM.drinkFlavors.count) flavors")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                
                                ForEach(menuVM.drinkFlavors) { flavor in
                                    DrinkFlavorAdminCard(
                                        flavor: flavor,
                                        menuVM: menuVM
                                    )
                                }
                            }
                        }
                        
                        // Allergy Tags Section (reusable)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Allergy Tags")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(menuVM.allergyTags.count) tags")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Button(action: { showAddAllergyTag = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            if menuVM.allergyTags.isEmpty {
                                Text("No allergy tags yet. Add reusable tags here, then assign them to items.")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .padding(.vertical, 6)
                            } else {
                                ForEach(menuVM.allergyTags) { tag in
                                    AllergyTagAdminCard(
                                        tag: tag,
                                        menuVM: menuVM,
                                        onEdit: { editingAllergyTag = tag }
                                    )
                                }
                            }
                        }
                        
                        // Empty State
                        if menuVM.allMenuItems.isEmpty && menuVM.drinkFlavors.isEmpty && menuVM.allergyTags.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                
                                Text("No Menu Items")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text("Add your first menu item to get started")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func tabIcon(for index: Int) -> String {
        switch index {
        case 0: return "folder.fill"
        case 1: return "list.bullet"
        default: return "circle"
        }
    }
    
    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "Categories"
        case 1: return "Items"
        default: return ""
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivityCard: View {
    let title: String
    let subtitle: String
    let time: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(color.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(time)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let change: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Text(change)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

struct CategoryAdminCard: View {
    let category: MenuCategory
    let menuVM: MenuViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteAlert = false
    
    private var orderNumber: Int {
        if let index = menuVM.orderedCategoryIds.firstIndex(of: category.id) {
            return index + 1
        }
        return 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // Order Number Badge
                if orderNumber > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Text("\(orderNumber)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.id)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Text("\(category.items?.count ?? 0) items")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: { showDeleteAlert = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
            }
            
            if let items = category.items, !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items.prefix(5)) { item in
                            Text(item.id)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        if items.count > 5 {
                            Text("+\(items.count - 5) more")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("No items in this category")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .alert("Delete Category", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete '\(category.id)'? This will also delete all items in this category.")
        }
        // Add item flow removed until implemented
    }
}

struct ItemAdminCard: View {
    let item: MenuItem
    let category: MenuCategory
    let menuVM: MenuViewModel
    
    @State private var showEditSheet = false
    @State private var showDuplicateSheet = false
    @State private var showDeleteAlert = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeleting = false
    @State private var selectedCategoryId: String = ""
    @State private var showMoveConfirmation = false
    @State private var isMoving = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Item Image
            AsyncImage(url: item.resolvedImageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle()
                        .fill(Color(.systemGray5))
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            
            // Item Details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.id)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(item.description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Category Picker
                HStack(spacing: 4) {
                    Text("Category:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if isMoving {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Picker("", selection: $selectedCategoryId) {
                            ForEach(menuVM.orderedCategories, id: \.id) { cat in
                                Text(cat.id).tag(cat.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                        .disabled(isMoving)
                    }
                }
                
                HStack {
                    Text("$\(String(format: "%.2f", item.price))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    if item.isDumpling {
                        Text("🥟")
                            .font(.system(size: 14))
                    }
                    
                    if !item.isAvailable {
                        Text("HIDDEN FROM CUSTOMERS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 8) {
                Button(action: { showEditSheet = true }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                
                Button(action: { showDuplicateSheet = true }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
                
                Button(action: { showDeleteAlert = true }) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.red)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .sheet(isPresented: $showEditSheet) {
            ItemEditSheet(menuVM: menuVM, categoryId: category.id, item: item)
        }
        .sheet(isPresented: $showDuplicateSheet) {
            DuplicateItemSheet(menuVM: menuVM, sourceItem: item, sourceCategoryId: category.id)
        }
        .alert("Delete Item", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("Are you sure you want to delete '\(item.id)'? This action cannot be undone.")
        }
        .alert("Move Item?", isPresented: $showMoveConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedCategoryId = category.id // Reset
            }
            Button("Move") {
                moveItem()
            }
        } message: {
            Text("Move '\(item.id)' from '\(category.id)' to '\(selectedCategoryId)'?")
        }
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
            Button("Retry") {
                deleteItem()
            }
        } message: {
            Text(deleteErrorMessage)
        }
        .onAppear {
            selectedCategoryId = category.id
        }
        .onChange(of: selectedCategoryId) { oldValue, newValue in
            if oldValue != newValue && !oldValue.isEmpty {
                showMoveConfirmation = true
            }
        }
    }
    
    private func deleteItem() {
        isDeleting = true
        
        DebugLogger.debug("🗑️ Attempting to delete item: '\(item.id)' from category: '\(category.id)'", category: "Admin")
        
        menuVM.deleteItemFromCategory(categoryId: category.id, item: item) { success, error in
            DispatchQueue.main.async {
                self.isDeleting = false
                if success {
                    DebugLogger.debug("✅ Item deleted successfully: \(item.id)", category: "Admin")
                    menuVM.fetchMenu() // Refresh the menu
                } else {
                    let errorMsg = error ?? "Unknown error occurred"
                    DebugLogger.debug("❌ Failed to delete item: \(item.id), Error: \(errorMsg)", category: "Admin")
                    self.deleteErrorMessage = "Failed to delete '\(item.id)': \(errorMsg)\n\nThe item may have been modified or the document ID may have special characters. Please try again or contact support if the issue persists."
                    self.showDeleteError = true
                }
            }
        }
    }
    
    private func moveItem() {
        // Don't move if same category
        guard selectedCategoryId != category.id else {
            DebugLogger.debug("⚠️ Item is already in category: \(selectedCategoryId)", category: "Admin")
            return
        }
        
        isMoving = true
        
        // Create updated item with new category
        var movedItem = item
        movedItem.category = selectedCategoryId
        
        // Step 1: Add to new category
        menuVM.addItemToCategory(categoryId: selectedCategoryId, item: movedItem) { success, error in
            if !success {
                DispatchQueue.main.async {
                    self.isMoving = false
                    self.selectedCategoryId = self.category.id // Reset
                    DebugLogger.debug("❌ Failed to add item to new category: \(error ?? "Unknown error")", category: "Admin")
                }
                return
            }
            
            // Step 2: Delete from old category
            self.menuVM.deleteItemFromCategory(categoryId: self.category.id, item: self.item) { success, error in
                DispatchQueue.main.async {
                    if !success {
                        // Rollback: delete from new category
                        self.menuVM.deleteItemFromCategory(categoryId: self.selectedCategoryId, item: movedItem) { _, _ in
                            self.isMoving = false
                            self.selectedCategoryId = self.category.id // Reset
                            DebugLogger.debug("❌ Failed to delete from old category, rolled back: \(error ?? "Unknown error")", category: "Admin")
                        }
                        return
                    }
                    
                    // Success!
                    self.isMoving = false
                    DebugLogger.debug("✅ Item moved successfully from '\(self.category.id)' to '\(self.selectedCategoryId)'", category: "Admin")
                    self.menuVM.fetchMenu() // Refresh the menu
                }
            }
        }
    }
}

// MARK: - Duplicate Item Sheet
struct DuplicateItemSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let sourceItem: MenuItem
    let sourceCategoryId: String
    @Environment(\.dismiss) var dismiss
    
    @State private var itemName: String = ""
    @State private var description: String = ""
    @State private var price: String = ""
    @State private var imageURL: String = ""
    @State private var paymentLinkID: String = ""
    @State private var isAvailable: Bool = true
    @State private var isDumpling: Bool = false
    @State private var toppingModifiersEnabled: Bool = false
    @State private var milkSubModifiersEnabled: Bool = false
    @State private var availableToppingIDs: [String] = []
    @State private var availableMilkSubIDs: [String] = []
    @State private var allergyTagIDs: [String] = []
    
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Item Details") {
                    TextField("Item Name", text: $itemName)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    HStack {
                        Text("$")
                        TextField("Price", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    
                    TextField("Payment Link ID (Optional)", text: $paymentLinkID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section("Item Properties") {
                    Toggle("Available to customers", isOn: $isAvailable)
                    Toggle("Is dumpling item", isOn: $isDumpling)
                    Toggle("Topping modifiers", isOn: $toppingModifiersEnabled)
                    Toggle("Milk substitute options", isOn: $milkSubModifiersEnabled)
                }

                Section("Allergy Info") {
                    if menuVM.allergyTags.isEmpty {
                        Text("No allergy tags yet. Add them in the Allergy Tags section.")
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
                
                Section("Source Item") {
                    HStack {
                        Text("Duplicating from:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(sourceItem.id)
                            .bold()
                    }
                    HStack {
                        Text("Category:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(sourceCategoryId)
                            .bold()
                    }
                }
                
                Section {
                    Button(isSaving ? "Creating..." : "Create Duplicate") {
                        createDuplicate()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canCreate ? Color.green : Color.gray)
                    )
                    .disabled(!canCreate || isSaving)
                }
            }
            .navigationTitle("Duplicate Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                // Pre-populate with source item data
                itemName = "\(sourceItem.id) Copy"
                description = sourceItem.description
                price = String(sourceItem.price)
                imageURL = sourceItem.imageURL
                paymentLinkID = sourceItem.paymentLinkID
                isAvailable = sourceItem.isAvailable
                isDumpling = sourceItem.isDumpling
                toppingModifiersEnabled = sourceItem.toppingModifiersEnabled
                milkSubModifiersEnabled = sourceItem.milkSubModifiersEnabled
                availableToppingIDs = sourceItem.availableToppingIDs
                availableMilkSubIDs = sourceItem.availableMilkSubIDs
                allergyTagIDs = sourceItem.allergyTagIDs
                menuVM.fetchAllergyTags()
            }
        }
    }
    
    private var canCreate: Bool {
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = price.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !trimmedPrice.isEmpty && Double(trimmedPrice) != nil
    }
    
    private func createDuplicate() {
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let priceValue = Double(price) else {
            alertMessage = "Please enter a valid price"
            isSuccess = false
            showAlert = true
            return
        }
        
        isSaving = true
        
        let duplicatedItem = MenuItem(
            id: trimmedName,
            description: trimmedDescription,
            price: priceValue,
            imageURL: imageURL,
            isAvailable: isAvailable,
            paymentLinkID: paymentLinkID,
            isDumpling: isDumpling,
            toppingModifiersEnabled: toppingModifiersEnabled,
            milkSubModifiersEnabled: milkSubModifiersEnabled,
            availableToppingIDs: availableToppingIDs,
            availableMilkSubIDs: availableMilkSubIDs,
            allergyTagIDs: allergyTagIDs,
            category: sourceCategoryId
        )
        
        menuVM.addItemToCategory(categoryId: sourceCategoryId, item: duplicatedItem) { success, error in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    alertMessage = "Item '\(trimmedName)' created successfully as a duplicate!"
                    isSuccess = true
                    menuVM.fetchMenu() // Refresh menu
                } else {
                    alertMessage = error ?? "Failed to create duplicate"
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
}

// MARK: - Supporting Sheets

struct AddCategorySheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var categoryName = ""
    @State private var categoryDescription = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Category Details") {
                    TextField("Category Name", text: $categoryName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Description", text: $categoryDescription, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }
                
                Section {
                    Button("Create Category") {
                        createCategory()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                    )
                    .disabled(categoryName.isEmpty)
                }
            }
            .navigationTitle("Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func createCategory() {
        guard !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Category name cannot be empty."
            isSuccess = false
            showAlert = true
            return
        }
        
        _ = MenuCategory(
            id: categoryName,
            items: [],
            subCategories: nil
        )
        
        menuVM.createCategoryIfNeeded(categoryId: categoryName) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Category '\(categoryName)' created successfully!"
                    isSuccess = true
                    menuVM.fetchMenu() // Refresh the menu
                } else {
                    alertMessage = error ?? "Failed to create category"
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
}

struct CategoryEditSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let category: MenuCategory
    @Environment(\.dismiss) var dismiss
    
    @State private var newName: String = ""
    @State private var isDrinks: Bool = false
    @State private var lemonadeSodaEnabled: Bool = false
    @State private var isToppingCategory: Bool = false
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    @State private var icon: String = ""
    @State private var showIconPicker = false
    @State private var iconImage: UIImage?
    @State private var iconUploading = false
    @State private var hideIcon: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Rename Category") {
                    TextField("New Category Name", text: $newName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.words)
                }
                
                Section("Category Labels") {
                    Toggle("Drinks category", isOn: $isDrinks)
                    Toggle("Enable Lemonade/Soda banner", isOn: $lemonadeSodaEnabled)
                    Toggle("Is Toppings Category", isOn: $isToppingCategory)
                }
                
                Section("Category Icon") {
                    HStack(spacing: 12) {
                        if let url = resolveIconURL(icon) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray5))
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(icon)
                                .font(.system(size: 28))
                                .frame(width: 60, height: 60)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray6))
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Button(action: { showIconPicker = true }) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text(iconUploading ? "Uploading..." : "Upload Icon")
                            }
                        }
                        .disabled(iconUploading)
                    }
                    TextField("Or paste emoji/URL", text: $icon)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Toggle("Hide category image (text only)", isOn: $hideIcon)

                    if !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(role: .destructive) {
                            icon = ""
                        } label: {
                            Label("Remove uploaded icon", systemImage: "trash")
                        }
                    }
                }
                
                Section {
                    Button(isSaving ? "Saving..." : (hasNameChange ? "Save & Rename" : "Save Changes")) {
                        saveCategoryChanges()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSaveEnabled ? Color.blue : Color.gray)
                    )
                    .disabled(!isSaveEnabled || isSaving)
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                newName = category.id
                isDrinks = category.isDrinks
                lemonadeSodaEnabled = category.lemonadeSodaEnabled
                isToppingCategory = category.isToppingCategory
                icon = category.icon
                hideIcon = category.hideIcon
            }
            .sheet(isPresented: $showIconPicker) {
                MenuImagePicker(selectedImage: $iconImage)
            }
            .onChange(of: iconImage) { oldValue, newValue in
                if let img = newValue {
                    uploadCategoryIcon(img)
                }
            }
        }
    }
    
    private var hasNameChange: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != category.id
    }
    private var hasFlagChange: Bool {
        return isDrinks != category.isDrinks
            || lemonadeSodaEnabled != category.lemonadeSodaEnabled
            || isToppingCategory != category.isToppingCategory
    }
    private var hasDisplayChange: Bool {
        return hideIcon != category.hideIcon
    }
    private var isSaveEnabled: Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && (hasNameChange || hasFlagChange || icon != category.icon || hasDisplayChange)
    }
    
    private func saveCategoryChanges() {
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        isSaving = true
        func finish(_ success: Bool, _ message: String?) {
            DispatchQueue.main.async {
                isSaving = false
                isSuccess = success
                alertMessage = message ?? (success ? "Category updated successfully." : "Failed to update category.")
                showAlert = true
            }
        }
        let applyFlagsAndIcon: (String) -> Void = { catId in
            // Update flags
            // Enforce single toppings category by clearing the flag on any other category first.
            if self.isToppingCategory {
                let others = self.menuVM.menuCategories.filter { $0.id != catId && $0.isToppingCategory }
                for other in others {
                    self.menuVM.updateCategoryFlags(categoryId: other.id, isDrinks: other.isDrinks, lemonadeSodaEnabled: other.lemonadeSodaEnabled, isToppingCategory: false) { _, _ in }
                }
            }

            self.menuVM.updateCategoryFlags(categoryId: catId, isDrinks: self.isDrinks, lemonadeSodaEnabled: self.lemonadeSodaEnabled, isToppingCategory: self.isToppingCategory) { success, _ in
                // Update icon after flags
                self.menuVM.updateCategoryIcon(categoryId: catId, icon: self.icon) { success2, msg in
                    self.menuVM.updateCategoryHideIcon(categoryId: catId, hideIcon: self.hideIcon) { success3, msg3 in
                        finish(success && success2 && success3, msg3 ?? msg)
                    }
                }
            }
        }
        if target == category.id {
            applyFlagsAndIcon(category.id)
        } else {
            menuVM.renameCategory(oldId: category.id, newId: target, newIsDrinks: isDrinks, newLemonadeSodaEnabled: lemonadeSodaEnabled, newHideIcon: hideIcon) { success, message in
                DispatchQueue.main.async {
                    if success {
                        applyFlagsAndIcon(target)
                    } else {
                        finish(false, message)
                    }
                }
            }
        }
    }
    
    private func resolveIconURL(_ icon: String) -> URL? {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("gs://") {
            let components = trimmed.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
                return URL(string: downloadURL)
            }
        } else if trimmed.hasPrefix("http") {
            return URL(string: trimmed)
        }
        return nil
    }
    
    private func uploadCategoryIcon(_ image: UIImage) {
        iconUploading = true
        let pngData = image.pngData()
        let isPNG = (pngData != nil)
        let imageData = pngData ?? image.jpegData(compressionQuality: 0.9)
        guard let data = imageData else {
            iconUploading = false
            return
        }
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let safeName = newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.id : newName
        let ext = isPNG ? "png" : "jpg"
        let fileName = "\(safeName)_icon_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let iconRef = storageRef.child("category_icons/\(fileName)")
        let metadata = StorageMetadata()
        metadata.contentType = isPNG ? "image/png" : "image/jpeg"
        iconRef.putData(data, metadata: metadata) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.alertMessage = "Icon upload failed: \(error.localizedDescription)"
                    self.isSuccess = false
                    self.showAlert = true
                    self.iconUploading = false
                }
                return
            }
            iconRef.downloadURL { url, _ in
                DispatchQueue.main.async {
                    // Prefer direct HTTPS URL for reliability; fallback to gs://
                    if let direct = url?.absoluteString {
                        self.icon = direct
                        self.menuVM.updateCategoryIcon(categoryId: self.category.id, icon: direct) { _, _ in }
                    } else {
                        let gs = "gs://\(storage.reference().bucket)/category_icons/\(fileName)"
                        self.icon = gs
                        self.menuVM.updateCategoryIcon(categoryId: self.category.id, icon: gs) { _, _ in }
                    }
                    self.iconUploading = false
                }
            }
        }
    }
}

struct ImageUploadSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedImage: UIImage?
    @State private var isShowingImagePicker = false
    @State private var selectedCategory: MenuCategory?
    @State private var selectedItem: MenuItem?
    @State private var isUploading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Image Upload")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.top, 20)
                
                Text("Upload images for menu items")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Category and Item Selection
                VStack(spacing: 16) {
                    Text("Select Category")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(menuVM.orderedMenuCategories) { category in
                                Button(action: {
                                    selectedCategory = category
                                    selectedItem = nil
                                }) {
                                    Text(category.id)
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(selectedCategory?.id == category.id ? Color.blue : Color(.systemGray5))
                                        )
                                        .foregroundColor(selectedCategory?.id == category.id ? .white : .primary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    if let category = selectedCategory, let items = category.items, !items.isEmpty {
                        Text("Select Item")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(items) { item in
                                    Button(action: {
                                        selectedItem = item
                                    }) {
                                        VStack(spacing: 4) {
                                            AsyncImage(url: item.resolvedImageURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle()
                                                    .fill(Color(.systemGray5))
                                            }
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            Text(item.id)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedItem?.id == item.id ? Color.blue.opacity(0.2) : Color(.systemGray6))
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                
                // Upload Section
                if selectedItem != nil {
                    VStack(spacing: 16) {
                        Text("Upload New Image")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(action: {
                            isShowingImagePicker = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 20))
                                Text("Select Image")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        if isUploading {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Uploading image...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Image Upload")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingImagePicker) {
                MenuImagePicker(selectedImage: $selectedImage)
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let image = newValue, let item = selectedItem {
                    uploadImage(image, for: item)
                }
            }
        }
    }
    
    private func uploadImage(_ image: UIImage, for item: MenuItem) {
        isUploading = true
        
        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            alertMessage = "Failed to process image"
            isSuccess = false
            showAlert = true
            isUploading = false
            return
        }
        
        // Upload to Firebase Storage
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let imageName = "\(item.id)_\(Date().timeIntervalSince1970).jpg"
        let imageRef = storageRef.child("menu_images/\(imageName)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        imageRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                DispatchQueue.main.async {
                    alertMessage = "Upload failed: \(error.localizedDescription)"
                    isSuccess = false
                    showAlert = true
                    isUploading = false
                }
                return
            }
            
            // Get download URL
            imageRef.downloadURL { url, error in
                DispatchQueue.main.async {
                    if let downloadURL = url {
                        // Update item with new image URL
                        let gsURL = "gs://\(storage.reference().bucket)/menu_images/\(imageName)"
                        updateItemImageURL(item: item, newImageURL: gsURL)
                    } else {
                        alertMessage = "Failed to get download URL"
                        isSuccess = false
                        showAlert = true
                        isUploading = false
                    }
                }
            }
        }
    }
    
    private func updateItemImageURL(item: MenuItem, newImageURL: String) {
        // Find the category containing this item
        for category in menuVM.menuCategories {
            if let items = category.items, items.contains(where: { $0.id == item.id }) {
                // Create updated item with new image URL
                var updatedItem = item
                updatedItem.imageURL = newImageURL
                
                // Update in Firestore
                menuVM.updateItemInCategory(categoryId: category.id, oldItem: item, newItem: updatedItem) { success, error in
                    DispatchQueue.main.async {
                        isUploading = false
                        if success {
                            alertMessage = error ?? "Image uploaded successfully!"
                            isSuccess = true
                            selectedImage = nil
                            menuVM.fetchMenu() // Refresh the menu
                        } else {
                            alertMessage = error ?? "Failed to update item"
                            isSuccess = false
                        }
                        showAlert = true
                    }
                }
                return
            }
        }
        
        // If we get here, item wasn't found
        DispatchQueue.main.async {
            isUploading = false
            alertMessage = "Item not found in any category"
            isSuccess = false
            showAlert = true
        }
    }
}

// Image Picker for selecting images from photo library
struct MenuImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MenuImagePicker
        
        init(_ parent: MenuImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// Category selection sheet removed until Add Item flow is reintroduced

struct DrinkFlavorAdminCard: View {
    let flavor: DrinkFlavor
    let menuVM: MenuViewModel
    
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Flavor Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(width: 60, height: 60)
                
                if !flavor.icon.isEmpty {
                    if let url = flavor.resolvedIconURL {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                        } placeholder: {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Emoji
                        Text(flavor.icon)
                            .font(.system(size: 24))
                    }
                } else {
                    Image(systemName: flavor.isLemonade ? "drop.fill" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 24))
                        .foregroundColor(flavor.isLemonade ? .yellow : .blue)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            
            // Flavor Details
            VStack(alignment: .leading, spacing: 4) {
                Text(flavor.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(flavor.isLemonade ? "Lemonade" : "Soda")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("$5.50")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    if !flavor.isAvailable {
                        Text("HIDDEN FROM CUSTOMERS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 8) {
                Button(action: { showEditSheet = true }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                
                Button(action: { showDeleteAlert = true }) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.red)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .sheet(isPresented: $showEditSheet) {
            EditDrinkFlavorSheet(menuVM: menuVM, flavor: flavor)
        }
        .alert("Delete Flavor", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteFlavor()
            }
        } message: {
            Text("Are you sure you want to delete '\(flavor.name)'? This action cannot be undone.")
        }
    }
    
    private func deleteFlavor() {
        isDeleting = true
        menuVM.deleteDrinkFlavor(flavor) { success, errorMessage in
            DispatchQueue.main.async {
                isDeleting = false
                if !success {
                    // Show error alert
                    DebugLogger.debug("❌ Failed to delete drink flavor: \(errorMessage ?? "Unknown error")", category: "Admin")
                    // You could add an alert here to show the error to the user
                }
            }
        }
    }
}

struct EditDrinkFlavorSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let flavor: DrinkFlavor
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var isLemonade = true
    @State private var isAvailable = true
    @State private var icon = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Flavor Details") {
                    TextField("Flavor Name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Icon (Emoji or URL)", text: $icon)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    Toggle("Is Lemonade", isOn: $isLemonade)
                    Toggle("Available", isOn: $isAvailable)
                }
                
                Section {
                    Button("Update Flavor") {
                        updateFlavor()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue)
                    )
                    .disabled(name.isEmpty)
                }
            }
            .navigationTitle("Edit Flavor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                name = flavor.name
                isLemonade = flavor.isLemonade
                isAvailable = flavor.isAvailable
                icon = flavor.icon
            }
        }
    }
    
    private func updateFlavor() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Flavor name cannot be empty."
            isSuccess = false
            showAlert = true
            return
        }
        
        let updatedFlavor = DrinkFlavor(
            id: flavor.id,
            name: name,
            isLemonade: isLemonade,
            isAvailable: isAvailable,
            icon: icon
        )
        
        menuVM.updateDrinkFlavor(updatedFlavor) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Flavor updated successfully!"
                    isSuccess = true
                } else {
                    alertMessage = "Failed to update flavor: \(errorMessage ?? "Unknown error")"
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
}

// MARK: - Add Item Sheet
struct AddItemSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedCategory: MenuCategory?
    @State private var itemName: String = ""
    @State private var description: String = ""
    @State private var price: String = ""
    @State private var imageURL: String = ""
    @State private var paymentLinkID: String = ""
    @State private var isAvailable: Bool = true
    @State private var isDumpling: Bool = false
    @State private var toppingModifiersEnabled: Bool = false
    @State private var milkSubModifiersEnabled: Bool = false
    @State private var selectedAllergyTagIDs: [String] = []
    
    @State private var selectedImage: UIImage?
    @State private var isShowingImagePicker = false
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Category") {
                    Picker("Select Category", selection: $selectedCategory) {
                        Text("Choose a category").tag(nil as MenuCategory?)
                        ForEach(menuVM.orderedCategories, id: \.id) { category in
                            Text(category.id).tag(category as MenuCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Item Details") {
                    TextField("Item Name", text: $itemName)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    HStack {
                        Text("$")
                        TextField("Price", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    
                    TextField("Payment Link ID (Optional)", text: $paymentLinkID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section("Photo") {
                    HStack(spacing: 12) {
                        if !imageURL.isEmpty {
                            AsyncImage(url: URL(string: imageURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray5))
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else if selectedImage != nil {
                            Image(uiImage: selectedImage!)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray6))
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Button(action: { isShowingImagePicker = true }) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text(isUploading ? "Uploading..." : "Select Photo")
                            }
                        }
                        .disabled(isUploading)
                        
                        if selectedImage != nil {
                            Button(action: { 
                                selectedImage = nil
                                imageURL = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Section("Item Properties") {
                    Toggle("Available to customers", isOn: $isAvailable)
                    Toggle("Is dumpling item", isOn: $isDumpling)
                    Toggle("Topping modifiers", isOn: $toppingModifiersEnabled)
                    Toggle("Milk substitute options", isOn: $milkSubModifiersEnabled)
                }

                Section("Allergy Info") {
                    if menuVM.allergyTags.isEmpty {
                        Text("No allergy tags yet. Add them in the Allergy Tags section.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(menuVM.allergyTags) { tag in
                            Toggle(tag.title, isOn: Binding(
                                get: { selectedAllergyTagIDs.contains(tag.id) },
                                set: { enabled in
                                    if enabled {
                                        if !selectedAllergyTagIDs.contains(tag.id) { selectedAllergyTagIDs.append(tag.id) }
                                    } else {
                                        selectedAllergyTagIDs.removeAll { $0 == tag.id }
                                    }
                                }
                            ))
                        }
                    }
                }
                
                Section {
                    Button(isSaving ? "Creating..." : "Create Item") {
                        createItem()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canCreate ? Color.blue : Color.gray)
                    )
                    .disabled(!canCreate || isSaving || isUploading)
                }
            }
            .navigationTitle("Add Menu Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving || isUploading)
                }
            }
            .sheet(isPresented: $isShowingImagePicker) {
                MenuImagePicker(selectedImage: $selectedImage)
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let img = newValue {
                    uploadImage(img)
                }
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                menuVM.fetchAllergyTags()
            }
        }
    }
    
    private var canCreate: Bool {
        guard let _ = selectedCategory else { return false }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = price.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !trimmedPrice.isEmpty && Double(trimmedPrice) != nil
    }
    
    private func createItem() {
        guard let category = selectedCategory else { return }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let priceValue = Double(price) else {
            alertMessage = "Please enter a valid price"
            isSuccess = false
            showAlert = true
            return
        }
        
        isSaving = true
        
        let newItem = MenuItem(
            id: trimmedName,
            description: trimmedDescription,
            price: priceValue,
            imageURL: imageURL,
            isAvailable: isAvailable,
            paymentLinkID: paymentLinkID,
            isDumpling: isDumpling,
            toppingModifiersEnabled: toppingModifiersEnabled,
            milkSubModifiersEnabled: milkSubModifiersEnabled,
            availableToppingIDs: [],
            availableMilkSubIDs: [],
            allergyTagIDs: selectedAllergyTagIDs,
            category: category.id
        )
        
        menuVM.addItemToCategory(categoryId: category.id, item: newItem) { success, error in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    alertMessage = "Item '\(trimmedName)' created successfully!"
                    isSuccess = true
                    menuVM.fetchMenu() // Refresh menu
                } else {
                    alertMessage = error ?? "Failed to create item"
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
    
    private func uploadImage(_ image: UIImage) {
        isUploading = true
        
        // Detect image format (PNG or JPEG)
        let pngData = image.pngData()
        let isPNG = (pngData != nil)
        let imageData = pngData ?? image.jpegData(compressionQuality: 0.8)
        
        guard let data = imageData else {
            alertMessage = "Failed to process image"
            isSuccess = false
            showAlert = true
            isUploading = false
            return
        }
        
        // Upload to Firebase Storage
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let ext = isPNG ? "png" : "jpg"
        let imageName = "\(itemName.isEmpty ? "item" : itemName)_\(Date().timeIntervalSince1970).\(ext)"
        let imageRef = storageRef.child("menu_images/\(imageName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = isPNG ? "image/png" : "image/jpeg"
        
        imageRef.putData(data, metadata: metadata) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    alertMessage = "Upload failed: \(error.localizedDescription)"
                    isSuccess = false
                    showAlert = true
                    isUploading = false
                }
                return
            }
            
            // Get download URL and use it directly (it's already https:// format)
            imageRef.downloadURL { url, error in
                DispatchQueue.main.async {
                    if let downloadURL = url {
                        // Use the direct HTTPS URL instead of gs:// for better compatibility
                        imageURL = downloadURL.absoluteString
                        DebugLogger.debug("✅ Image uploaded successfully: \(downloadURL.absoluteString)", category: "Admin")
                    } else {
                        // Fallback: construct gs:// URL with correct bucket name
                        // Firebase default bucket is always projectId.appspot.com
                        let gsURL = "gs://dumplinghouseapp.appspot.com/menu_images/\(imageName)"
                        imageURL = gsURL
                        DebugLogger.debug("✅ Image uploaded (using gs:// fallback): \(gsURL)", category: "Admin")
                    }
                    isUploading = false
                }
            }
        }
    }
}

// MARK: - Item Edit Sheet (Name + Photo)
struct ItemEditSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let categoryId: String
    let item: MenuItem
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var imageURL: String = ""
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false

    // Allergy tags (reusable)
    @State private var selectedAllergyTagIDs: [String] = []
    
    // Image picking/upload
    @State private var selectedImage: UIImage?
    @State private var isShowingImagePicker = false
    @State private var isUploading = false
    
    // Enhanced image management
    @State private var originalImageURL: String = ""
    @State private var hasSelectedNewImage = false
    @State private var showRemoveConfirmation = false
    @State private var showClearSelectionConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Allergy Tags") {
                    if menuVM.allergyTags.isEmpty {
                        Text("No allergy tags yet. Create them in Menu Admin → Allergy Tags.")
                            .foregroundColor(.secondary)
                    } else {
                        let tags = menuVM.allergyTags.sorted { $0.order < $1.order }
                        ForEach(tags) { tag in
                            Toggle(isOn: Binding(
                                get: { selectedAllergyTagIDs.contains(tag.id) },
                                set: { enabled in
                                    if enabled {
                                        if !selectedAllergyTagIDs.contains(tag.id) {
                                            selectedAllergyTagIDs.append(tag.id)
                                        }
                                    } else {
                                        selectedAllergyTagIDs.removeAll { $0 == tag.id }
                                    }
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Text(tag.title)
                                    if !tag.isAvailable {
                                        Text("HIDDEN")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.red.opacity(0.12)))
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Photo") {
                    // Image Previews
                    HStack(spacing: 16) {
                        // Current/Original Image
                        VStack(spacing: 4) {
                            if let url = MenuItem(id: item.id, description: item.description, price: item.price, imageURL: originalImageURL, isAvailable: item.isAvailable, paymentLinkID: item.paymentLinkID, isDumpling: item.isDumpling, toppingModifiersEnabled: item.toppingModifiersEnabled, milkSubModifiersEnabled: item.milkSubModifiersEnabled, availableToppingIDs: item.availableToppingIDs, availableMilkSubIDs: item.availableMilkSubIDs, category: item.category).resolvedImageURL, !originalImageURL.isEmpty {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(Color(.systemGray5))
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                            } else {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(.systemGray6))
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Image(systemName: "photo.slash")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Text(originalImageURL.isEmpty ? "No Image" : "Current")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        // Arrow if image is being changed
                        if hasSelectedNewImage || imageURL != originalImageURL {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        
                        // New Selected Image
                        if hasSelectedNewImage, let newImage = selectedImage {
                            VStack(spacing: 4) {
                                Image(uiImage: newImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.green, lineWidth: 2)
                                    )
                                
                                Text("New")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        } else if imageURL.isEmpty && !hasSelectedNewImage && !originalImageURL.isEmpty {
                            VStack(spacing: 4) {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.red.opacity(0.1))
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.red, lineWidth: 2)
                                        )
                                    
                                    Image(systemName: "trash")
                                        .font(.system(size: 24))
                                        .foregroundColor(.red)
                                }
                                
                                Text("Removed")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    
                    // Status Message
                    if hasSelectedNewImage {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("New image selected - tap Save to apply")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if imageURL.isEmpty && !originalImageURL.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Image will be removed when saved")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 10) {
                        Button(action: { isShowingImagePicker = true }) {
                            HStack {
                                Image(systemName: hasSelectedNewImage ? "arrow.triangle.2.circlepath" : "photo.fill")
                                    .font(.system(size: 14))
                                Text(isUploading ? "Uploading..." : (hasSelectedNewImage ? "Choose Different Photo" : "Select New Photo"))
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isUploading)
                        
                        HStack(spacing: 10) {
                            // Clear Selection Button
                            if hasSelectedNewImage {
                                Button(action: { showClearSelectionConfirmation = true }) {
                                    HStack {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                        Text("Clear Selection")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                            
                            // Remove Image Button
                            if !imageURL.isEmpty || !originalImageURL.isEmpty {
                                Button(action: { showRemoveConfirmation = true }) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 14))
                                        Text("Remove Image")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(imageURL.isEmpty && originalImageURL.isEmpty)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving || isUploading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        saveChanges()
                    }
                    .disabled(!canSave || isUploading)
                }
            }
            .sheet(isPresented: $isShowingImagePicker) {
                MenuImagePicker(selectedImage: $selectedImage)
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let img = newValue {
                    uploadImage(img)
                }
            }
            .onAppear {
                name = item.id
                description = item.description
                imageURL = item.imageURL
                originalImageURL = item.imageURL
                selectedAllergyTagIDs = item.allergyTagIDs
                menuVM.fetchAllergyTags()
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
            .alert("Remove Image?", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeImage()
                }
            } message: {
                Text("This will remove the image from this item. You can add a new image later if needed.")
            }
            .alert("Clear Selection?", isPresented: $showClearSelectionConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearSelectedImage()
                }
            } message: {
                Text("This will discard the newly selected image and keep the current one.")
            }
        }
    }
    
    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameChanged = trimmed != item.id
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionChanged = trimmedDescription != item.description
        let imageChanged = imageURL != originalImageURL
        let hasNewImage = hasSelectedNewImage
        let tagsChanged = Set(selectedAllergyTagIDs) != Set(item.allergyTagIDs)
        
        return !trimmed.isEmpty && (nameChanged || descriptionChanged || imageChanged || hasNewImage || tagsChanged)
    }
    
    private func removeImage() {
        imageURL = ""
        selectedImage = nil
        hasSelectedNewImage = false
        DebugLogger.debug("🗑️ Image marked for removal", category: "Admin")
    }
    
    private func clearSelectedImage() {
        selectedImage = nil
        hasSelectedNewImage = false
        imageURL = originalImageURL
        DebugLogger.debug("❌ Cleared selected image, restored original", category: "Admin")
    }
    
    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isSaving = true
        let updated = MenuItem(
            id: trimmedName,
            description: trimmedDescription,
            price: item.price,
            imageURL: imageURL,
            isAvailable: item.isAvailable,
            paymentLinkID: item.paymentLinkID,
            isDumpling: item.isDumpling,
            toppingModifiersEnabled: item.toppingModifiersEnabled,
            milkSubModifiersEnabled: item.milkSubModifiersEnabled,
            availableToppingIDs: item.availableToppingIDs,
            availableMilkSubIDs: item.availableMilkSubIDs,
            allergyTagIDs: selectedAllergyTagIDs,
            category: item.category
        )
        
        menuVM.updateItemInCategory(categoryId: categoryId, oldItem: item, newItem: updated) { success, error in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    // If the ViewModel provides a success/info message (e.g. offline sync),
                    // show it; otherwise use the default.
                    alertMessage = error ?? "Item updated successfully!"
                    isSuccess = true
                    
                    // Update the in-memory model immediately so the admin UI reflects the change
                    // without waiting for Firestore cache/listener propagation.
                    if let catIndex = menuVM.menuCategories.firstIndex(where: { $0.id == categoryId }),
                       var items = menuVM.menuCategories[catIndex].items,
                       let itemIndex = items.firstIndex(where: { $0.id == item.id }) {
                        items[itemIndex] = updated
                        menuVM.menuCategories[catIndex].items = items
                        
                        // If the item was renamed, keep the saved order consistent too.
                        if item.id != updated.id,
                           var order = menuVM.orderedItemIdsByCategory[categoryId],
                           let orderIndex = order.firstIndex(of: item.id) {
                            order[orderIndex] = updated.id
                            menuVM.orderedItemIdsByCategory[categoryId] = order
                        }
                    }
                    
                    // Still refresh to ensure we stay in sync with Firestore.
                    menuVM.refreshCategoryItems(categoryId: categoryId)
                } else {
                    alertMessage = error ?? "Failed to update item"
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
    
    private func uploadImage(_ image: UIImage) {
        isUploading = true
        
        // Detect image format (PNG or JPEG)
        let pngData = image.pngData()
        let isPNG = (pngData != nil)
        let imageData = pngData ?? image.jpegData(compressionQuality: 0.8)
        
        guard let data = imageData else {
            alertMessage = "Failed to process image"
            isSuccess = false
            showAlert = true
            isUploading = false
            return
        }
        
        // Upload to Firebase Storage
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let ext = isPNG ? "png" : "jpg"
        let imageName = "\(item.id)_\(Date().timeIntervalSince1970).\(ext)"
        let imageRef = storageRef.child("menu_images/\(imageName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = isPNG ? "image/png" : "image/jpeg"
        
        imageRef.putData(data, metadata: metadata) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    alertMessage = "Upload failed: \(error.localizedDescription)"
                    isSuccess = false
                    showAlert = true
                    isUploading = false
                }
                return
            }
            
            // Get download URL and use it directly (it's already https:// format)
            imageRef.downloadURL { url, error in
                DispatchQueue.main.async {
                    if let downloadURL = url {
                        // Use the direct HTTPS URL instead of gs:// for better compatibility
                        imageURL = downloadURL.absoluteString
                        hasSelectedNewImage = true
                        DebugLogger.debug("✅ Image uploaded successfully: \(downloadURL.absoluteString)", category: "Admin")
                    } else {
                        // Fallback: construct gs:// URL with correct bucket name
                        // Firebase default bucket is always projectId.appspot.com
                        let gsURL = "gs://dumplinghouseapp.appspot.com/menu_images/\(imageName)"
                        imageURL = gsURL
                        hasSelectedNewImage = true
                        DebugLogger.debug("✅ Image uploaded (using gs:// fallback): \(gsURL)", category: "Admin")
                    }
                    isUploading = false
                }
            }
        }
    }
}

// MARK: - Reorder Categories
struct ReorderCategoriesSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) var dismiss
    @State private var categories: [String] = []
    @State private var isSaving = false
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        NavigationView {
            List {
                ForEach(categories, id: \.self) { cat in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                        Text(cat)
                    }
                }
                .onMove { indices, newOffset in
                    categories.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Reorder Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                        .disabled(isSaving)
                    Button(isSaving ? "Saving..." : "Save") {
                        saveOrder()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                let current = menuVM.orderedCategoryIds.isEmpty
                    ? menuVM.menuCategories.map { $0.id }
                    : menuVM.orderedCategoryIds
                categories = current
            }
        }
    }
    
    private func saveOrder() {
        isSaving = true
        let itemsByCat = menuVM.orderedItemIdsByCategory
        menuVM.updateMenuOrder(categories: categories, itemsByCategory: itemsByCat) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Reorder Items in Category
struct ReorderItemsSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let categoryId: String
    @Environment(\.dismiss) var dismiss
    @State private var itemIds: [String] = []
    @State private var isSaving = false
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        NavigationView {
            List {
                ForEach(itemIds, id: \.self) { itemId in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                        Text(itemId)
                    }
                }
                .onMove { indices, newOffset in
                    itemIds.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Reorder Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    EditButton()
                        .disabled(isSaving)
                    Button(isSaving ? "Saving..." : "Save") {
                        saveOrder()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                // Prefer saved order; fall back to current category items
                if let existing = menuVM.orderedItemIdsByCategory[categoryId], !existing.isEmpty {
                    itemIds = existing
                } else if let items = menuVM.menuCategories.first(where: { $0.id == categoryId })?.items {
                    itemIds = items.map { $0.id }
                } else {
                    itemIds = []
                }
            }
        }
    }
    
    private func saveOrder() {
        isSaving = true
        var itemsByCat = menuVM.orderedItemIdsByCategory
        itemsByCat[categoryId] = itemIds
        
        let categoriesOrder = menuVM.orderedCategoryIds.isEmpty
            ? menuVM.menuCategories.map { $0.id }
            : menuVM.orderedCategoryIds
        
        menuVM.updateMenuOrder(categories: categoriesOrder, itemsByCategory: itemsByCat) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Allergy Tags Admin UI

struct AllergyTagAdminCard: View {
    let tag: AllergyTag
    let menuVM: MenuViewModel
    let onEdit: () -> Void
    
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tag.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                if !tag.isAvailable {
                    Text("HIDDEN FROM CUSTOMERS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.1))
                        )
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                
                Button(action: { showDeleteAlert = true }) {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.red)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .alert("Delete Allergy Tag", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteTag() }
        } message: {
            Text("Are you sure you want to delete '\(tag.title)'? This action cannot be undone.")
        }
    }
    
    private func deleteTag() {
        isDeleting = true
        menuVM.deleteAllergyTag(tag) { success, errorMessage in
            DispatchQueue.main.async {
                isDeleting = false
                if !success {
                    DebugLogger.debug("❌ Failed to delete allergy tag: \(errorMessage ?? "Unknown error")", category: "Admin")
                }
            }
        }
    }
}

struct AddAllergyTagSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var isAvailable: Bool = true
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Allergy Tag") {
                    TextField("Tag text (ex: Contains peanuts)", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Toggle("Available", isOn: $isAvailable)
                }
                
                Section {
                    Button("Add Tag") { addTag() }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue)
                        )
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add Allergy Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func addTag() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let tag = AllergyTag(id: UUID().uuidString, title: trimmed, isAvailable: isAvailable)
        menuVM.addAllergyTag(tag) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Allergy tag added successfully!"
                    isSuccess = true
                } else {
                    alertMessage = errorMessage ?? "Failed to add allergy tag."
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
}

struct EditAllergyTagSheet: View {
    @ObservedObject var menuVM: MenuViewModel
    let tag: AllergyTag
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var isAvailable: Bool = true
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Allergy Tag") {
                    TextField("Tag text", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Toggle("Available", isOn: $isAvailable)
                }
                
                Section {
                    Button("Save") { updateTag() }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue)
                        )
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Edit Allergy Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                title = tag.title
                isAvailable = tag.isAvailable
            }
            .alert(isSuccess ? "Success!" : "Error", isPresented: $showAlert) {
                Button("OK") {
                    if isSuccess { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func updateTag() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let updated = AllergyTag(id: tag.id, title: trimmed, isAvailable: isAvailable, order: tag.order)
        menuVM.updateAllergyTag(updated) { success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Allergy tag updated successfully!"
                    isSuccess = true
                } else {
                    alertMessage = errorMessage ?? "Failed to update allergy tag."
                    isSuccess = false
                }
                showAlert = true
            }
        }
    }
}

#Preview {
    MenuAdminDashboard(menuVM: MenuViewModel())
} 