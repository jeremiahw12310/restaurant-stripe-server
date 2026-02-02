import Foundation
import Combine
import SwiftUI
import Kingfisher

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
    private var areImagesReady = false
    
    // Failsafe timeout to dismiss interstitial if request hangs
    private var comboTimeoutWorkItem: DispatchWorkItem?
    
    // Retain prefetcher so it isn't deallocated before completion
    private var imagePrefetcher: ImagePrefetcher?
    
    // Count overlapping prefetches so we only restore Kingfisher defaults when the last one finishes
    private var comboPrefetchInProgressCount = 0
    
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
        areImagesReady = false
        requestEarlyCut = false
        error = nil
        
        // Start failsafe timeout to dismiss interstitial if request hangs
        comboTimeoutWorkItem?.cancel()
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.showComboInterstitial else { return }
            DebugLogger.debug("⏰ Combo generation failsafe timeout fired - dismissing interstitial", category: "Menu")
            self.showComboInterstitial = false
            self.error = "Request timed out. Please try again."
        }
        comboTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 35.0, execute: timeoutItem)
        
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
                // Cancel failsafe timeout since we got a response
                self?.comboTimeoutWorkItem?.cancel()
                self?.comboTimeoutWorkItem = nil
                
                if case .failure(let error) = completion {
                    DebugLogger.debug("❌ Combo generation failed: \(error)", category: "Menu")
                    self?.error = error.localizedDescription
                    // Dismiss interstitial if still showing
                    self?.showComboInterstitial = false
                }
            },
            receiveValue: { [weak self] combo in
                // Cancel failsafe timeout since we got a response
                self?.comboTimeoutWorkItem?.cancel()
                self?.comboTimeoutWorkItem = nil
                
                DebugLogger.debug("✅ Combo generated successfully", category: "Menu")
                DebugLogger.debug("🍽️ Combo items: \(combo.items.map { $0.id })", category: "Menu")
                DebugLogger.debug("💰 Total price: $\(combo.totalPrice)", category: "Menu")
                self?.personalizedCombo = combo
                self?.isComboReady = true
                
                // Add this combo to previous recommendations
                self?.addToPreviousRecommendations(combo)
                
                // Prefetch images before signaling video can end
                self?.prefetchComboImages(combo: combo) {
                    self?.areImagesReady = true
                    // Signal the interstitial it may end early (subject to threshold)
                    self?.requestEarlyCut = true
                    self?.maybeShowResult()
                }
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
        if isComboReady && isInterstitialDone && areImagesReady {
            showComboResult = true
        }
    }
    
    private func prefetchComboImages(combo: PersonalizedCombo, completion: @escaping () -> Void) {
        let urls = combo.items.compactMap { $0.resolvedImageURL }
        
        guard !urls.isEmpty else {
            DebugLogger.debug("🖼️ No combo images to prefetch", category: "Menu")
            completion()
            return
        }
        
        DebugLogger.debug("🖼️ Prefetching \(urls.count) combo images", category: "Menu")
        
        // KingfisherOptionsInfoItem.cacheMemoryOnly has no associated value, so we temporarily
        // remove it from default options so prefetched combo images persist to disk.
        let processor = DownsamplingImageProcessor(size: CGSize(width: 120, height: 120))
        let options: KingfisherOptionsInfo = [
            .processor(processor),
            .scaleFactor(UIScreen.main.scale),
            .cacheSerializer(FormatIndicatedCacheSerializer.png),
            .backgroundDecode
        ]
        let originalDefaults = KingfisherManager.shared.defaultOptions
        KingfisherManager.shared.defaultOptions = originalDefaults.filter { opt in
            if case .cacheMemoryOnly = opt { return false }
            return true
        }
        comboPrefetchInProgressCount += 1
        
        // Store prefetcher so it isn't deallocated before completion
        imagePrefetcher = ImagePrefetcher(urls: urls, options: options) { [weak self] skipped, failed, completed in
            DispatchQueue.main.async {
                self?.comboPrefetchInProgressCount = max(0, (self?.comboPrefetchInProgressCount ?? 1) - 1)
                if self?.comboPrefetchInProgressCount == 0 {
                    KingfisherManager.shared.defaultOptions = originalDefaults
                }
                self?.imagePrefetcher = nil  // Clear reference after completion
                DebugLogger.debug("🖼️ Image prefetch done - skipped: \(skipped.count), failed: \(failed.count), completed: \(completed.count)", category: "Menu")
                completion()
            }
        }
        imagePrefetcher?.start()
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