import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Reward Tier Admin View
/// Admin interface for configuring which menu items are available for each reward tier
struct RewardTierAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RewardTierAdminViewModel()
    @State private var selectedTier: RewardTierConfig?
    @State private var showAddItemSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Theme.modernBackground,
                        Theme.modernCardSecondary,
                        Theme.modernBackground
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    if viewModel.isLoading {
                        loadingView
                    } else if let error = viewModel.errorMessage {
                        errorView(error)
                    } else {
                        tiersList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.primaryGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.loadTiers() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Theme.primaryGold)
                    }
                }
            }
            .onAppear {
                viewModel.loadTiers()
            }
            .sheet(isPresented: $showAddItemSheet) {
                if let tier = selectedTier {
                    AddItemToTierSheet(
                        tier: tier,
                        onItemAdded: {
                            viewModel.loadTiers()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.darkGoldGradient)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reward Items")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    Text("Configure eligible items for each reward tier")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Theme.modernCard)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(Theme.primaryGold)
            Text("Loading reward tiers...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.modernSecondary)
            Spacer()
        }
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
            Text("Error loading tiers")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.modernPrimary)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: { viewModel.loadTiers() }) {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.primaryGold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .stroke(Theme.primaryGold, lineWidth: 1)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Tiers List
    private var tiersList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.defaultTiers, id: \.id) { defaultTier in
                    let configuredTier = viewModel.tiers.first { $0.id == defaultTier.id }
                    let activeTier = configuredTier ?? RewardTierConfig(
                        id: defaultTier.id,
                        pointsRequired: defaultTier.pointsRequired,
                        tierName: defaultTier.name,
                        eligibleItems: []
                    )
                    
                    TierCard(
                        tier: activeTier,
                        defaultName: defaultTier.name,
                        onAddItem: {
                            selectedTier = activeTier
                            showAddItemSheet = true
                        },
                        onRemoveItem: { item in
                            Task {
                                await viewModel.removeItem(
                                    from: activeTier.id,
                                    itemId: item.itemId
                                )
                            }
                        }
                    )
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Tier Card
struct TierCard: View {
    let tier: RewardTierConfig
    let defaultName: String
    let onAddItem: () -> Void
    let onRemoveItem: (RewardEligibleItem) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(tier.pointsRequired) Points")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                        
                        Text(tier.tierName ?? defaultName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.modernSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text("\(tier.eligibleItems.count) items")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(tier.eligibleItems.isEmpty ? Theme.modernSecondary : Theme.primaryGold)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.modernSecondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(16)
                .background(Theme.modernCard)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 12) {
                    // Add item button
                    Button(action: onAddItem) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Theme.primaryGold)
                            Text("Add Menu Item")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.primaryGold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.primaryGold.opacity(0.5), lineWidth: 1)
                                .background(Theme.primaryGold.opacity(0.1))
                        )
                        .cornerRadius(10)
                    }
                    
                    // Eligible items list
                    if tier.eligibleItems.isEmpty {
                        Text("No items configured for this tier")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.modernSecondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(tier.eligibleItems) { item in
                            EligibleItemRow(
                                item: item,
                                onRemove: { onRemoveItem(item) }
                            )
                        }
                    }
                }
                .padding(16)
                .background(Theme.modernCardSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Eligible Item Row
struct EligibleItemRow: View {
    let item: RewardEligibleItem
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Image placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                if let imageURL = item.imageURL, !imageURL.isEmpty {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                        default:
                            Image(systemName: "takeoutbag.and.cup.and.straw")
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                } else {
                    Image(systemName: "takeoutbag.and.cup.and.straw")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.itemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.modernPrimary)
                
                if let categoryId = item.categoryId {
                    Text(categoryId)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.modernSecondary)
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.modernCard)
        )
    }
}

// MARK: - Add Item to Tier Sheet
struct AddItemToTierSheet: View {
    let tier: RewardTierConfig
    let onItemAdded: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddItemToTierViewModel()
    @State private var searchText = ""
    @State private var expandedCategories: Set<String> = []
    @State private var addedItemIds: Set<String> = []
    
    // Filter items by search text, maintaining category grouping
    var filteredItemsByCategory: [String: [RewardMenuItem]] {
        if searchText.isEmpty {
            return viewModel.itemsByCategory
        }
        var filtered: [String: [RewardMenuItem]] = [:]
        for (category, items) in viewModel.itemsByCategory {
            let matchingItems = items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
            if !matchingItems.isEmpty {
                filtered[category] = matchingItems
            }
        }
        return filtered
    }
    
