import SwiftUI
import Combine

// MARK: - Advanced Search System (Simplified - No Voice Search)
class AdvancedSearchManager: ObservableObject {
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var searchResults: [SearchMenuItem] = []
    @Published var searchSuggestions: [String] = []
    @Published var recentSearches: [String] = []
    @Published var selectedFilters: Set<SearchFilter> = []
    @Published var sortOption: SortOption = .relevance
    @Published var aiRecommendations: [SearchMenuItem] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    // Menu data - empty by default (this view is not currently connected to the app)
    // In production, this would be populated from the real menu data source
    private let menuItems: [SearchMenuItem] = []
    
    init() {
        setupSearchSubscriptions()
        loadRecentSearches()
        generateAIRecommendations()
    }
    
    private func setupSearchSubscriptions() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] searchTerm in
                self?.performSearch(query: searchTerm)
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(query: String) {
        isSearching = true
        
        // Simulate search delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isSearching = false
            if query.isEmpty {
                self?.searchResults = []
            } else {
                self?.searchResults = self?.menuItems.filter { item in
                    item.name.localizedCaseInsensitiveContains(query) ||
                    item.description.localizedCaseInsensitiveContains(query) ||
                    item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
                } ?? []
            }
        }
    }
    
    func addRecentSearch(_ query: String) {
        guard !query.isEmpty else { return }
        
        if let index = recentSearches.firstIndex(of: query) {
            recentSearches.remove(at: index)
        }
        
        recentSearches.insert(query, at: 0)
        
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        
        saveRecentSearches()
    }
    
    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "recent_searches") ?? []
    }
    
    private func saveRecentSearches() {
        UserDefaults.standard.set(recentSearches, forKey: "recent_searches")
    }
    
    private func generateAIRecommendations() {
        // Simplified AI recommendations
        aiRecommendations = Array(menuItems.shuffled().prefix(3))
    }
    
    func toggleFilter(_ filter: SearchFilter) {
        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
        } else {
            selectedFilters.insert(filter)
        }
        performSearch(query: searchText)
    }
    
    private func applySortingAndFilters(to items: [SearchMenuItem]) -> [SearchMenuItem] {
        var filtered = items
        
        // Apply filters
        for filter in selectedFilters {
            switch filter {
            case .category(let category):
                filtered = filtered.filter { $0.category == category }
            case .priceRange(let range):
                filtered = filtered.filter { range.contains($0.price) }
            case .dietary:
                break // Implement dietary filtering as needed
            }
        }
        
        // Apply sorting
        switch sortOption {
        case .relevance:
            break // Already sorted by relevance in search
        case .price:
            filtered.sort { $0.price < $1.price }
        case .name:
            filtered.sort { $0.name < $1.name }
        case .rating:
            filtered.sort { $0.rating > $1.rating }
        case .popularity:
            filtered.shuffle() // Simplified popularity
        }
        
        return filtered
    }
}

// MARK: - Search Filter Types
enum SearchFilter: Hashable {
    case category(SearchCategory)
    case priceRange(ClosedRange<Double>)
    case dietary(DietaryRestriction)
}

enum SortOption: String, CaseIterable {
    case relevance = "Relevance"
    case price = "Price"
    case name = "Name"
    case rating = "Rating"
    case popularity = "Popularity"
}

enum DietaryRestriction: String, CaseIterable {
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case glutenFree = "Gluten-Free"
    case dairyFree = "Dairy-Free"
    case nutFree = "Nut-Free"
}

// MARK: - Search Menu Item Model
struct SearchMenuItem: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let price: Double
    let category: SearchCategory
    let tags: [String]
    let rating: Double = Double.random(in: 3.5...5.0)
}

enum SearchCategory: String, CaseIterable {
    case appetizer = "Appetizers"
    case main = "Main Dishes"
    case dessert = "Desserts"
    case drinks = "Drinks"
}

