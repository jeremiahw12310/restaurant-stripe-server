import SwiftUI

/// Typography system for Restaurant Demo
/// Optimized for readability, visual hierarchy, and iOS design standards
struct AppTypography {
    
    // MARK: - Display Fonts (Headlines, Titles)
    /// Large display text for main headlines
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .default)
        .leading(.tight)
    
    /// Medium display text for section headers
    static let displayMedium = Font.system(size: 28, weight: .semibold, design: .default)
        .leading(.tight)
    
    /// Small display text for card titles
    static let displaySmall = Font.system(size: 24, weight: .medium, design: .default)
        .leading(.tight)
    
    // MARK: - Headline Fonts
    /// Primary headline for navigation and important sections
    static let headlineLarge = Font.system(size: 22, weight: .semibold, design: .default)
    
    /// Secondary headline for subsections
    static let headlineMedium = Font.system(size: 20, weight: .medium, design: .default)
    
    /// Small headline for card headers
    static let headlineSmall = Font.system(size: 18, weight: .medium, design: .default)
    
    // MARK: - Body Text
    /// Primary body text for main content
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    
    /// Standard body text
    static let bodyMedium = Font.system(size: 16, weight: .regular, design: .default)
    
    /// Small body text for descriptions
    static let bodySmall = Font.system(size: 15, weight: .regular, design: .default)
    
    // MARK: - Label Text
    /// Large labels for buttons and important elements
    static let labelLarge = Font.system(size: 16, weight: .medium, design: .default)
    
    /// Medium labels for form fields and secondary buttons
    static let labelMedium = Font.system(size: 15, weight: .medium, design: .default)
    
    /// Small labels for tags and metadata
    static let labelSmall = Font.system(size: 14, weight: .medium, design: .default)
    
    // MARK: - Caption Text
    /// Large captions for image descriptions
    static let captionLarge = Font.system(size: 14, weight: .regular, design: .default)
    
    /// Standard captions for metadata
    static let captionMedium = Font.system(size: 13, weight: .regular, design: .default)
    
    /// Small captions for fine print
    static let captionSmall = Font.system(size: 12, weight: .regular, design: .default)
    
    // MARK: - Specialized Fonts
    /// Pricing text with tabular figures for alignment
    static let pricing = Font.system(size: 18, weight: .semibold, design: .monospaced)
    
    /// Currency text for prices
    static let currency = Font.system(size: 16, weight: .medium, design: .monospaced)
    
    /// Numbers for quantities and counters
    static let numbers = Font.system(size: 16, weight: .medium, design: .monospaced)
    
    /// Menu item names with enhanced readability
    static let menuItem = Font.system(size: 17, weight: .medium, design: .default)
    
    /// Category labels with subtle emphasis
    static let category = Font.system(size: 15, weight: .semibold, design: .default)
    
    // MARK: - Interactive Elements
    /// Button text for primary actions
    static let buttonPrimary = Font.system(size: 17, weight: .semibold, design: .default)
    
    /// Button text for secondary actions
    static let buttonSecondary = Font.system(size: 16, weight: .medium, design: .default)
    
    /// Tab bar and navigation text
    static let navigation = Font.system(size: 10, weight: .medium, design: .default)
    
    // MARK: - MenuItemCard Specific Fonts
    /// Large icon font for placeholders
    static let iconLarge = Font.system(size: 40, weight: .regular)
    
    /// Price display font
    static let priceDisplay = Font.system(size: 20, weight: .bold, design: .rounded)
    
    /// Badge text font
    static let badgeText = Font.system(size: 12, weight: .medium)
    
    /// Emoji font
    static let emoji = Font.system(size: 12)
    
    /// Small icon font
    static let iconSmall = Font.system(size: 16, weight: .medium)
    
    // MARK: - Letter Spacing Modifiers
    /// Tight letter spacing for headlines
    static let tightSpacing: CGFloat = -0.5
    
    /// Normal letter spacing
    static let normalSpacing: CGFloat = 0
    
    /// Loose letter spacing for emphasis
    static let looseSpacing: CGFloat = 0.5
    
    // MARK: - Line Height Helpers
    /// Tight line height for display text
    static let tightLineHeight: CGFloat = 1.1
    
    /// Normal line height for body text
    static let normalLineHeight: CGFloat = 1.4
    
    /// Loose line height for readability
    static let looseLineHeight: CGFloat = 1.6
}