    var filteredCategoryOrder: [String] {
        if searchText.isEmpty {
            return viewModel.categoryOrder
        }
        return viewModel.categoryOrder.filter { filteredItemsByCategory[$0] != nil }
    }
    
    var totalItemCount: Int {
        filteredItemsByCategory.values.reduce(0) { $0 + $1.count }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    tierInfoSection
                    searchBarSection
                    itemCountSection
                    itemsContentSection
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.primaryGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        viewModel.loadMenuItems(forceRefresh: true)
                        addedItemIds = Set(tier.eligibleItems.map { $0.itemId })
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Theme.primaryGold)
                    }
                }
            }
            .onAppear {
                viewModel.loadMenuItems()
                // Categories start collapsed for fast initial render
                // User can tap "Expand All" or individual categories
                addedItemIds = Set(tier.eligibleItems.map { $0.itemId })
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var tierInfoSection: some View {
        VStack(spacing: 4) {
            Text("Adding to \(tier.pointsRequired) Point Tier")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            
            Text(tier.tierName ?? "Reward Tier")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.modernSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.modernCard)
    }
    
    private var searchBarSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.modernSecondary)
            
            TextField("Search menu items...", text: $searchText)
                .foregroundColor(Theme.modernPrimary)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.modernSecondary)
                }
            }
        }
        .padding(12)
        .background(Theme.modernCard)
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    private var itemCountSection: some View {
        Group {
            if !viewModel.isLoading {
                HStack {
                    Text("\(totalItemCount) items")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.modernSecondary)
                    if !searchText.isEmpty {
                        Text("matching \"\(searchText)\"")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.primaryGold)
                    }
                    Spacer()
                    Button(action: toggleCategoryExpansion) {
                        Text(expandedCategories.count == filteredCategoryOrder.count ? "Collapse All" : "Expand All")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.primaryGold)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
    
    private var itemsContentSection: some View {
        Group {
            if viewModel.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.primaryGold)
                    Text("Loading menu items...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.modernSecondary)
                }
                Spacer()
            } else if filteredCategoryOrder.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.modernSecondary.opacity(0.5))
                    Text("No items found")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.modernSecondary)
                    if !searchText.isEmpty {
                        Text("Try a different search term")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.modernSecondary.opacity(0.7))
                    }
                }
                Spacer()
            } else {
                categoryListSection
            }
        }
    }
    
    private var categoryListSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredCategoryOrder, id: \.self) { categoryId in
                    CategorySection(
                        categoryId: categoryId,
                        items: filteredItemsByCategory[categoryId] ?? [],
                        isExpanded: expandedCategories.contains(categoryId),
                        tier: tier,
                        onToggle: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if expandedCategories.contains(categoryId) {
                                    expandedCategories.remove(categoryId)
                                } else {
                                    expandedCategories.insert(categoryId)
                                }
                            }
                        },
                        onSelectItem: { item in
                            Task {
                                await viewModel.addItemToTier(
                                    tierId: tier.id,
                                    pointsRequired: tier.pointsRequired,
                                    tierName: tier.tierName,
                                    item: item
                                )
                                if viewModel.errorMessage == nil {
                                    addedItemIds.insert(item.id)
                                    onItemAdded()
                                }
                            }
                        }
                        ,
                        isItemAdded: { item in
                            addedItemIds.contains(item.id)
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
    
    private func toggleCategoryExpansion() {
        withAnimation {
            if expandedCategories.count == filteredCategoryOrder.count {
                expandedCategories.removeAll()
            } else {
                expandedCategories = Set(filteredCategoryOrder)
            }
        }
    }
}

// MARK: - Category Section
struct CategorySection: View {
    let categoryId: String
    let items: [RewardMenuItem]
    let isExpanded: Bool
    let tier: RewardTierConfig
    let onToggle: () -> Void
    let onSelectItem: (RewardMenuItem) -> Void
    let isItemAdded: (RewardMenuItem) -> Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Category header
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(categoryId)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                        
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.modernSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.modernSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(14)
                .background(Theme.modernCard)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Items (when expanded)
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        MenuItemSelectRow(
                            item: item,
                            isAlreadyAdded: isItemAdded(item),
                            onSelect: { onSelectItem(item) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Theme.modernCardSecondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Menu Item Select Row
struct MenuItemSelectRow: View {
    let item: RewardMenuItem
    let isAlreadyAdded: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Static icon (no image loading for fast performance)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "takeoutbag.and.cup.and.straw")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.primaryGold.opacity(0.7))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.modernPrimary)
                    
