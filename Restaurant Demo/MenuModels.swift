import Foundation

// Represents a single item on your menu.
struct MenuItem: Codable, Identifiable, Hashable {
    var id: String
    var description: String
    var price: Double
    var imageURL: String
    var isAvailable: Bool
    // ✅ NEW: The ID for the Stripe Payment Link for this item.
    var paymentLinkID: String
    var isDumpling: Bool = false // New property, default false
    // Drink-related properties
    var toppingModifiersEnabled: Bool = false
    var milkSubModifiersEnabled: Bool = false
    var availableToppingIDs: [String] = [] // IDs of enabled toppings for this item
    var availableMilkSubIDs: [String] = [] // IDs of enabled milk subs for this item
    var allergyTagIDs: [String] = [] // IDs of reusable allergy tags applied to this item
    var category: String = "" // Category for the item (e.g., "Dumplings", "Appetizers", "Drinks")

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case price
        case imageURL
        case isAvailable
        case paymentLinkID
        case isDumpling
        case toppingModifiersEnabled
        case milkSubModifiersEnabled
        case availableToppingIDs
        case availableMilkSubIDs
        case allergyTagIDs
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        price = try container.decode(Double.self, forKey: .price)
        imageURL = try container.decode(String.self, forKey: .imageURL)
        isAvailable = MenuItem.decodeBoolOrInt(container: container, key: .isAvailable, defaultValue: true)
        paymentLinkID = try container.decodeIfPresent(String.self, forKey: .paymentLinkID) ?? ""
        isDumpling = MenuItem.decodeBoolOrInt(container: container, key: .isDumpling, defaultValue: false)
        toppingModifiersEnabled = MenuItem.decodeBoolOrInt(container: container, key: .toppingModifiersEnabled, defaultValue: false)
        milkSubModifiersEnabled = MenuItem.decodeBoolOrInt(container: container, key: .milkSubModifiersEnabled, defaultValue: false)
        availableToppingIDs = try container.decodeIfPresent([String].self, forKey: .availableToppingIDs) ?? []
        availableMilkSubIDs = try container.decodeIfPresent([String].self, forKey: .availableMilkSubIDs) ?? []
        allergyTagIDs = try container.decodeIfPresent([String].self, forKey: .allergyTagIDs) ?? []
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
    }

    private static func decodeBoolOrInt(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys, defaultValue: Bool) -> Bool {
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return boolValue ?? defaultValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return (intValue ?? 0) != 0
        }
        return defaultValue
    }

    // Memberwise initializer for use in code
    init(
        id: String,
        description: String,
        price: Double,
        imageURL: String,
        isAvailable: Bool,
        paymentLinkID: String,
        isDumpling: Bool = false,
        toppingModifiersEnabled: Bool = false,
        milkSubModifiersEnabled: Bool = false,
        availableToppingIDs: [String] = [],
        availableMilkSubIDs: [String] = [],
        allergyTagIDs: [String] = [],
        category: String = ""
    ) {
        self.id = id
        self.description = description
        self.price = price
        self.imageURL = imageURL
        self.isAvailable = isAvailable
        self.paymentLinkID = paymentLinkID
        self.isDumpling = isDumpling
        self.toppingModifiersEnabled = toppingModifiersEnabled
        self.milkSubModifiersEnabled = milkSubModifiersEnabled
        self.availableToppingIDs = availableToppingIDs
        self.availableMilkSubIDs = availableMilkSubIDs
        self.allergyTagIDs = allergyTagIDs
        self.category = category
    }
    
    // Computed property to resolve image URL for AsyncImage
    var resolvedImageURL: URL? {
        if imageURL.hasPrefix("gs://") {
            let components = imageURL.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                
                // Construct proper Firebase Storage URL
                let urlString = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
                
                if let url = URL(string: urlString) {
                    print("✅ Resolved gs:// URL: \(urlString)")
                    return url
                } else {
                    print("❌ Failed to construct URL from: \(urlString)")
                }
            }
        } else if imageURL.hasPrefix("http") {
            return URL(string: imageURL)
        }
        return nil
    }
}

