import SwiftUI
import Kingfisher
import FirebaseFirestore

// MARK: - Item Detail View
struct ItemDetailView: View {
    let item: MenuItem
    let menuVM: MenuViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedCookingStyle = "Steamed"
    @State private var selectedToppings: [String] = []
    @State private var selectedMilkSubs: [String] = []
    @State private var quantity = 1
    @State private var showToppingsModal = false
    @State private var showSafariView = false
    @State private var showToppingCategorySheet = false
    
    private var imageURL: URL? {
        // Handle empty URLs
        guard !item.imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        // Handle Firebase Storage URLs
        if item.imageURL.hasPrefix("gs://") {
            // Convert gs:// URL to proper Firebase Storage download URL
            // Format: gs://bucket-name/path/to/file
            // Convert to: https://firebasestorage.googleapis.com/v0/b/bucket-name/o/path%2Fto%2Ffile?alt=media
            
            let components = item.imageURL.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                
                // Better URL encoding for Firebase Storage
                let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                let downloadURL = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
                
                return URL(string: downloadURL)
            } else {
                return nil
            }
        } else if item.imageURL.hasPrefix("https://firebasestorage.googleapis.com") {
            // Already a Firebase Storage URL
            return URL(string: item.imageURL)
        } else if item.imageURL.hasPrefix("http") {
            // Regular URL
            return URL(string: item.imageURL)
        } else {
            // Invalid or empty URL
            return nil
        }
    }
    
    private var totalPrice: Double {
        let toppingPrice = selectedToppings.compactMap { toppingID in
            menuVM.drinkOptions.first(where: { $0.id == toppingID && !$0.isMilkSub })?.price
        }.reduce(0, +)
        
        let milkSubPrice = selectedMilkSubs.compactMap { milkID in
            menuVM.drinkOptions.first(where: { $0.id == milkID && $0.isMilkSub })?.price
        }.reduce(0, +)
        
        return (item.price + toppingPrice + milkSubPrice) * Double(quantity)
    }
    
    private var availableToppings: [DrinkOption] {
        item.availableToppingIDs.compactMap { toppingID in
            menuVM.drinkOptions.first(where: { $0.id == toppingID && !$0.isMilkSub })
        }
    }
    
    private var availableMilkSubs: [DrinkOption] {
        item.availableMilkSubIDs.compactMap { milkID in
            menuVM.drinkOptions.first(where: { $0.id == milkID && $0.isMilkSub })
        }
    }

    private var isLemonadeSodaEnabledForItem: Bool {
        // Prefer explicit item.category match
        if !item.category.isEmpty, let cat = menuVM.menuCategories.first(where: { $0.id == item.category }) {
            return cat.lemonadeSodaEnabled
        }
        // Fallback: locate the category containing this item
        for category in menuVM.menuCategories {
            if let items = category.items, items.contains(where: { $0.id == item.id }) {
                return category.lemonadeSodaEnabled
            }
        }
        return false
    }

    private var isDrinksCategoryForItem: Bool {
        // Prefer explicit item.category match
        if !item.category.isEmpty, let cat = menuVM.menuCategories.first(where: { $0.id == item.category }) {
            return cat.isDrinks
        }
        // Fallback: locate the category containing this item
        for category in menuVM.menuCategories {
            if let items = category.items, items.contains(where: { $0.id == item.id }) {
                return category.isDrinks
            }
        }
        return false
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                if isDrinksCategoryForItem {
                    // Simplified drink layout: no hero image, larger title
                    drinkContentSection
                } else {
                    // Standard layout with hero image
                    heroImageSection
                    
                    // Scrollable content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            titleSection
                            scrollCueSection

                            // Description (larger, under the down arrow)
                            if !item.description.isEmpty {
                                descriptionSection
                            }
                            
                            // Allergy Info chips
                            allergyInfoSection
                            
                            if item.isDumpling {
                                quantitySection
                                cookingStyleSection
                            }
                            
                            // Lemonade/Soda indicator (non-interactive) above CTA
                            if isLemonadeSodaEnabledForItem {
                                lemonadeSodaIndicatorRow
                            }
                            
                            // Drink options
                            drinkOptionsSection
                            
                            // Spacer for bottom bar overlap
                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                    .background(Color.black)
                }
                
                // Sticky bottom bar
                bottomBarSection
            }
            
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .transition(.opacity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: true)
        .sheet(isPresented: $showToppingsModal) {
            ToppingsSelectionModal(
                availableToppings: availableToppings,
                selectedToppings: $selectedToppings
            )
        }
        .sheet(isPresented: $showSafariView) {
            if let url = URL(string: "https://dumplinghousetn.kwickmenu.com/") {
                SimplifiedSafariView(
                    url: url,
                    onDismiss: { showSafariView = false }
                )
            }
        }
        .sheet(isPresented: $showToppingCategorySheet) {
            if let toppingsCategory = menuVM.toppingsCategory {
                NavigationView {
                    CategoryDetailView(
                        category: toppingsCategory,
                        menuVM: menuVM,
                        showAdminTools: .constant(false)
                    )
                }
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - View Components
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.id)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1) // Add shadow for better readability
        }
        .padding(.vertical, 4)
    }
    
    // priceSection removed; price is shown in sticky bottom bar
    
    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quantity")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            HStack {
                Button(action: {
                    if quantity > 1 {
                        quantity -= 1
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                Text("\(quantity)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 40)
                Button(action: {
                    quantity += 1
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                Spacer()
            }
        }
    }
    
    private var cookingStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cooking Style")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Picker("Cooking Style", selection: $selectedCookingStyle) {
                Text("Steamed").tag("Steamed")
                Text("Fried").tag("Fried")
                Text("Boiled").tag("Boiled")
            }
            .pickerStyle(SegmentedPickerStyle())
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        }
    }
    
    private var scrollCueSection: some View {
        HStack {
            Spacer()
            Image(systemName: "chevron.compact.down")
                .foregroundColor(.gray)
                .font(.system(size: 16, weight: .medium))
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var descriptionSection: some View {
        Text(item.description)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white.opacity(0.85))
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 1)
            .padding(.top, -6)
    }
    
    private var allergyInfoSection: some View {
        let tagById = Dictionary(uniqueKeysWithValues: menuVM.allergyTags.map { ($0.id, $0) })
        let tags: [AllergyTag] = item.allergyTagIDs.compactMap { tagById[$0] }.filter { $0.isAvailable }
        
        return Group {
            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Allergy Info")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(tags) { tag in
                            AllergyTagPill(title: tag.title, color: allergyColor(for: tag.id))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func allergyColor(for tagId: String) -> Color {
        // Deterministic across runs (avoid Swift's randomized hashValue).
        let sum = tagId.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette: [Color] = [
            .red, .orange, .yellow, .green, .mint, .cyan, .blue, .indigo, .purple, .pink
        ]
        return palette[sum % palette.count]
    }
    
    private var drinkOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.toppingModifiersEnabled {
                toppingsSection
            }
            if item.milkSubModifiersEnabled {
                milkSubsSection
            }
        }
    }
    
    private var toppingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Toppings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            if availableToppings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No toppings available for this drink")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.vertical, 8)
                    
                    // Debug information
                    #if DEBUG
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debug Info:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                        Text("toppingModifiersEnabled: \(item.toppingModifiersEnabled)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("availableToppingIDs: \(item.availableToppingIDs)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Toppings in drink options: \(menuVM.drinkOptions.filter { !$0.isMilkSub }.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    #endif
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableToppings.prefix(4), id: \.id) { toppingOption in
                            toppingCard(toppingOption)
                        }
                        if availableToppings.count > 4 {
                            viewMoreToppingsButton
                        }
                    }
                }
            }
        }
    }
    
    private var milkSubsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milk Substitutions (Optional)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            if availableMilkSubs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No milk substitutions available for this drink")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.vertical, 8)
                    
                    // Debug information
                    #if DEBUG
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debug Info:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                        Text("milkSubModifiersEnabled: \(item.milkSubModifiersEnabled)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("availableMilkSubIDs: \(item.availableMilkSubIDs)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Total drink options: \(menuVM.drinkOptions.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Milk subs in drink options: \(menuVM.drinkOptions.filter { $0.isMilkSub }.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                    #endif
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableMilkSubs, id: \.id) { milkOption in
                            milkSubCard(milkOption)
                        }
                    }
                }
            }
        }
    }
    
    // orderOnlineSection removed; use bottomBarSection instead
    
    private var floatingImageSection: some View {
        Group {
            if let imageURL = imageURL {
                KFImage(imageURL)
                    .resizable()
                    .placeholder {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                    .onFailure { _ in
                        // Handle image loading failure
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .background(Color.clear)
                    .zIndex(2)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No image")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .frame(width: 160, height: 160)
                    .zIndex(2)
            }
        }
    }

    // MARK: - New Sections
    private var heroImageSection: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let imageURL = imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                } else {
                    Color.black
                        .frame(height: 200)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .frame(height: 80)
        }
    }
    
    // MARK: - Drink Content Section (for categories with isDrinks=true)
    private var drinkContentSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Large prominent title with space for close button
                Text(item.id)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .padding(.top, 60) // Space for close button
                
                // Description
                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 1)
                }
                
                // Allergy info
                allergyInfoSection
                
                // View Topping Options button (opens toppings category sheet)
                if menuVM.toppingsCategory != nil {
                    Button(action: { showToppingCategorySheet = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 16, weight: .bold))
                            Text("View Topping Options")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6).opacity(0.35))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Bottom spacing for sticky bar
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black)
    }
    
    private var bottomBarSection: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(String(format: "$%.2f", totalPrice))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { showSafariView = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .bold))
                        Text("Order Online")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.red)
                            .shadow(color: Color.red.opacity(0.35), radius: 10, x: 0, y: 5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.95).ignoresSafeArea(edges: .bottom))
        }
    }

    private var lemonadeSodaIndicatorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick one: Lemonade OR Soda")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            HStack(spacing: 12) {
                // Lemonade chip
                HStack(spacing: 8) {
                    Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    Text("Lemonade")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.8), lineWidth: 1.5)
                        .fill(Color.clear)
                )
                // OR
                Text("OR")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 4)
                // Soda chip
                HStack(spacing: 8) {
                    Circle().fill(Color.cyan).frame(width: 8, height: 8)
                    Text("Soda")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cyan.opacity(0.85), lineWidth: 1.5)
                        .fill(Color.clear)
                )
                Spacer()
            }
        }
        .padding(.vertical, 6)
        .padding(.top, 4)
        .allowsHitTesting(false)
    }
    
    private var viewMoreToppingsButton: some View {
        Button(action: { showToppingsModal = true }) {
            VStack(spacing: 4) {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.blue)
                    .font(.system(size: 18, weight: .medium))
                Text("View all \(availableToppings.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: 80, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    private func toppingCard(_ topping: DrinkOption) -> some View {
        Button(action: {
            if selectedToppings.contains(topping.id) {
                selectedToppings.removeAll { $0 == topping.id }
            } else {
                selectedToppings.append(topping.id)
            }
        }) {
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: selectedToppings.contains(topping.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedToppings.contains(topping.id) ? .green : .gray)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
                Text(topping.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if topping.price > 0 {
                    Text(String(format: "+$%.2f", topping.price))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: 80, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedToppings.contains(topping.id) ? Color.green.opacity(0.2) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedToppings.contains(topping.id) ? Color.green : Color.clear, lineWidth: 1.5)
                    )
            )
        }
    }
    
    private func milkSubCard(_ milkOption: DrinkOption) -> some View {
        Button(action: {
            if selectedMilkSubs.contains(milkOption.id) {
                selectedMilkSubs.removeAll { $0 == milkOption.id }
            } else {
                selectedMilkSubs.removeAll()
                selectedMilkSubs.append(milkOption.id)
            }
        }) {
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: selectedMilkSubs.contains(milkOption.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedMilkSubs.contains(milkOption.id) ? .green : .gray)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
                Text(milkOption.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if milkOption.price > 0 {
                    Text(String(format: "+$%.2f", milkOption.price))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: 80, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedMilkSubs.contains(milkOption.id) ? Color.green.opacity(0.2) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedMilkSubs.contains(milkOption.id) ? Color.green : Color.clear, lineWidth: 1.5)
                    )
            )
        }
    }
}