                    if let price = item.price {
                        Text(String(format: "$%.2f", price))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.modernSecondary)
                    }
                }
                
                Spacer()
                
                if isAlreadyAdded {
                    Text("Added")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.2))
                        )
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.primaryGold)
                }
            }
            .padding(10)
            .background(Theme.modernCard)
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAlreadyAdded)
        .opacity(isAlreadyAdded ? 0.6 : 1)
    }
}

// MARK: - Reward Tier Config Model
struct RewardTierConfig: Identifiable, Codable {
    let id: String
    let pointsRequired: Int
    let tierName: String?
    let eligibleItems: [RewardEligibleItem]
}

// MARK: - Default Tier Definition
struct DefaultTier {
    let id: String
    let pointsRequired: Int
    let name: String
}

// MARK: - Simple Menu Item for Selection
struct RewardMenuItem: Identifiable, Codable {
    let id: String
    let displayName: String
    let price: Double?
    let imageURL: String?
    let categoryId: String?
}

// MARK: - Reward Tier Admin ViewModel
@MainActor
class RewardTierAdminViewModel: ObservableObject {
    @Published var tiers: [RewardTierConfig] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Default tiers based on the app's reward structure
    let defaultTiers: [DefaultTier] = [
        DefaultTier(id: "tier_sauce_250", pointsRequired: 250, name: "Sauce"),
        DefaultTier(id: "tier_drinks_fruit_tea_450", pointsRequired: 450, name: "Fruit Tea"),
        DefaultTier(id: "tier_drinks_milk_tea_450", pointsRequired: 450, name: "Milk Tea"),
        DefaultTier(id: "tier_drinks_lemonade_450", pointsRequired: 450, name: "Lemonade"),
        DefaultTier(id: "tier_drinks_coffee_450", pointsRequired: 450, name: "Coffee"),
        DefaultTier(id: "tier_small_appetizer_500", pointsRequired: 500, name: "Small Appetizer"),
        DefaultTier(id: "tier_large_appetizer_650", pointsRequired: 650, name: "Large Appetizer"),
        DefaultTier(id: "tier_pizza_dumplings_850", pointsRequired: 850, name: "Pizza Dumplings / Lunch Special"),
        DefaultTier(id: "tier_12piece_1500", pointsRequired: 1500, name: "12-Piece Dumplings"),
        DefaultTier(id: "tier_full_combo_2000", pointsRequired: 2000, name: "Full Combo")
    ]
    
    func loadTiers() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                guard let token = try await getAuthToken() else {
                    errorMessage = "Authentication required"
                    isLoading = false
                    return
                }
                
                let url = URL(string: "\(Config.backendURL)/admin/reward-tiers")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "RewardTierAdmin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }

                if !(200..<300).contains(httpResponse.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(
                        domain: "RewardTierAdmin",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"]
                    )
                }
                
                struct TiersResponse: Codable {
                    let tiers: [RewardTierConfig]
                }
                
                let tiersResponse = try JSONDecoder().decode(TiersResponse.self, from: data)
                self.tiers = tiersResponse.tiers
                self.isLoading = false
                
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func removeItem(from tierId: String, itemId: String) async {
        do {
            guard let token = try await getAuthToken() else {
                errorMessage = "Authentication required"
                return
            }
            
            let url = URL(string: "\(Config.backendURL)/admin/reward-tiers/\(tierId)/remove-item/\(itemId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "RewardTierAdmin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            if !(200..<300).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(
                    domain: "RewardTierAdmin",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"]
                )
            }
            
            // Reload tiers
            loadTiers()
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func getAuthToken() async throws -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDTokenResult(forcingRefresh: false).token
    }
}

// MARK: - Add Item to Tier ViewModel
@MainActor
class AddItemToTierViewModel: ObservableObject {
    @Published var itemsByCategory: [String: [RewardMenuItem]] = [:]
    @Published var categoryOrder: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let cacheManager = MenuDataCacheManager.shared
    
    var allItems: [RewardMenuItem] {
        categoryOrder.flatMap { itemsByCategory[$0] ?? [] }
    }
    