// The rest of the file (MenuSubCategory, MenuCategory) remains the same.
// ...
struct MenuSubCategory: Codable, Identifiable, Hashable {
    var id: String
    var items: [MenuItem]
}

struct MenuCategory: Codable, Identifiable, Hashable {
    var id: String
    var items: [MenuItem]?
    var subCategories: [MenuSubCategory]?
    var isDrinks: Bool = false
    var lemonadeSodaEnabled: Bool = false
    var isToppingCategory: Bool = false
    var icon: String = "" // emoji or PNG URL (gs:// or https)
    var hideIcon: Bool = false // when true, category displays as text-only (no uploaded icon or built-in defaults)
}

// Global reusable allergy tag (applied to menu items)
struct AllergyTag: Codable, Identifiable, Hashable {
    var id: String // unique
    var title: String // bubble text
    var isAvailable: Bool // global availability
    var order: Int // for ordering in admin UI
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isAvailable
        case order
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
    
    init(id: String, title: String, isAvailable: Bool = true, order: Int = 0) {
        self.id = id
        self.title = title
        self.isAvailable = isAvailable
        self.order = order
    }
}

// Global drink option (topping or milk sub)
struct DrinkOption: Codable, Identifiable, Hashable {
    var id: String // unique
    var name: String
    var price: Double
    var isMilkSub: Bool // true for milk sub, false for topping
    var isAvailable: Bool // global availability (can be used for future global toggling)
    var order: Int // for reordering in admin UI
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case price
        case isMilkSub
        case isAvailable
        case order
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Double.self, forKey: .price)
        isMilkSub = try container.decode(Bool.self, forKey: .isMilkSub)
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
    
    init(id: String, name: String, price: Double, isMilkSub: Bool, isAvailable: Bool, order: Int = 0) {
        self.id = id
        self.name = name
        self.price = price
        self.isMilkSub = isMilkSub
        self.isAvailable = isAvailable
        self.order = order
    }
}

// Drink flavor for Lemonades and Sodas
struct DrinkFlavor: Codable, Identifiable, Hashable {
    var id: String // unique
    var name: String
    var isLemonade: Bool // true for lemonade, false for soda
    var isAvailable: Bool
    var order: Int // for reordering in admin UI
    var icon: String // emoji or PNG URL
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isLemonade
        case isAvailable
        case order
        case icon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isLemonade = try container.decode(Bool.self, forKey: .isLemonade)
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
    }
    
    init(id: String, name: String, isLemonade: Bool, isAvailable: Bool, order: Int = 0, icon: String = "") {
        self.id = id
        self.name = name
        self.isLemonade = isLemonade
        self.isAvailable = isAvailable
        self.order = order
        self.icon = icon
    }
    
    // Computed property to resolve icon URL for AsyncImage
    var resolvedIconURL: URL? {
        if icon.hasPrefix("gs://") {
            let components = icon.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                
                // Construct proper Firebase Storage URL
                let urlString = "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media"
                
                if let url = URL(string: urlString) {
                    return url
                } else {
                    print("❌ Failed to construct URL from: \(urlString)")
                }
            }
        } else if icon.hasPrefix("http") {
            return URL(string: icon)
        }
        return nil
    }
}

// Drink-specific toppings for Lemonades and Sodas
struct DrinkTopping: Codable, Identifiable, Hashable {
    var id: String // unique
    var name: String
    var price: Double
    var isAvailable: Bool
    var order: Int // for reordering in admin UI
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case price
        case isAvailable
        case order
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decode(Double.self, forKey: .price)
        isAvailable = try container.decode(Bool.self, forKey: .isAvailable)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
    
    init(id: String, name: String, price: Double, isAvailable: Bool, order: Int = 0) {
        self.id = id
        self.name = name
        self.price = price
        self.isAvailable = isAvailable
        self.order = order
    }
}
