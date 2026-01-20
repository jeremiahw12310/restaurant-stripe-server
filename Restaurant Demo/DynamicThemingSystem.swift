import SwiftUI
import Combine
import Foundation

// MARK: - Dynamic Theming System
// Visual intelligence and adaptive theming for Phase 2

class DynamicThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .adaptive
    @Published var timeOfDay: TimeOfDay = .morning
    @Published var userMood: UserMood = .neutral
    @Published var contentContext: ContentContext = .menu
    
    private var timer: Timer?
    
    enum AppTheme {
        case adaptive, warm, cool, energetic, calm, appetite, social
    }
    
    enum TimeOfDay {
        case dawn, morning, afternoon, evening, night, lateNight
    }
    
    enum UserMood {
        case excited, calm, hungry, social, focused, neutral
    }
    
    enum ContentContext {
        case menu, community, ordering, profile, admin
    }
    
    init() {
        updateTimeOfDay()
        startTimeTracking()
        determineThemeBasedOnContext()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - Time-based Theming
    private func startTimeTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.updateTimeOfDay()
            self.determineThemeBasedOnContext()
        }
    }
    
    private func updateTimeOfDay() {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<7: timeOfDay = .dawn
        case 7..<12: timeOfDay = .morning
        case 12..<17: timeOfDay = .afternoon
        case 17..<20: timeOfDay = .evening
        case 20..<23: timeOfDay = .night
        default: timeOfDay = .lateNight
        }
    }
    
    // MARK: - Intelligent Theme Selection
    func determineThemeBasedOnContext() {
        let newTheme: AppTheme
        
        switch (timeOfDay, contentContext, userMood) {
        case (.morning, .menu, _):
            newTheme = .energetic
        case (.afternoon, .menu, .hungry):
            newTheme = .appetite
        case (.evening, .menu, _):
            newTheme = .warm
        case (_, .community, .social):
            newTheme = .social
        case (.night, _, _):
            newTheme = .calm
        case (_, .ordering, .excited):
            newTheme = .energetic
        default:
            newTheme = .adaptive
        }
        
        if newTheme != currentTheme {
            withAnimation(.easeInOut(duration: 1.0)) {
                currentTheme = newTheme
            }
        }
    }
    
    // MARK: - Theme Color Schemes
    var colors: DynamicColors {
        switch currentTheme {
        case .adaptive:
            return adaptiveColors
        case .warm:
            return warmColors
        case .cool:
            return coolColors
        case .energetic:
            return energeticColors
        case .calm:
            return calmColors
        case .appetite:
            return appetiteColors
        case .social:
            return socialColors
        }
    }
    
    // MARK: - User Behavior Tracking
    func trackUserInteraction(_ interaction: UserInteraction) {
        switch interaction {
        case .quickTap:
            userMood = .excited
        case .longPress:
            userMood = .focused
        case .gentleScroll:
            userMood = .calm
        case .rapidScroll:
            userMood = .excited
        case .menuBrowsing:
            userMood = .hungry
        case .socialEngagement:
            userMood = .social
        }
        
        determineThemeBasedOnContext()
    }
    
    enum UserInteraction {
        case quickTap, longPress, gentleScroll, rapidScroll, menuBrowsing, socialEngagement
    }
}

// MARK: - Dynamic Color Schemes
struct DynamicColors {
    let primary: Color
    let secondary: Color
    let accent: Color
    let background: Color
    let surface: Color
    let onSurface: Color
    let cardBackground: Color
    let shadowColor: Color
    let gradientStart: Color
    let gradientEnd: Color
}

extension DynamicThemeManager {
    // Adaptive theme (changes based on time and context)
    private var adaptiveColors: DynamicColors {
        switch timeOfDay {
        case .dawn:
            return DynamicColors(
                primary: Color(red: 0.9, green: 0.6, blue: 0.4),
                secondary: Color(red: 0.8, green: 0.7, blue: 0.6),
                accent: Color(red: 1.0, green: 0.7, blue: 0.3),
                background: Color(red: 0.98, green: 0.96, blue: 0.94),
                surface: Color.white,
                onSurface: Color.black,
                cardBackground: Color.white.opacity(0.9),
                shadowColor: Color.black.opacity(0.08),
                gradientStart: Color(red: 1.0, green: 0.95, blue: 0.9),
                gradientEnd: Color(red: 0.95, green: 0.97, blue: 1.0)
            )
        case .morning:
            return energeticColors
        case .afternoon:
            return appetiteColors
        case .evening:
            return warmColors
        case .night, .lateNight:
            return calmColors
        }
    }
    
