import SwiftUI

// MARK: - Enhanced Selective Glimmer System
struct SelectiveGlimmerView: View {
    let isActive: Bool
    let intensity: GlimmerIntensity
    let isLowPowerMode: Bool
    @State private var glimmerOffset: CGFloat = -200
    
    enum GlimmerIntensity {
        case subtle, medium, strong
        
        var colors: [Color] {
            switch self {
            case .subtle:
                return [
                    Color.clear,
                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1),
                    Color.clear
                ]
            case .medium:
                return [
                    Color.clear,
                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2),
                    Color(red: 0.95, green: 0.85, blue: 0.7).opacity(0.3),
                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2),
                    Color.clear
                ]
            case .strong:
                return [
                    Color.clear,
                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3),
                    Color(red: 0.95, green: 0.85, blue: 0.7).opacity(0.4),
                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3),
                    Color.clear
                ]
            }
        }
        
        var animationDuration: Double {
            switch self {
            case .subtle: return 3.0
            case .medium: return 2.5
            case .strong: return 2.0
            }
        }
    }
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: intensity.colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.6),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(12)) // More organic angle
                    .offset(x: glimmerOffset)
            )
            .onAppear {
                if isActive && !isLowPowerMode {
                    startGlimmerAnimation()
                }
            }
            .onChange(of: isActive) { newValue in
                if newValue && !isLowPowerMode {
                    startGlimmerAnimation()
                } else {
                    stopGlimmerAnimation()
                }
            }
            .onChange(of: isLowPowerMode) { newValue in
                if newValue {
                    stopGlimmerAnimation()
                } else if isActive {
                    startGlimmerAnimation()
                }
            }
    }
    
    private func startGlimmerAnimation() {
        withAnimation(
            Animation.easeInOut(duration: intensity.animationDuration)
                .repeatForever(autoreverses: false)
        ) {
            glimmerOffset = 400
        }
    }
    
    private func stopGlimmerAnimation() {
        withAnimation(.easeOut(duration: 0.5)) {
            glimmerOffset = -200
        }
    }
}

// MARK: - Button Glimmer Enhancement
struct GlimmerButton<Content: View>: View {
    let intensity: SelectiveGlimmerView.GlimmerIntensity
    let isLowPowerMode: Bool
    let content: Content
    @State private var isPressed = false
    
    init(intensity: SelectiveGlimmerView.GlimmerIntensity = .medium, isLowPowerMode: Bool = false, @ViewBuilder content: () -> Content) {
        self.intensity = intensity
        self.isLowPowerMode = isLowPowerMode
        self.content = content()
    }
    
    var body: some View {
        content
            .overlay(
                SelectiveGlimmerView(isActive: !isPressed, intensity: intensity, isLowPowerMode: isLowPowerMode)
                    .allowsHitTesting(false)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onTapGesture {
                // Provide haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
            }
    }
}

// MARK: - Micro-Interaction Card Enhancement
struct MicroInteractionCard<Content: View>: View {
    let content: Content
    @State private var isHovered = false
    @State private var isPressed = false
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .scaleEffect(isPressed ? 0.98 : (isHovered ? 1.02 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(isHovered ? 0.3 : 0.0),
                                Color(red: 0.95, green: 0.85, blue: 0.7).opacity(isHovered ? 0.2 : 0.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 0.5 : 0
                    )
            )
            .shadow(
                color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(isHovered ? 0.1 : 0.0),
                radius: isHovered ? 8 : 0,
                x: 0,
                y: isHovered ? 4 : 0
            )
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = pressing
                }
            }, perform: {})
    }
} 