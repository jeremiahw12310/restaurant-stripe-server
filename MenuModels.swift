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
}