    // Warm theme (evening, cozy feeling)
    private var warmColors: DynamicColors {
        DynamicColors(
            primary: Color(red: 0.9, green: 0.6, blue: 0.3),
            secondary: Color(red: 0.8, green: 0.5, blue: 0.4),
            accent: Color(red: 1.0, green: 0.6, blue: 0.2),
            background: Color(red: 0.97, green: 0.94, blue: 0.9),
            surface: Color(red: 0.99, green: 0.97, blue: 0.94),
            onSurface: Color(red: 0.2, green: 0.1, blue: 0.1),
            cardBackground: Color(red: 0.98, green: 0.96, blue: 0.93),
            shadowColor: Color.orange.opacity(0.15),
            gradientStart: Color(red: 1.0, green: 0.9, blue: 0.8),
            gradientEnd: Color(red: 0.95, green: 0.85, blue: 0.75)
        )
    }
    
    // Cool theme (calm, focused)
    private var coolColors: DynamicColors {
        DynamicColors(
            primary: Color(red: 0.3, green: 0.6, blue: 0.9),
            secondary: Color(red: 0.4, green: 0.7, blue: 0.8),
            accent: Color(red: 0.2, green: 0.7, blue: 1.0),
            background: Color(red: 0.95, green: 0.97, blue: 0.99),
            surface: Color(red: 0.98, green: 0.99, blue: 1.0),
            onSurface: Color(red: 0.1, green: 0.1, blue: 0.2),
            cardBackground: Color(red: 0.96, green: 0.98, blue: 1.0),
            shadowColor: Color.blue.opacity(0.1),
            gradientStart: Color(red: 0.9, green: 0.95, blue: 1.0),
            gradientEnd: Color(red: 0.85, green: 0.92, blue: 0.98)
        )
    }
    
    // Energetic theme (morning, excitement)
    private var energeticColors: DynamicColors {
        DynamicColors(
            primary: Color(red: 1.0, green: 0.5, blue: 0.3),
            secondary: Color(red: 0.9, green: 0.7, blue: 0.2),
            accent: Color(red: 1.0, green: 0.6, blue: 0.0),
            background: Color(red: 0.99, green: 0.97, blue: 0.94),
            surface: Color.white,
            onSurface: Color.black,
            cardBackground: Color.white,
            shadowColor: Color.orange.opacity(0.12),
            gradientStart: Color(red: 1.0, green: 0.95, blue: 0.85),
            gradientEnd: Color(red: 0.95, green: 0.9, blue: 0.8)
        )
    }
    
    // Calm theme (night, relaxation)
    private var calmColors: DynamicColors {
        DynamicColors(
            primary: Color(red: 0.6, green: 0.7, blue: 0.9),
            secondary: Color(red: 0.7, green: 0.8, blue: 0.9),
            accent: Color(red: 0.5, green: 0.8, blue: 1.0),
            background: Color(red: 0.94, green: 0.96, blue: 0.98),
            surface: Color(red: 0.97, green: 0.98, blue: 0.99),
            onSurface: Color(red: 0.1, green: 0.1, blue: 0.15),
            cardBackground: Color(red: 0.98, green: 0.99, blue: 1.0),
            shadowColor: Color.blue.opacity(0.08),
            gradientStart: Color(red: 0.92, green: 0.95, blue: 0.98),
            gradientEnd: Color(red: 0.88, green: 0.92, blue: 0.96)
        )
    }
    
    // Appetite theme (food-focused, stimulating)
    private var appetiteColors: DynamicColors {
        DynamicColors(
            primary: Color(red: 0.9, green: 0.3, blue: 0.2),
            secondary: Color(red: 1.0, green: 0.6, blue: 0.3),
            accent: Color(red: 1.0, green: 0.4, blue: 0.1),
            background: Color(red: 0.98, green: 0.95, blue: 0.92),
            surface: Color(red: 0.99, green: 0.97, blue: 0.95),
            onSurface: Color.black,
            cardBackground: Color(red: 1.0, green: 0.98, blue: 0.96),
            shadowColor: Color.red.opacity(0.1),
            gradientStart: Color(red: 1.0, green: 0.93, blue: 0.87),
            gradientEnd: Color(red: 0.95, green: 0.88, blue: 0.82)
        )
    }
    