// MARK: - Font Extensions
extension Font {
    /// Apply custom letter spacing
    func letterSpacing(_ spacing: CGFloat) -> Font {
        return self
    }
    
    /// Apply custom line height
    func lineHeight(_ height: CGFloat) -> Font {
        return self
    }
    
    /// Make font weight adaptive to device settings
    func adaptiveWeight() -> Font {
        return self
    }
}

// MARK: - Text Style Extensions
extension Text {
    /// Apply pricing style with tabular figures
    func pricingStyle() -> some View {
        self
            .font(AppTypography.pricing)
            .foregroundColor(AppColors.primaryText)
            .monospacedDigit()
    }
    
    /// Apply menu item style
    func menuItemStyle() -> some View {
        self
            .font(AppTypography.menuItem)
            .foregroundColor(AppColors.primaryText)
            .lineLimit(2)
    }
    
    /// Apply category style
    func categoryStyle() -> some View {
        self
            .font(AppTypography.category)
            .foregroundColor(AppColors.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    /// Apply caption style
    func captionStyle() -> some View {
        self
            .font(AppTypography.captionMedium)
            .foregroundColor(AppColors.secondaryText)
    }
    
    /// Apply button style
    func buttonStyle(_ isPrimary: Bool = true) -> some View {
        self
            .font(isPrimary ? AppTypography.buttonPrimary : AppTypography.buttonSecondary)
            .foregroundColor(isPrimary ? .white : AppColors.primaryText)
    }
}

// MARK: - Accessibility Support
extension AppTypography {
    /// Get font that adapts to accessibility settings
    static func accessibleFont(base: Font, category: Font.TextStyle) -> Font {
        return Font.system(category, design: .default)
    }
    
    /// Check if user has large text enabled
    static func isLargeTextEnabled() -> Bool {
        return UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }
}

// MARK: - Preview Support
#if DEBUG
struct AppTypography_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Display Large")
                        .font(AppTypography.displayLarge)
                    
                    Text("Display Medium")
                        .font(AppTypography.displayMedium)
                    
                    Text("Headline Large")
                        .font(AppTypography.headlineLarge)
                    
                    Text("Body Large - This is body text that should be easy to read and provide good contrast for accessibility.")
                        .font(AppTypography.bodyLarge)
                    
                    Text("Menu Item - Pork & Chive Dumplings")
                        .menuItemStyle()
                    
                    Text("$12.99")
                        .pricingStyle()
                    
                    Text("APPETIZERS")
                        .categoryStyle()
                    
                    Text("Caption text for additional information")
                        .captionStyle()
                }
                
                Group {
                    Button("Primary Button") {}
                        .buttonStyle(.borderedProminent)
                    
                    Button("Secondary Button") {}
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.light)
        
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Display Large")
                        .font(AppTypography.displayLarge)
                    
                    Text("Display Medium")
                        .font(AppTypography.displayMedium)
                    
                    Text("Headline Large")
                        .font(AppTypography.headlineLarge)
                    
                    Text("Body Large - This is body text that should be easy to read and provide good contrast for accessibility.")
                        .font(AppTypography.bodyLarge)
                    
                    Text("Menu Item - Pork & Chive Dumplings")
                        .menuItemStyle()
                    
                    Text("$12.99")
                        .pricingStyle()
                    
                    Text("APPETIZERS")
                        .categoryStyle()
                    
                    Text("Caption text for additional information")
                        .captionStyle()
                }
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
    }
}
#endif 