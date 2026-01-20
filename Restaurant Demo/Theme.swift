import SwiftUI

/// Central palette for consistent theming across the app.
/// Dutch Bros-inspired design with white/cream and gold brand colors.
struct Theme {
    // MARK: - Brand Golds (Enhanced for Dutch Bros energy)
    static let primaryGold = Color(red: 0.85, green: 0.65, blue: 0.25)
    static let deepGold    = Color(red: 0.75, green: 0.55, blue: 0.15)
    static let lightGold   = Color(red: 0.95, green: 0.85, blue: 0.45)
    static let goldGradient = LinearGradient(
        colors: [primaryGold, deepGold],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let lightGoldGradient = LinearGradient(
        colors: [lightGold, primaryGold],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let darkGoldGradient = LinearGradient(
        colors: [Color(red: 0.7, green: 0.5, blue: 0.1), Color(red: 0.55, green: 0.35, blue: 0.02)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Dutch Bros-Inspired Color Scheme
    static let modernPrimary     = Color(red: 0.15, green: 0.15, blue: 0.25) // Deep charcoal
    static let modernSecondary   = Color(red: 0.4, green: 0.4, blue: 0.5)    // Medium gray
    static let modernAccent      = Color(red: 0.2, green: 0.7, blue: 0.4)   // Dutch Bros green
    static let modernBackground  = Color(red: 0.98, green: 0.98, blue: 0.99) // Cream white
    static let modernCard        = Color.white
    static let modernCardSecondary = Color(red: 0.96, green: 0.96, blue: 0.98) // Subtle cream
    
    // MARK: - Dutch Bros Energy Colors
    static let energyOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let energyRed = Color(red: 0.9, green: 0.3, blue: 0.3)
    static let energyBlue = Color(red: 0.2, green: 0.6, blue: 0.9)
    static let energyGreen = Color(red: 0.2, green: 0.7, blue: 0.4)
    
    // MARK: - Professional Gradients
    static let cardGradient = LinearGradient(
        colors: [modernCard, modernCardSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let energyGradient = LinearGradient(
        colors: [energyOrange, energyRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let successGradient = LinearGradient(
        colors: [energyGreen, energyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Shadow Colors
    static let cardShadow = Color.black.opacity(0.08)
    static let buttonShadow = Color.black.opacity(0.15)
    static let goldShadow = primaryGold.opacity(0.3)
} 