    // Social theme (community-focused)
    private var socialColors: DynamicColors {
        DynamicColors(
            primary: Color(red: 0.5, green: 0.3, blue: 0.9),
            secondary: Color(red: 0.7, green: 0.5, blue: 0.9),
            accent: Color(red: 0.6, green: 0.2, blue: 1.0),
            background: Color(red: 0.96, green: 0.95, blue: 0.98),
            surface: Color(red: 0.98, green: 0.97, blue: 0.99),
            onSurface: Color(red: 0.1, green: 0.05, blue: 0.15),
            cardBackground: Color(red: 0.99, green: 0.98, blue: 1.0),
            shadowColor: Color.purple.opacity(0.1),
            gradientStart: Color(red: 0.94, green: 0.92, blue: 0.98),
            gradientEnd: Color(red: 0.9, green: 0.87, blue: 0.95)
        )
    }
}

// MARK: - AI-Powered Visual Intelligence
class VisualIntelligenceManager: ObservableObject {
    @Published var imageEnhancements: [String: ImageEnhancement] = [:]
    @Published var contextualInsights: [ContentInsight] = []
    
    enum ImageEnhancement {
        case appetiteBoost(warmth: Double, saturation: Double)
        case moodLighting(brightness: Double, contrast: Double)
        case socialOptimization(vibrancy: Double, sharpness: Double)
    }
    
    struct ContentInsight {
        let type: InsightType
        let confidence: Double
        let recommendation: String
        
        enum InsightType {
            case colorHarmony, visualFlow, appetiteAppeal, socialEngagement
        }
    }
    
    // Smart image enhancement based on context
    func enhanceImage(for context: DynamicThemeManager.ContentContext, item: MenuItem? = nil) -> ImageEnhancement {
        switch context {
        case .menu:
            // Enhance appetite appeal
            return .appetiteBoost(warmth: 0.2, saturation: 0.15)
        case .community:
            // Optimize for social engagement
            return .socialOptimization(vibrancy: 0.1, sharpness: 0.05)
        case .ordering:
            // Enhance decision-making clarity
            return .moodLighting(brightness: 0.1, contrast: 0.08)
        default:
            return .moodLighting(brightness: 0.05, contrast: 0.03)
        }
    }
    
    // Analyze visual composition and provide insights
    func analyzeVisualComposition(for view: AnyView) -> [ContentInsight] {
        // Simulate AI analysis - in production, this would use ML models
        return [
            ContentInsight(
                type: .colorHarmony,
                confidence: 0.85,
                recommendation: "Consider warmer tones for better appetite appeal"
            ),
            ContentInsight(
                type: .visualFlow,
                confidence: 0.92,
                recommendation: "Excellent visual hierarchy and flow"
            )
        ]
    }
}

// MARK: - Smart Layout System
class SmartLayoutManager: ObservableObject {
    @Published var layoutMode: LayoutMode = .adaptive
    @Published var contentDensity: ContentDensity = .comfortable
    @Published var visualFlow: VisualFlow = .natural
    
    enum LayoutMode {
        case compact, comfortable, spacious, adaptive
    }
    
    enum ContentDensity {
        case minimal, comfortable, dense, adaptive
    }
    
    enum VisualFlow {
        case grid, list, card, natural, context
    }
    
    // Intelligent layout adaptation based on content and context
    func adaptLayout(for context: DynamicThemeManager.ContentContext, screenSize: CGSize) {
        switch context {
        case .menu:
            layoutMode = screenSize.width > 400 ? .comfortable : .compact
            contentDensity = .comfortable
            visualFlow = .card
        case .community:
            layoutMode = .spacious
            contentDensity = .comfortable
            visualFlow = .natural
        case .ordering:
            layoutMode = .compact
            contentDensity = .dense
            visualFlow = .list
        default:
            layoutMode = .adaptive
            contentDensity = .comfortable
            visualFlow = .natural
        }
    }
}

// MARK: - Dynamic Theme Environment
struct DynamicThemeEnvironment: EnvironmentKey {
    static let defaultValue = DynamicThemeManager()
}

extension EnvironmentValues {
    var dynamicTheme: DynamicThemeManager {
        get { self[DynamicThemeEnvironment.self] }
        set { self[DynamicThemeEnvironment.self] = newValue }
    }
}

// MARK: - Theme-Aware Views
struct ThemedBackground: View {
    @EnvironmentObject var themeManager: DynamicThemeManager
    
    var body: some View {
        LinearGradient(
            colors: [
                themeManager.colors.gradientStart,
                themeManager.colors.gradientEnd
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.0), value: themeManager.currentTheme)
    }
}

struct ThemedCard<Content: View>: View {
    @EnvironmentObject var themeManager: DynamicThemeManager
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(themeManager.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(themeManager.colors.accent.opacity(0.1), lineWidth: 1)
            )
            .shadow(
                color: themeManager.colors.shadowColor,
                radius: 8,
                x: 0,
                y: 4
            )
            .animation(.easeInOut(duration: 0.5), value: themeManager.currentTheme)
    }
} 