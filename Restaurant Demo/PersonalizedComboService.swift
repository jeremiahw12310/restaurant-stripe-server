import Foundation
import Combine
import FirebaseAuth

class PersonalizedComboService: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    
    private let backendURL = Config.backendURL

    private enum ComboAuthError: LocalizedError {
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Please sign in to generate a personalized combo."
            }
        }
    }

    private func idTokenPublisher() -> AnyPublisher<String, Error> {
        Future<String, Error> { promise in
            guard let user = Auth.auth().currentUser else {
                promise(.failure(ComboAuthError.notSignedIn))
                return
            }
            user.getIDToken { token, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                guard let token else {
                    promise(.failure(ComboAuthError.notSignedIn))
                    return
                }
                promise(.success(token))
            }
        }
        .eraseToAnyPublisher()
    }
    
    func generatePersonalizedCombo(
        userName: String,
        dietaryPreferences: DietaryPreferences? = nil,
        menuItems: [MenuItem],
        previousRecommendations: [PreviousCombo]? = nil
    ) -> AnyPublisher<PersonalizedCombo, Error> {
        isLoading = true
        error = nil
        
        let request = ComboRequest(
            userName: userName,
            dietaryPreferences: dietaryPreferences,
            menuItems: menuItems,
            previousRecommendations: previousRecommendations
        )
        
        guard let url = URL(string: "\(backendURL)/generate-combo") else {
            return Fail(error: ComboError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            let requestData = try encoder.encode(request)
            urlRequest.httpBody = requestData
        } catch {
            return Fail(error: ComboError.encodingError)
                .eraseToAnyPublisher()
        }
        
        return idTokenPublisher()
            .flatMap { token -> AnyPublisher<Data, Error> in
                var authed = urlRequest
                authed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return URLSession.configured.dataTaskPublisher(for: authed)
                    .map(\.data)
                    .mapError { $0 as Error }
                    .eraseToAnyPublisher()
            }
            .handleEvents(receiveOutput: { data in
                DebugLogger.debug("📥 Received response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")", category: "Combo")
            })
            .decode(type: ComboResponse.self, decoder: JSONDecoder())
            .map { response in
                DebugLogger.debug("✅ Successfully decoded ComboResponse: \(response)", category: "Combo")
                // Convert response to PersonalizedCombo by matching with actual menu items
                let comboItems = response.combo.items.compactMap { comboItem in
                    // Try exact match first
                    if let exactMatch = menuItems.first(where: { $0.id == comboItem.id }) {
                        return exactMatch
                    }
                    
                    // Try fuzzy matching if exact match fails
                    let fuzzyMatch = menuItems.first { menuItem in
                        let aiItemLower = comboItem.id.lowercased()
                        let menuItemLower = menuItem.id.lowercased()
                        
                        // Check if the AI item contains key parts of the menu item
                        return menuItemLower.contains(aiItemLower) || 
                               aiItemLower.contains(menuItemLower) ||
                               menuItemLower.contains(aiItemLower.replacingOccurrences(of: " ", with: "")) ||
                               aiItemLower.contains(menuItemLower.replacingOccurrences(of: " ", with: ""))
                    }
                    
                    if let fuzzyMatch = fuzzyMatch {
                        DebugLogger.debug("🔍 Fuzzy matched '\(comboItem.id)' to '\(fuzzyMatch.id)'", category: "Combo")
                        return fuzzyMatch
                    }
                    
                    // If still no match, try to find by category
                    let categoryMatch = menuItems.first { menuItem in
                        let aiCategory = comboItem.category.lowercased()
                        let menuItemIsDumpling = menuItem.isDumpling
                        
                        if aiCategory == "dumplings" && menuItemIsDumpling {
                            return true
                        } else if (aiCategory == "appetizers" || aiCategory == "sauces") && !menuItemIsDumpling {
                            return true
                        }
                        return false
                    }
                    
                    if let categoryMatch = categoryMatch {
                        DebugLogger.debug("🔍 Category matched '\(comboItem.id)' to '\(categoryMatch.id)'", category: "Combo")
                        return categoryMatch
                    }
                    
                    DebugLogger.debug("❌ Could not match AI item: \(comboItem.id)", category: "Combo")
                    return nil
                }
                
                // If we couldn't find some items, log a warning but continue
                if comboItems.count != response.combo.items.count {
                    DebugLogger.debug("⚠️ Warning: Could not find \(response.combo.items.count - comboItems.count) menu items from AI response", category: "Combo")
                    DebugLogger.debug("🔍 AI suggested items: \(response.combo.items.map { $0.id })", category: "Combo")
                    DebugLogger.debug("📋 Available menu items: \(menuItems.map { $0.id })", category: "Combo")
                }
                
                // If no items were found, provide fallback items
                let finalItems = comboItems.isEmpty ? [
                    menuItems.first { $0.isDumpling } ?? menuItems.first,
                    menuItems.first { !$0.isDumpling } ?? menuItems.first
                ].compactMap { $0 } : comboItems
                
                return PersonalizedCombo(
                    items: finalItems,
                    aiResponse: response.combo.aiResponse,
                    totalPrice: response.combo.totalPrice
                )
            }
            .handleEvents(
                receiveOutput: { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                },
                receiveCompletion: { [weak self] completion in
                    DispatchQueue.main.async {
                        if case .failure(let error) = completion {
                            self?.isLoading = false
                            self?.error = error.localizedDescription
                            DebugLogger.debug("❌ Combo generation failed: \(error)", category: "Combo")
                        }
                    }
                }
            )
            .eraseToAnyPublisher()
    }
}

enum ComboError: Error, LocalizedError {
    case invalidURL
    case encodingError
    case networkError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .encodingError:
            return "Failed to encode request"
        case .networkError:
            return "Network error occurred"
        case .decodingError:
            return "Failed to decode response"
        }
    }
} 