// MARK: - Advanced Search View
struct AdvancedSearchView: View {
    @StateObject private var searchManager = AdvancedSearchManager()
    @State private var showFilters = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Header
                VStack(spacing: 16) {
                    // Search Bar
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16, weight: .medium))
                            
                            TextField("Search menu items...", text: $searchManager.searchText)
                                .font(.system(size: 16, weight: .medium))
                                .onSubmit {
                                    searchManager.addRecentSearch(searchManager.searchText)
                                }
                            
                            if !searchManager.searchText.isEmpty {
                                Button(action: {
                                    searchManager.searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16, weight: .medium))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                        
                        // Filter Button
                        Button(action: { showFilters.toggle() }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Active Filters
                    if !searchManager.selectedFilters.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(searchManager.selectedFilters), id: \.self) { filter in
                                    FilterTag(filter: filter) {
                                        searchManager.toggleFilter(filter)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .background(Color(.systemBackground))
                
                Divider()
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if searchManager.searchText.isEmpty {
                            // Show recent searches and AI recommendations
                            if !searchManager.recentSearches.isEmpty {
                                RecentSearchesSection(
                                    searches: searchManager.recentSearches
                                ) { search in
                                    searchManager.searchText = search
                                }
                            }
                            
                            if !searchManager.aiRecommendations.isEmpty {
                                AIRecommendationsSection(
                                    recommendations: searchManager.aiRecommendations
                                )
                            }
                        } else {
                            // Show search results
                            if searchManager.isSearching {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Spacer()
                                }
                                .padding()
                            } else if searchManager.searchResults.isEmpty {
                                EmptySearchResults(searchText: searchManager.searchText)
                            } else {
                                SearchResultsSection(results: searchManager.searchResults)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showFilters) {
                SearchFiltersView(searchManager: searchManager)
            }
        }
    }
}

// MARK: - Supporting Views
struct FilterTag: View {
    let filter: SearchFilter
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(filterTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var filterTitle: String {
        switch filter {
        case .category(let category):
            return category.rawValue
        case .priceRange(let range):
            return "$\(Int(range.lowerBound))-\(Int(range.upperBound))"
        case .dietary(let restriction):
            return restriction.rawValue
        }
    }
}

struct RecentSearchesSection: View {
    let searches: [String]
    let onSearchTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Searches")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(searches, id: \.self) { search in
                    Button(action: { onSearchTap(search) }) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))
                            
                            Text(search)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.left")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                    }
                }
            }
        }
    }
}

struct AIRecommendationsSection: View {
    let recommendations: [SearchMenuItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🤖 AI Recommendations")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(recommendations) { item in
                    RecommendationCard(item: item) {
                        // Handle item tap
                    }
                }
            }
        }
    }
}

struct RecommendationCard: View {
    let item: SearchMenuItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(item.description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("$\(String(format: "%.2f", item.price))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(item.category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

struct SearchResultsSection: View {
    let results: [SearchMenuItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search Results (\(results.count))")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                Spacer()
            }
            
            LazyVStack(spacing: 8) {
                ForEach(results) { item in
                        AdvancedSearchResultCard(item: item)
                }
            }
        }
    }
}

struct AdvancedSearchResultCard: View {
    let item: SearchMenuItem
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Text(item.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(item.category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.1))
                        )
                    
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        
                        Text(String(format: "%.1f", item.rating))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text("$\(String(format: "%.2f", item.price))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

struct EmptySearchResults: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No results found")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("We couldn't find anything for \"\(searchText)\"")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Try searching with different keywords")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
    }
}

struct SearchFiltersView: View {
    @ObservedObject var searchManager: AdvancedSearchManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Categories
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Categories")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(SearchCategory.allCases, id: \.self) { category in
                                FilterToggle(
                                    title: category.rawValue,
                                    isSelected: searchManager.selectedFilters.contains(.category(category))
                                ) {
                                    searchManager.toggleFilter(.category(category))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider()
                    
                    // Price Range
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Price Range")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            FilterToggle(
                                title: "$0 - $15",
                                isSelected: searchManager.selectedFilters.contains(.priceRange(0...15))
                            ) {
                                searchManager.toggleFilter(.priceRange(0...15))
                            }
                            
                            FilterToggle(
                                title: "$15 - $30",
                                isSelected: searchManager.selectedFilters.contains(.priceRange(15...30))
                            ) {
                                searchManager.toggleFilter(.priceRange(15...30))
                            }
                            
                            FilterToggle(
                                title: "$30+",
                                isSelected: searchManager.selectedFilters.contains(.priceRange(30...999))
                            ) {
                                searchManager.toggleFilter(.priceRange(30...999))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FilterToggle: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
} 