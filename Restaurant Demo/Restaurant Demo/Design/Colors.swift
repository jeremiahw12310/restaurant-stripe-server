import SwiftUI

// MARK: - App Colors
// Color system for the Restaurant Demo app

struct AppColors {
    // Primary brand colors
    static let dumplingGold = Color(red: 0.9, green: 0.7, blue: 0.3)
    static let primary = Color.blue
    static let secondary = Color.gray
    static let accent = Color.orange
    
    // Background colors
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    
    // Surface colors
    static let surfacePrimary = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)
    static let surfaceTertiary = Color(.tertiarySystemBackground)
    
    // Text colors
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    
    // Interactive colors
    static let buttonPrimary = Color.blue
    static let buttonSecondary = Color(.systemGray)
    static let buttonDestructive = Color.red
    
    // Status colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // Border and separator colors
    static let border = Color(.separator)
    static let divider = Color(.systemGray4)
    
    // Shadow colors
    static let shadowPrimary = Color.black.opacity(0.1)
    static let shadowSecondary = Color.black.opacity(0.05)
    
    // Card colors
    static let cardBackground = Color(.systemBackground)
    static let cardBorder = Color(.systemGray5)
    
    // Overlay colors
    static let overlay = Color.black.opacity(0.3)
    static let backdropBlur = Color.white.opacity(0.1)
    
    // Glass effects
    static let glassLight = Color.white.opacity(0.15)
    
    // Fresh colors for pricing
    static let freshGreen = Color.green
    
    // Information colors
    static let informationBlue = Color.blue
}

// MARK: - Color Extensions
extension Color {
    static let appBackground = AppColors.background
    static let appPrimary = AppColors.primary
    static let appSecondary = AppColors.secondary
    static let appAccent = AppColors.accent
}

// MARK: - Preview Support
#if DEBUG
struct AppColors_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            HStack {
                ColorSwatch(color: AppColors.primary, name: "Primary")
                ColorSwatch(color: AppColors.secondary, name: "Secondary")
                ColorSwatch(color: AppColors.accent, name: "Accent")
            }
            
            HStack {
                ColorSwatch(color: AppColors.background, name: "Background")
                ColorSwatch(color: AppColors.secondaryBackground, name: "Secondary Background")
                ColorSwatch(color: AppColors.groupedBackground, name: "Grouped Background")
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.light)
        
        VStack(spacing: 16) {
            HStack {
                ColorSwatch(color: AppColors.primary, name: "Primary")
                ColorSwatch(color: AppColors.secondary, name: "Secondary")
                ColorSwatch(color: AppColors.accent, name: "Accent")
            }
            
            HStack {
                ColorSwatch(color: AppColors.background, name: "Background")
                ColorSwatch(color: AppColors.secondaryBackground, name: "Secondary Background")
                ColorSwatch(color: AppColors.groupedBackground, name: "Grouped Background")
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
    }
}

private struct ColorSwatch: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
            
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
#endif 