    // In-memory cache to avoid re-fetching on sheet reopen
    private static var cachedItems: [String: [RewardMenuItem]]?
    private static var cachedCategoryOrder: [String]?
    
    func loadMenuItems(forceRefresh: Bool = false) {
        // Return in-memory cache immediately if available and not forcing refresh
        if !forceRefresh, let cached = Self.cachedItems, let order = Self.cachedCategoryOrder {
            print("📦 Using in-memory cached menu items (\(cached.values.reduce(0) { $0 + $1.count }) items)")
            self.itemsByCategory = cached
            self.categoryOrder = order
            self.isLoading = false
            
            // If cache is stale, refresh in background
            if cacheManager.isRewardAddItemMenuStale() {
                Task { await fetchMenuItemsFromFirestore() }
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Cache-first: load dedicated Add Item cache for instant UI if not forcing refresh
        if !forceRefresh {
            let cacheIsFresh = !cacheManager.isRewardAddItemMenuStale()
            if cacheIsFresh {
                cacheManager.getCachedRewardAddItemMenuAsync { [weak self] cachedCategories in
                    guard let self = self else { return }
                    if let cachedCategories, !cachedCategories.isEmpty {
                        self.applyMenuCategories(cachedCategories)
                        self.isLoading = false
                        print("📦 Loaded menu items from disk cache (\(self.allItems.count) items)")
                    }
                }
                return
            } else {
                cacheManager.getCachedRewardAddItemMenuAsync { [weak self] cachedCategories in
                    guard let self = self else { return }
                    if let cachedCategories, !cachedCategories.isEmpty {
                        self.applyMenuCategories(cachedCategories)
                        print("📦 Showing stale cache while refreshing (\(self.allItems.count) items)")
                    }
                }
            }
        }
        
        Task { await fetchMenuItemsFromFirestore() }
    }
    
    private func fetchMenuItemsFromFirestore() async {
        do {
            let db = Firestore.firestore()
            
            // Get all categories
            let categoriesSnapshot = try await db.collection("menu").getDocuments()
            let categoryDocs = categoriesSnapshot.documents
            print("📂 Found \(categoryDocs.count) categories")
            
            var tempItemsByCategory: [String: [RewardMenuItem]] = [:]
            var categoriesForCache: [MenuCategory] = []
            
            // Throttled parallel fetch: process in batches of 3 to avoid network congestion
            let batchSize = 3
            
            for batchStart in stride(from: 0, to: categoryDocs.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, categoryDocs.count)
                let batch = Array(categoryDocs[batchStart..<batchEnd])
                
                // Fetch this batch in parallel
                try await withThrowingTaskGroup(of: (String, [RewardMenuItem], MenuCategory).self) { group in
                    for categoryDoc in batch {
                        let categoryId = categoryDoc.documentID
                        let categoryData = categoryDoc.data()
                        
                        group.addTask {
                            let itemsSnapshot = try await db.collection("menu")
                                .document(categoryId)
                                .collection("items")
                                .getDocuments()
                            
                            var categoryItems: [RewardMenuItem] = []
                            var cacheItems: [MenuItem] = []
                            
                            for itemDoc in itemsSnapshot.documents {
                                let data = itemDoc.data()
                                // The 'id' field IS the display name in this app's schema
                                let id = data["id"] as? String ?? itemDoc.documentID
                                let priceValue: Double? = {
                                    if let price = data["price"] as? Double { return price }
                                    if let price = data["price"] as? Int { return Double(price) }
                                    if let priceString = data["price"] as? String {
                                        return Double(priceString)
                                    }
                                    return nil
                                }()
                                
                                let rewardItem = RewardMenuItem(
                                    id: id,
                                    displayName: id,
                                    price: priceValue,
                                    imageURL: nil,  // Don't load images - not needed for selection
                                    categoryId: categoryId
                                )
                                categoryItems.append(rewardItem)
                                
                                let cacheItem = MenuItem(
                                    id: id,
                                    description: data["description"] as? String ?? "",
                                    price: priceValue ?? 0,
                                    imageURL: data["imageURL"] as? String ?? "",
                                    isAvailable: self.boolValue(data["isAvailable"], defaultValue: true),
                                    paymentLinkID: data["paymentLinkID"] as? String ?? "",
                                    isDumpling: self.boolValue(data["isDumpling"], defaultValue: false),
                                    toppingModifiersEnabled: self.boolValue(data["toppingModifiersEnabled"], defaultValue: false),
                                    milkSubModifiersEnabled: self.boolValue(data["milkSubModifiersEnabled"], defaultValue: false),
                                    availableToppingIDs: data["availableToppingIDs"] as? [String] ?? [],
                                    availableMilkSubIDs: data["availableMilkSubIDs"] as? [String] ?? [],
                                    allergyTagIDs: data["allergyTagIDs"] as? [String] ?? [],
                                    category: data["category"] as? String ?? categoryId
                                )
                                cacheItems.append(cacheItem)
                            }
                            
                            // Sort items within category alphabetically
                            let sortedRewardItems = categoryItems.sorted { $0.displayName < $1.displayName }
                            let menuCategory = MenuCategory(
                                id: categoryId,
                                items: cacheItems,
                                subCategories: nil,
                                isDrinks: categoryData["isDrinks"] as? Bool ?? false,
                                lemonadeSodaEnabled: categoryData["lemonadeSodaEnabled"] as? Bool ?? false,
                                isToppingCategory: categoryData["isToppingCategory"] as? Bool ?? false,
                                icon: categoryData["icon"] as? String ?? "",
                                hideIcon: categoryData["hideIcon"] as? Bool ?? false
                            )
                            
                            return (categoryId, sortedRewardItems, menuCategory)
                        }
                    }
                    
                    // Collect results from this batch
                    for try await (categoryId, items, categoryCache) in group {
                        if !items.isEmpty {
                            tempItemsByCategory[categoryId] = items
                            categoriesForCache.append(categoryCache)
                            print("  📋 Category '\(categoryId)': \(items.count) items")
                        }
                    }
                }
            }
            
            // Sort categories alphabetically
            let tempCategoryOrder = tempItemsByCategory.keys.sorted()
            
            // Cache for future opens (memory + disk)
            Self.cachedItems = tempItemsByCategory
            Self.cachedCategoryOrder = tempCategoryOrder
            cacheManager.cacheRewardAddItemMenu(categoriesForCache)
            
            self.itemsByCategory = tempItemsByCategory
            self.categoryOrder = tempCategoryOrder
            self.isLoading = false
            
            let totalItems = tempItemsByCategory.values.reduce(0) { $0 + $1.count }
            print("✅ Loaded \(totalItems) items across \(tempCategoryOrder.count) categories")
            
        } catch {
            print("❌ Error loading menu items: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    private func applyMenuCategories(_ categories: [MenuCategory]) {
        var tempItemsByCategory: [String: [RewardMenuItem]] = [:]
        
        for category in categories {
            let items = (category.items ?? []).map { menuItem in
                RewardMenuItem(
                    id: menuItem.id,
                    displayName: menuItem.id,
                    price: menuItem.price,
                    imageURL: nil,
                    categoryId: category.id
                )
            }
            if !items.isEmpty {
                tempItemsByCategory[category.id] = items.sorted { $0.displayName < $1.displayName }
            }
        }
        
        let tempCategoryOrder = tempItemsByCategory.keys.sorted()
        Self.cachedItems = tempItemsByCategory
        Self.cachedCategoryOrder = tempCategoryOrder
        self.itemsByCategory = tempItemsByCategory
        self.categoryOrder = tempCategoryOrder
    }
    
    nonisolated private func boolValue(_ value: Any?, defaultValue: Bool) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let intValue = value as? Int { return intValue != 0 }
        if let stringValue = value as? String {
            return (stringValue as NSString).boolValue
        }
        return defaultValue
    }
    
    func addItemToTier(tierId: String, pointsRequired: Int, tierName: String?, item: RewardMenuItem) async {
        do {
            guard let token = try await getAuthToken() else {
                errorMessage = "Authentication required"
                return
            }
            
            let url = URL(string: "\(Config.backendURL)/admin/reward-tiers/\(tierId)/add-item")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let body: [String: Any] = [
                "tierName": tierName ?? "",
                "pointsRequired": pointsRequired,
                "itemId": item.id,
                "itemName": item.displayName,
                "categoryId": item.categoryId ?? "",
                "imageURL": item.imageURL ?? ""
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "AddItemToTier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if !(200..<300).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(
                    domain: "AddItemToTier",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"]
                )
            }
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func getAuthToken() async throws -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDTokenResult(forcingRefresh: false).token
    }
}

// MARK: - Preview
struct RewardTierAdminView_Previews: PreviewProvider {
    static var previews: some View {
        RewardTierAdminView()
    }
}
