import SwiftUI

// MARK: - Menu Search View (Theme-matched)
struct SearchView: View {
    @EnvironmentObject var menuVM: MenuViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [MenuItem] {
        let q = normalizedQuery
        guard !q.isEmpty else { return [] }

        return menuVM.allMenuItems.filter { item in
            item.id.localizedCaseInsensitiveContains(q) ||
            item.description.localizedCaseInsensitiveContains(q) ||
            item.category.localizedCaseInsensitiveContains(q)
        }
    }

    private var emptyStateCategorySuggestions: [String] {
        // Prefer the canonical category list if available.
        let fromCategories = menuVM.orderedMenuCategories.map(\.id).filter { !$0.isEmpty }
        if !fromCategories.isEmpty { return Array(fromCategories.prefix(10)) }

        // Fallback: derive from items.
        let derived = Array(Set(menuVM.allMenuItems.map(\.category).filter { !$0.isEmpty })).sorted()
        return Array(derived.prefix(10))
    }

    private let popularSearches: [String] = [
        "dumplings",
        "boba",
        "appetizers",
        "spicy",
        "vegetarian",
        "drinks"
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.96),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if normalizedQuery.isEmpty {
                        emptyState
                    } else if filteredItems.isEmpty {
                        noResultsState
                    } else {
                        resultsList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            // If user tapped search icon, go straight into typing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSearchFocused = true
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.darkGoldGradient)
                        .frame(width: 34, height: 34)
                        .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                }

                TextField("Search the menu…", text: $searchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .submitLabel(.search)

                Spacer()

                if !normalizedQuery.isEmpty {
                    Text("\(filteredItems.count)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Theme.lightGold)
                        )
                        .accessibilityLabel("\(filteredItems.count) results")
                        .transition(.scale.combined(with: .opacity))
                }

                if !searchText.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            searchText = ""
                        }
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
            )

            if normalizedQuery.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.primaryGold)

                    Text("Try: dumplings, boba, drinks…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))

                    Spacer()
                }
                .padding(.horizontal, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: searchText)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Popular searches")
            chipRow(items: popularSearches) { term in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    searchText = term
                }
                isSearchFocused = true
            }

            if !emptyStateCategorySuggestions.isEmpty {
                sectionTitle("Browse by category")
                chipRow(items: emptyStateCategorySuggestions) { category in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        searchText = category
                    }
                    isSearchFocused = true
                }
            }

            VStack(spacing: 10) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(Theme.darkGoldGradient)

                Text("Find your next favorite")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Text("Search by item name, category, or keywords in the description.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .padding(.top, 8)
    }

    // MARK: - Results
    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Results")

            LazyVStack(spacing: 12) {
                ForEach(filteredItems) { item in
                    NavigationLink {
                        ItemDetailView(item: item, menuVM: menuVM)
                    } label: {
                        SearchResultRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.45))

            Text("No results")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text("We couldn’t find anything for “\(normalizedQuery)”. Try a different keyword.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Reusable UI
    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundColor(.white.opacity(0.62))
            .tracking(1.1)
            .padding(.horizontal, 4)
    }

    private func chipRow(items: [String], onTap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    Button {
                        onTap(item)
                    } label: {
                        Text(item)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(
                                        Capsule()
                                            .stroke(Theme.primaryGold.opacity(0.22), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Search Result Row
private struct SearchResultRow: View {
    let item: MenuItem

    private var displayName: String { item.id }

    private var displaySubtitle: String {
        let trimmed = item.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tap to view details" }
        return trimmed
    }

    var body: some View {
        HStack(spacing: 14) {
            leadingIcon

            VStack(alignment: .leading, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(displaySubtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.70))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Theme.lightGold)
                            )
                    }

                    Text(String(format: "$%.2f", item.price))
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Theme.lightGold)

                    Spacer()
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 8)
        )
        .contentShape(Rectangle())
    }

    private var leadingIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.primaryGold.opacity(0.18), lineWidth: 1)
                )

            Image(systemName: iconName)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Theme.darkGoldGradient)
        }
        .frame(width: 48, height: 48)
    }

    private var iconName: String {
        let key = item.category.lowercased()
        if key.contains("drink") || key.contains("tea") || key.contains("coffee") || key.contains("boba") || key.contains("lemonade") || key.contains("coke") {
            return "cup.and.saucer.fill"
        }
        if key.contains("soup") {
            return "drop.fill"
        }
        if key.contains("sauce") {
            return "takeoutbag.and.cup.and.straw.fill"
        }
        if key.contains("appetizer") {
            return "leaf.fill"
        }
        if key.contains("dessert") {
            return "birthday.cake.fill"
        }
        if key.contains("dumpling") {
            return "sparkles"
        }
        return "fork.knife"
    }
}

#Preview {
    NavigationView {
        SearchView()
            .environmentObject(MenuViewModel())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
    }
}