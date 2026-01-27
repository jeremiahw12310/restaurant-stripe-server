import Foundation
import Combine
import SwiftUI

class MenuViewViewModel: ObservableObject {
    @Published var showComboLoading = false
    @Published var showComboResult = false
    @Published var personalizedCombo: PersonalizedCombo?
    @Published var error: String?
    @Published var showOrderWebView = false
    @Published var showComboInterstitial = false
    @Published var requestEarlyCut = false
    
    private var cancellables = Set<AnyCancellable>()
    private let comboService = PersonalizedComboService()
    private var isComboReady = false
    private var isInterstitialDone = false
    
    // Track previous recommendations (last 3)
    private var previousRecommendations: [PreviousCombo] = []
    
    func handlePersonalizedComboTap(
        userVM: UserViewModel,
        menuVM: MenuViewModel
    ) {
        DebugLogger.debug("🎯 Personalized combo tapped", category: "Menu")
        DebugLogger.debug("👤 User name: \(userVM.firstName.isEmpty ? "Guest" : userVM.firstName)", category: "Menu")
        DebugLogger.debug("✅ Has completed preferences: \(userVM.hasCompletedPreferences)", category: "Menu")
        DebugLogger.debug("📋 Previous recommendations count: \(previousRecommendations.count)", category: "Menu")
        
        // Present interstitial video immediately
        showComboInterstitial = true
        // Reset gating flags
        isComboReady = false
        isInterstitialDone = false
        requestEarlyCut = false
        error = nil
        
        let userName = userVM.firstName.isEmpty ? "Guest" : userVM.firstName
        // Create dietary preferences with current values (may be defaults if not set)
        // Include hasCompletedPreferences so backend knows user's preference status
        let dietaryPreferences = DietaryPreferences(
            likesSpicyFood: userVM.likesSpicyFood,
            dislikesSpicyFood: userVM.dislikesSpicyFood,
            hasPeanutAllergy: userVM.hasPeanutAllergy,
            isVegetarian: userVM.isVegetarian,
            hasLactoseIntolerance: userVM.hasLactoseIntolerance,
            doesntEatPork: userVM.doesntEatPork,
            tastePreferences: userVM.tastePreferences,
            hasCompletedPreferences: userVM.hasCompletedPreferences
        )
        
        DebugLogger.debug("🔍 Generating combo for \(userName) with preferences: \(dietaryPreferences)", category: "Menu")
        DebugLogger.debug("📋 Available menu items: \(menuVM.allMenuItems.count)", category: "Menu")
        
        comboService.generatePersonalizedCombo(
            userName: userName,
            dietaryPreferences: dietaryPreferences,
            menuItems: menuVM.allMenuItems,
            previousRecommendations: previousRecommendations.isEmpty ? nil : previousRecommendations
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    DebugLogger.debug("❌ Combo generation failed: \(error)", category: "Menu")
                    self?.error = error.localizedDescription
                    // Dismiss interstitial if still showing
                    self?.showComboInterstitial = false
                }
            },
            receiveValue: { [weak self] combo in
                DebugLogger.debug("✅ Combo generated successfully", category: "Menu")
                DebugLogger.debug("🍽️ Combo items: \(combo.items.map { $0.id })", category: "Menu")
                DebugLogger.debug("💰 Total price: $\(combo.totalPrice)", category: "Menu")
                self?.personalizedCombo = combo
                self?.isComboReady = true
                // Signal the interstitial it may end early (subject to threshold)
                self?.requestEarlyCut = true
                self?.maybeShowResult()
                
                // Add this combo to previous recommendations
                self?.addToPreviousRecommendations(combo)
            }
        )
        .store(in: &cancellables)
    }

    func interstitialDidFinish() {
        isInterstitialDone = true
        showComboInterstitial = false
        // Clear early-cut request for next run
        requestEarlyCut = false
        maybeShowResult()
    }

    private func maybeShowResult() {
        if isComboReady && isInterstitialDone {
            showComboResult = true
        }
    }
    
    private func addToPreviousRecommendations(_ combo: PersonalizedCombo) {
        // Convert PersonalizedCombo to PreviousCombo
        let previousCombo = PreviousCombo(
            items: combo.items.map { item in
                PreviousCombo.ComboItem(id: item.id, category: item.category)
            }
        )
        
        // Add to the beginning of the array (most recent first)
        previousRecommendations.insert(previousCombo, at: 0)
        
        // Keep only the last 3 recommendations
        if previousRecommendations.count > 3 {
            previousRecommendations = Array(previousRecommendations.prefix(3))
        }
        
        DebugLogger.debug("📝 Added combo to previous recommendations. Total: \(previousRecommendations.count)", category: "Menu")
        DebugLogger.debug("📋 Previous combos: \(previousRecommendations.map { $0.items.map { $0.id }.joined(separator: ", ") })", category: "Menu")
    }
    
    func handleOrderCombo() {
        guard let combo = personalizedCombo else { return }

        // Navigate to order web view
        showOrderWebView = true
    }
} 