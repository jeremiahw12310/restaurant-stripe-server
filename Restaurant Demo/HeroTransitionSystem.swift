import SwiftUI
import Combine

// MARK: - Hero Transition System
// Advanced hero transitions and layout morphing for Phase 2

struct HeroTransitionModifier: ViewModifier {
    let heroID: String
    let namespace: Namespace.ID
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .matchedGeometryEffect(id: heroID, in: namespace, isSource: isVisible)
    }
}

extension View {
    func heroTransition(id: String, in namespace: Namespace.ID, isVisible: Bool = true) -> some View {
        self.modifier(HeroTransitionModifier(heroID: id, namespace: namespace, isVisible: isVisible))
    }
}

// MARK: - Enhanced Menu Item Card with Hero Transitions
struct HeroMenuItemCard: View {
    let item: MenuItem
    let namespace: Namespace.ID
    @State private var isPressed = false
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @Environment(\.colorScheme) var colorScheme
    
    // Advanced micro-interactions
    @GestureState private var dragOffset = CGSize.zero
    @State private var springOffset: CGSize = .zero
    
    var body: some View {
        VStack(spacing: 0) {
            // Hero image with advanced animations
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemBackground),
                                Color(.systemBackground).opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                        radius: isPressed ? 20 : 8,
                        x: 0,
                        y: isPressed ? 8 : 4
                    )
                
                // Enhanced image with hero transition
                AsyncImage(url: URL(string: item.imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                        .heroTransition(id: "image-\(item.id)", in: namespace)
                } placeholder: {
                    // Sophisticated skeleton loading
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.3),
                                    Color.gray.opacity(0.1),
                                    Color.gray.opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 140)
                        .shimmering()
                }
                .cornerRadius(12)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            
            // Enhanced text section with hero transitions
            VStack(alignment: .leading, spacing: 6) {
                Text(item.description)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .heroTransition(id: "title-\(item.id)", in: namespace)
                
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .heroTransition(id: "description-\(item.id)", in: namespace)
                
                Text("$\(String(format: "%.2f", item.price))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .heroTransition(id: "price-\(item.id)", in: namespace)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .offset(springOffset)
        .rotationEffect(.degrees(cardRotation))
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: isPressed)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: springOffset)
        // Advanced gesture system
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                    
                    // Micro-interactions during drag
                    withAnimation(.easeOut(duration: 0.1)) {
                        springOffset = CGSize(
                            width: value.translation.width * 0.1,
                            height: value.translation.height * 0.1
                        )
                        cardRotation = Double(value.translation.width) * 0.05
                    }
                }
                .onEnded { value in
                    // Spring back animation
                    withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8)) {
                        springOffset = .zero
                        cardRotation = 0
                    }
                }
                .simultaneously(with: 
                    TapGesture()
                        .onEnded { _ in
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                            // Tap animation
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isPressed = true
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    isPressed = false
                                }
                            }
                        }
                )
        )
    }
}

// MARK: - Shimmer Effect for Loading States
struct ShimmerModifier: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.4),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: isAnimating ? 200 : -200)
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

// MARK: - Advanced Layout Morphing System
struct MorphingContainer<Content: View>: View {
    let content: Content
    @State private var layoutPhase: LayoutPhase = .compact
    @State private var animationProgress: Double = 0
    
    enum LayoutPhase {
        case compact, expanded, fullScreen
    }
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .scaleEffect(layoutScale)
            .opacity(layoutOpacity)
            .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.8), value: layoutPhase)
    }
    
    private var layoutScale: CGFloat {
        switch layoutPhase {
        case .compact: return 1.0
        case .expanded: return 1.05
        case .fullScreen: return 1.1
        }
    }
    
    private var layoutOpacity: Double {
        switch layoutPhase {
        case .compact: return 1.0
        case .expanded: return 0.95
        case .fullScreen: return 1.0
        }
    }
    
    func morphTo(_ phase: LayoutPhase) {
        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8)) {
            layoutPhase = phase
        }
    }
}

// MARK: - Advanced Gesture Recognition System
struct AdvancedGestureRecognizer: UIViewRepresentable {
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onSwipe: (UISwipeGestureRecognizer.Direction) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        
        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tapGesture)
        
        // Long press gesture
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
        
        // Swipe gestures
        for direction in [UISwipeGestureRecognizer.Direction.left, .right, .up, .down] {
            let swipeGesture = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe))
            swipeGesture.direction = direction
            view.addGestureRecognizer(swipeGesture)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: AdvancedGestureRecognizer
        
        init(_ parent: AdvancedGestureRecognizer) {
            self.parent = parent
        }
        
        @objc func handleTap() {
            parent.onTap()
        }
        
        @objc func handleLongPress() {
            parent.onLongPress()
        }
        
        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            parent.onSwipe(gesture.direction)
        }
    }
}

// MARK: - Fluid Animation Helper
struct FluidAnimation {
    static let spring = Animation.interactiveSpring(response: 0.4, dampingFraction: 0.8)
    static let easeInOut = Animation.easeInOut(duration: 0.3)
    static let bounce = Animation.interpolatingSpring(stiffness: 300, damping: 20)
    static let smooth = Animation.easeInOut(duration: 0.5)
}

// MARK: - Contextual Micro-Interactions
struct MicroInteractionModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .onTapGesture {
                // Micro-interaction on tap
                withAnimation(.easeInOut(duration: 0.1)) {
                    scale = 0.95
                    opacity = 0.8
                }
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                // Spring back
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(FluidAnimation.spring) {
                        scale = 1.0
                        opacity = 1.0
                    }
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                // Long press micro-interaction
                withAnimation(FluidAnimation.bounce) {
                    rotation += 360
                }
                
                // Stronger haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
            }
    }
}

extension View {
    func microInteractions() -> some View {
        self.modifier(MicroInteractionModifier())
    }
} 