import SwiftUI
import Kingfisher
import UIKit

struct PersonalizedComboResultView: View {
    let combo: PersonalizedCombo
    let onOrder: () -> Void
    let onBack: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var menuViewModel: MenuViewModel
    @State private var pulseAnimation = false
    @State private var isRegenerating = false
    @State private var hintPulse = false
    
    var body: some View {
        ZStack {
            // Chatbot hybrid background (matches ChatbotView)
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
            
            JellyGlimmerView(
                scrollOffset: 0,
                time: 0,
                colorScheme: colorScheme,
                pop: false
            )
            .opacity(reduceMotion ? 0.02 : 0.05)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            
            // Subtle aurora spots
            RadialGradient(
                colors: [
                    Theme.primaryGold.opacity(reduceMotion ? 0.02 : 0.06),
                    Theme.lightGold.opacity(reduceMotion ? 0.01 : 0.03),
                    Color.clear
                ],
                center: .init(x: 0.15, y: 0.08),
                startRadius: pulseAnimation ? 80 : 100,
                endRadius: pulseAnimation ? 200 : 240
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 5.0).repeatForever(autoreverses: true), value: pulseAnimation)
            
            RadialGradient(
                colors: [
                    Theme.lightGold.opacity(reduceMotion ? 0.01 : 0.025),
                    Theme.primaryGold.opacity(reduceMotion ? 0.008 : 0.012),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.92),
                startRadius: pulseAnimation ? 80 : 90,
                endRadius: pulseAnimation ? 170 : 200
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 6.0).repeatForever(autoreverses: true), value: pulseAnimation)
            .onAppear { pulseAnimation = !reduceMotion }
            
            ScrollView {
                VStack(spacing: 22) {
                    // Compact header bar
                    HStack(spacing: 28) {
                        Image("newhero")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Personalized Combo")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Theme.modernPrimary, Theme.primaryGold]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Text("Curated just for you")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    
                    // AI message in glass card (no redundant header)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(combo.aiResponse)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Theme.modernCard.opacity(0.95),
                                        Theme.modernCard.opacity(0.85)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Theme.primaryGold.opacity(0.25),
                                                Theme.modernPrimary.opacity(0.2)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
                    )
                    .padding(.horizontal, 20)
                    
                    // Items list
                    VStack(spacing: 14) {
                        ForEach(Array(combo.items.enumerated()), id: \.element.id) { index, item in
                            ComboItemCard(
                                item: item,
                                menuViewModel: menuViewModel,
                                forceNoImage: item.resolvedImageURL == nil
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Actions row
                    VStack(spacing: 12) {
                    Button(action: onOrder) {
                            HStack(spacing: 12) {
                                Image(systemName: "bag.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Order Online")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Theme.primaryGold, Theme.deepGold]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: Theme.primaryGold.opacity(0.35), radius: 14, x: 0, y: 6)
                            )
                        }
                        
                        HStack(spacing: 12) {
                            Spacer()
                            
                            Button(action: triggerRegenerate) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Try another")
                                }
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Theme.modernSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
            }
            
            // Swipe-to-dismiss hint arrow (top-center)
            VStack {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.modernSecondary)
                    .opacity(0.85)
                    .scaleEffect(hintPulse ? 1.08 : 0.96)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: hintPulse)
                    .padding(.top, 10)
                Spacer()
            }
            .allowsHitTesting(false)
            .onAppear {
                if !reduceMotion { hintPulse = true }
            }
            
            // Regeneration loading overlay
            if isRegenerating {
                Color.black.opacity(0.2).ignoresSafeArea()
                PersonalizedComboLoadingView()
                    .transition(.opacity)
            }
        }
    }
    
    private func triggerRegenerate() {
        // Show loading overlay
        withAnimation { isRegenerating = true }
        // Notify parent/flow to regenerate; parent should handle navigation and replace this view
        NotificationCenter.default.post(name: Notification.Name("regeneratePersonalizedCombo"), object: combo)
    }
}

// MARK: - Combo Item Card (chatbot glass style)
struct ComboItemCard: View {
    let item: MenuItem
    let menuViewModel: MenuViewModel
    let forceNoImage: Bool
    
    /// Options matching prefetch (no cacheMemoryOnly) so combo images can load from disk.
    private static let comboImageProcessor = DownsamplingImageProcessor(size: CGSize(width: 120, height: 120))
    
