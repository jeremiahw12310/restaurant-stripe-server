import Foundation

struct PersonalizedCombo: Identifiable {
    let id = UUID()
    let items: [MenuItem]
    let aiResponse: String
    let totalPrice: Double
    
    init(items: [MenuItem], aiResponse: String, totalPrice: Double) {
        self.items = items
        self.aiResponse = aiResponse
        self.totalPrice = totalPrice
    }
}

struct ComboRequest: Codable {
    let userName: String
    let dietaryPreferences: DietaryPreferences?
    let menuItems: [MenuItem]
    let previousRecommendations: [PreviousCombo]?
    
    init(
        userName: String,
        dietaryPreferences: DietaryPreferences? = nil,
        menuItems: [MenuItem],
        previousRecommendations: [PreviousCombo]? = nil
    ) {
        self.userName = userName
        self.dietaryPreferences = dietaryPreferences
        self.menuItems = menuItems
        self.previousRecommendations = previousRecommendations
    }
}

struct PreviousCombo: Codable {
    let items: [ComboItem]
    
    struct ComboItem: Codable {
        let id: String
        let category: String
    }
}

struct DietaryPreferences: Codable {
    let likesSpicyFood: Bool
    let dislikesSpicyFood: Bool
    let hasPeanutAllergy: Bool
    let isVegetarian: Bool
    let hasLactoseIntolerance: Bool
    let doesntEatPork: Bool
    let tastePreferences: String
    /// Indicates whether the user has completed the dietary preferences flow
    let hasCompletedPreferences: Bool
    
    init(
        likesSpicyFood: Bool = false,
        dislikesSpicyFood: Bool = false,
        hasPeanutAllergy: Bool = false,
        isVegetarian: Bool = false,
        hasLactoseIntolerance: Bool = false,
        doesntEatPork: Bool = false,
        tastePreferences: String = "",
        hasCompletedPreferences: Bool = false
    ) {
        self.likesSpicyFood = likesSpicyFood
        self.dislikesSpicyFood = dislikesSpicyFood
        self.hasPeanutAllergy = hasPeanutAllergy
        self.isVegetarian = isVegetarian
        self.hasLactoseIntolerance = hasLactoseIntolerance
        self.doesntEatPork = doesntEatPork
        self.tastePreferences = tastePreferences
        self.hasCompletedPreferences = hasCompletedPreferences
    }
}

struct ComboResponse: Codable {
    let success: Bool
    let combo: ComboData
    let varietyInfo: VarietyInfo?
    
    struct ComboData: Codable {
        let items: [ComboItem]
        let aiResponse: String
        let totalPrice: Double
    }
    
    struct ComboItem: Codable {
        let id: String
        let category: String
    }
    
    struct VarietyInfo: Codable {
        let strategy: String
        let guideline: String
        let factors: [String: Int]
        let sessionId: String
    }
} 