// MARK: - Toppings Selection Modal
struct ToppingsSelectionModal: View {
    let availableToppings: [DrinkOption]
    @Binding var selectedToppings: [String]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 16) {
                        Text("Select Toppings")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Choose from \(availableToppings.count) available toppings")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    // Toppings List
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(availableToppings, id: \.id) { topping in
                                Button(action: {
                                    if selectedToppings.contains(topping.id) {
                                        selectedToppings.removeAll { $0 == topping.id }
                                    } else {
                                        selectedToppings.append(topping.id)
                                    }
                                }) {
                                    HStack(spacing: 16) {
                                        // Checkbox
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(selectedToppings.contains(topping.id) ? Color.blue : Color(.systemGray5))
                                                .frame(width: 24, height: 24)
                                            if selectedToppings.contains(topping.id) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        // Topping Info
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(topping.name)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.primary)
                                            if topping.price > 0 {
                                                Text("+$\(String(format: "%.2f", topping.price))")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                    // Bottom Section
                    VStack(spacing: 16) {
                        if !selectedToppings.isEmpty {
                            Text("\(selectedToppings.count) topping\(selectedToppings.count == 1 ? "" : "s") selected")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Done")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// VisualEffectBlur helper for background blur
import UIKit
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - Allergy Tag Pill
private struct AllergyTagPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                Capsule()
                    .fill(color.opacity(0.22))
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.55), lineWidth: 1.2)
                    )
            )
    }
}