    private var isDrinkCategory: Bool {
        // Check if category name indicates it's a drink
        let categoryLower = item.category.lowercased()
        let isDrink = categoryLower.contains("tea") || 
                      categoryLower.contains("coffee") || 
                      categoryLower.contains("lemonade") || 
                      categoryLower.contains("soda") || 
                      categoryLower.contains("drink") ||
                      categoryLower.contains("coke")
        
        DebugLogger.debug("🔍 Item: \(item.id) | category: '\(item.category)' | isDrinkCategory: \(isDrink)", category: "Combo")
        return isDrink
    }
    
    // Check if this item is from a category with lemonade/soda banner enabled
    private var isLemonadeSodaCategory: Bool {
        guard !item.category.isEmpty else {
            DebugLogger.debug("🔍 Item '\(item.id)' has empty category", category: "Combo")
            return false
        }
        
        DebugLogger.debug("🔍 Checking item '\(item.id)' with category '\(item.category)'", category: "Combo")
        DebugLogger.debug("🔍 Available categories: \(menuViewModel.menuCategories.map { "\($0.id) (lemonadeSodaEnabled: \($0.lemonadeSodaEnabled))" })", category: "Combo")
        
        // Find the category in menuViewModel and check if lemonadeSodaEnabled is true
        if let category = menuViewModel.menuCategories.first(where: { $0.id == item.category }) {
            DebugLogger.debug("🔍 Found matching category '\(category.id)' with lemonadeSodaEnabled: \(category.lemonadeSodaEnabled)", category: "Combo")
            return category.lemonadeSodaEnabled
        }
        
        DebugLogger.debug("🔍 No matching category found for '\(item.category)'", category: "Combo")
        return false
    }
    
    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemGray6))
            .frame(width: 84, height: 84)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(.systemGray3))
            )
    }
    
    var body: some View {
        HStack(spacing: 16) {
            if !forceNoImage && !isDrinkCategory {
                if let imageURL = item.resolvedImageURL {
                    KFImage(imageURL)
                        .setProcessor(Self.comboImageProcessor)
                        .scaleFactor(UIScreen.main.scale)
                        .cacheMemoryOnly(false)
                        .resizable()
                        .placeholder {
                            placeholderImage
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                } else {
                    placeholderImage
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text(item.id)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                            .lineLimit(2)
                        
                        // Yellow bubble for lemonade/soda category items
                        if isLemonadeSodaCategory {
                            Text("(lemonade or soda)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.yellow)
                                )
                        }
                    }
                    Spacer()
                    Text("$\(String(format: "%.2f", item.price))")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.primaryGold)
                }
                
                if !isDrinkCategory && !item.description.isEmpty {
                    HStack(spacing: 8) {
                        Text(item.description)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Theme.modernCard.opacity(0.95),
                            Theme.modernCard.opacity(0.85)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Theme.primaryGold.opacity(0.35),
                                    Theme.modernPrimary.opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 5)
        )
    }
}

struct EnhancedMenuItemCard: View {
    let item: MenuItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Enhanced item image with gold border
            ZStack {
                if let imageURL = item.resolvedImageURL {
                    KFImage(imageURL)
                        .resizable()
                        .placeholder { 
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                                .frame(width: 70, height: 70)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 70, height: 70)
                }
                
                // Gold border overlay
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.6),
                                Color(red: 0.8, green: 0.6, blue: 0.2).opacity(0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 70, height: 70)
            }
            
            // Enhanced item details
            VStack(alignment: .leading, spacing: 6) {
                Text(item.id)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Enhanced price with gold styling
            Text("$\(String(format: "%.2f", item.price))")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemGray6).opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.4),
                                    Color(red: 0.8, green: 0.6, blue: 0.2).opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 20)
    }
}

#Preview {
    let sampleCombo = PersonalizedCombo(
        items: [
            MenuItem(id: "Pork Dumplings", description: "Steamed pork dumplings", price: 8.99, imageURL: "", isAvailable: true, paymentLinkID: ""),
            MenuItem(id: "Spring Rolls", description: "Crispy vegetable spring rolls", price: 6.99, imageURL: "", isAvailable: true, paymentLinkID: ""),
            MenuItem(id: "Green Tea", description: "Hot green tea", price: 2.99, imageURL: "", isAvailable: true, paymentLinkID: "")
        ],
        aiResponse: "Jeremiah, I know you like traditional flavors and prefer lighter options. I've selected our signature pork dumplings with crispy spring rolls and a refreshing green tea to complete your meal.",
        totalPrice: 18.97
    )
    
    PersonalizedComboResultView(
        combo: sampleCombo,
        onOrder: { DebugLogger.debug("Order tapped", category: "Combo") },
        onBack: { DebugLogger.debug("Back tapped", category: "Combo") }
    )
} 
