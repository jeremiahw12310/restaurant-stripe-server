import SwiftUI

// MARK: - Walkthrough Confetti Model

struct WalkthroughConfettiPiece: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var rotation: Double
    var scale: Double
    var color: Color
    var velocity: Double
    var angularVelocity: Double
}

// MARK: - Walkthrough Step Data

private struct WalkthroughStep {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    /// Tab to navigate to (-1 = no tab change, used for the welcome step)
    let targetTab: Int
    /// Whether this is the special welcome/points step
    let isWelcomeStep: Bool
}

// MARK: - Walkthrough Overlay View

/// A full-screen paged overlay that teaches new users how to use the app.
/// Step 0 (optional) shows the welcome screen with confetti and +5 points.
/// Steps 1-4 navigate to the relevant tab and point an arrow at the tab bar item.
/// Must be placed above the TabView in ContentView so it can cover the tab bar.
struct WalkthroughOverlayView: View {
    let includeWelcome: Bool
    let onComplete: () -> Void
    let onStepChanged: (Int) -> Void
    let onClaimWelcomePoints: () -> Void

    @State private var currentStep = 0
    @State private var contentVisible = false
    @State private var isTransitioning = false
    @State private var arrowBounce = false
    @State private var welcomePointsClaimed = false

    // Welcome confetti state
    @State private var confettiPieces: [WalkthroughConfettiPiece] = []
    @State private var confettiTimer: Timer? = nil

    // Welcome sub-animations
    @State private var welcomeContentVisible = false
    @State private var welcomePointsVisible = false
    @State private var welcomeMessageVisible = false

    private var steps: [WalkthroughStep] {
        var list: [WalkthroughStep] = []
        if includeWelcome {
            list.append(WalkthroughStep(
                icon: "party.popper.fill",
                iconColor: Theme.primaryGold,
                title: "Welcome to",
                subtitle: "Dumpling House Rewards",
                description: "Thanks for signing up!\nScan receipts to earn more points and unlock exclusive rewards.",
                targetTab: 0,
                isWelcomeStep: true
            ))
        }
        list.append(contentsOf: [
            WalkthroughStep(
                icon: "house.fill",
                iconColor: Theme.primaryGold,
                title: "Your Home Base",
                subtitle: "Everything Starts Here",
                description: "Order ahead, refer friends, reserve a table, get directions, and more — all from your home screen.",
                targetTab: 0,
                isWelcomeStep: false
            ),
            WalkthroughStep(
                icon: "camera.fill",
                iconColor: Theme.energyBlue,
                title: "Earn Points",
                subtitle: "Scan Your Receipts",
                description: "After dining at Dumpling House, tap here to scan your receipt and earn points toward free rewards.",
                targetTab: 2,
                isWelcomeStep: false
            ),
            WalkthroughStep(
                icon: "gift.fill",
                iconColor: Theme.energyGreen,
                title: "Redeem Rewards",
                subtitle: "Unlock Free Items",
                description: "As you earn points, unlock tiers of exclusive rewards — from appetizers to full entrees.",
                targetTab: 3,
                isWelcomeStep: false
            ),
            WalkthroughStep(
                icon: "list.bullet",
                iconColor: Theme.energyRed,
                title: "Browse the Menu",
                subtitle: "See What We Offer",
                description: "Explore our full menu with photos, descriptions, and dietary info — all in one place.",
                targetTab: 1,
                isWelcomeStep: false
            )
        ])
        return list
    }

    /// The index of the first non-welcome step (cannot go back past this after welcome is dismissed)
    private var firstTourStep: Int { includeWelcome ? 1 : 0 }

    /// Whether the current step is the welcome step
    private var isOnWelcomeStep: Bool {
        guard currentStep < steps.count else { return false }
        return steps[currentStep].isWelcomeStep
    }

    /// Total tour steps (excluding welcome) for the step counter display
    private var tourStepCount: Int { steps.count - (includeWelcome ? 1 : 0) }

    /// Current tour step number (1-based, excluding welcome)
    private var tourStepNumber: Int { currentStep - (includeWelcome ? 1 : 0) + 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Semi-transparent background
                Color.black.opacity(isOnWelcomeStep ? 0.75 : 0.8)
                    .ignoresSafeArea()
                    .transition(.opacity)

                // Confetti (welcome step only)
                if isOnWelcomeStep {
                    ForEach(confettiPieces) { piece in
                        Circle()
                            .fill(piece.color)
                            .frame(width: 8, height: 8)
                            .position(x: piece.x, y: piece.y)
                            .rotationEffect(.degrees(piece.rotation))
                            .scaleEffect(piece.scale)
                    }
                }

                // Main content VStack
                VStack(spacing: 0) {
                    // Top bar: Back + Skip
                    HStack {
                        // Back button (not on welcome step, not on first tour step)
                        if !isOnWelcomeStep && currentStep > firstTourStep {
                            Button(action: { goBack() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Back")
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                }
                                .foregroundColor(.white.opacity(0.7))
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }

                        Spacer()

                        Button(action: { skipWalkthrough() }) {
                            Text("Skip")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 8)

                    Spacer()

                    // Step content
                    if currentStep < steps.count {
                        let step = steps[currentStep]

                        if step.isWelcomeStep {
                            welcomeStepContent
                        } else {
                            tourStepContent(step: step)
                        }
                    }

                    Spacer()

                    // Page indicators (tour steps only, not welcome)
                    if !isOnWelcomeStep {
                        HStack(spacing: 8) {
                            ForEach(0..<tourStepCount, id: \.self) { index in
                                let isActive = index == (tourStepNumber - 1)
                                Capsule()
                                    .fill(isActive ? Theme.primaryGold : Color.white.opacity(0.3))
                                    .frame(width: isActive ? 24 : 8, height: 8)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
                            }
                        }
                        .padding(.bottom, 24)
                    }

                    // Action button
                    Button(action: { advanceOrComplete() }) {
                        Text(actionButtonLabel)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Theme.primaryGold, Theme.deepGold],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(25)
                            .shadow(color: Theme.deepGold.opacity(0.4), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, isOnWelcomeStep ? 60 : 16)
                    .opacity(isOnWelcomeStep ? (welcomeMessageVisible ? 1 : 0) : (contentVisible ? 1 : 0))
                    .offset(y: isOnWelcomeStep ? (welcomeMessageVisible ? 0 : 15) : (contentVisible ? 0 : 15))

                    // Spacer for tab bar area on tour steps
                    if !isOnWelcomeStep {
                        Spacer().frame(height: 80)
                    }
                }

                // Arrow pointer - separate ZStack layer anchored to geometry bottom
                if currentStep < steps.count && !steps[currentStep].isWelcomeStep {
                    let step = steps[currentStep]
                    let tabCount: CGFloat = 5
                    let targetTab = CGFloat(step.targetTab)
                    let tabWidth = geo.size.width / tabCount
                    // Nudge Home tab arrow right to align with iOS 26 tab bar layout
                    let homeNudge: CGFloat = step.targetTab == 0 ? 8 : 0
                    let arrowX = tabWidth * targetTab + tabWidth / 2 + homeNudge
                    let safeBottom = geo.safeAreaInsets.bottom
                    // Position arrow just above the tab bar icons
                    let arrowY = geo.size.height - safeBottom - 28

                    VStack(spacing: 2) {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.primaryGold)
                            .shadow(color: Theme.primaryGold.opacity(0.6), radius: 6, x: 0, y: 2)
                            .offset(y: arrowBounce ? 4 : -2)

                        Text(tabLabel(for: step.targetTab))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.primaryGold)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .position(x: arrowX, y: arrowY)
                }
            }
        }
        .onAppear {
            // Navigate to the first step's tab
            if steps.count > 0 {
                onStepChanged(steps[0].targetTab)
            }
            if isOnWelcomeStep {
                startWelcomeAnimations()
            } else {
                animateContentIn()
            }
            startArrowBounce()
        }
    }

    // MARK: - Welcome Step Content

    private var welcomeStepContent: some View {
        VStack(spacing: 24) {
            // Welcome icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGold, Theme.deepGold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)

                Image(systemName: "party.popper.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(welcomeContentVisible ? 1.1 : 0.8)
            .opacity(welcomeContentVisible ? 1 : 0)

            // Welcome text
            VStack(spacing: 6) {
                Text("Welcome to")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)

                Text("Dumpling House")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 2)

                Text("Rewards")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
            }
            .multilineTextAlignment(.center)
            .opacity(welcomeContentVisible ? 1 : 0)
            .offset(y: welcomeContentVisible ? 0 : 20)

            // Points earned
            VStack(spacing: 12) {
                Text("+5")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryGold)
                    .scaleEffect(welcomePointsVisible ? 1.2 : 0.8)

                Text("Welcome Points!")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
            }
            .opacity(welcomePointsVisible ? 1 : 0)
            .offset(y: welcomePointsVisible ? 0 : 20)

            // Message
            VStack(spacing: 16) {
                Text("Thanks for signing up!")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .multilineTextAlignment(.center)

                Text("Scan receipts to earn more points and unlock exclusive rewards.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, 32)
            .opacity(welcomeMessageVisible ? 1 : 0)
            .offset(y: welcomeMessageVisible ? 0 : 20)
        }
    }

    // MARK: - Tour Step Content

    private func tourStepContent(step: WalkthroughStep) -> some View {
        VStack(spacing: 24) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [step.iconColor, step.iconColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .shadow(color: step.iconColor.opacity(0.4), radius: 16, x: 0, y: 8)

                Image(systemName: step.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(contentVisible ? 1.0 : 0.7)
            .opacity(contentVisible ? 1 : 0)

            // Step number
            Text("Step \(tourStepNumber) of \(tourStepCount)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.primaryGold)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .opacity(contentVisible ? 1 : 0)

            // Title
            VStack(spacing: 6) {
                Text(step.title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 2)

                Text(step.subtitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 2)
            }
            .multilineTextAlignment(.center)
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 15)

            // Description
            Text(step.description)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 15)
        }
    }

    // MARK: - Action Button Label

    private var actionButtonLabel: String {
        if isOnWelcomeStep {
            return "Let's Go!"
        } else if currentStep == steps.count - 1 {
            return "Get Started"
        } else {
            return "Next"
        }
    }

    // MARK: - Actions

    private func advanceOrComplete() {
        guard !isTransitioning else { return }

        if isOnWelcomeStep {
            claimPointsAndAdvance()
        } else if currentStep == steps.count - 1 {
            onComplete()
        } else {
            transitionToStep(currentStep + 1)
        }
    }

    private func goBack() {
        guard !isTransitioning, !isOnWelcomeStep, currentStep > firstTourStep else { return }
        transitionToStep(currentStep - 1)
    }

    private func skipWalkthrough() {
        // If still on welcome step and haven't claimed yet, claim before dismissing
        if isOnWelcomeStep && !welcomePointsClaimed {
            welcomePointsClaimed = true
            onClaimWelcomePoints()
        }
        onComplete()
    }

    private func claimPointsAndAdvance() {
        guard !isTransitioning else { return }

        if !welcomePointsClaimed {
            welcomePointsClaimed = true
            onClaimWelcomePoints()
        }

        // Stop confetti
        confettiTimer?.invalidate()
        confettiTimer = nil

        transitionToStep(currentStep + 1)
    }

    private func transitionToStep(_ newStep: Int) {
        guard newStep >= 0, newStep < steps.count else { return }
        isTransitioning = true

        // Fade out current content
        withAnimation(.easeOut(duration: 0.2)) {
            contentVisible = false
            welcomeContentVisible = false
            welcomePointsVisible = false
            welcomeMessageVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            currentStep = newStep
            onStepChanged(steps[newStep].targetTab)

            if steps[newStep].isWelcomeStep {
                startWelcomeAnimations()
            } else {
                animateContentIn()
            }
            isTransitioning = false
        }
    }

    // MARK: - Animations

    private func animateContentIn() {
        contentVisible = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
            contentVisible = true
        }
    }

    private func startWelcomeAnimations() {
        createConfetti()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                welcomeContentVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                welcomePointsVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                welcomeMessageVisible = true
            }
        }
    }

    private func createConfetti() {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        confettiPieces = []

        for _ in 0..<50 {
            confettiPieces.append(WalkthroughConfettiPiece(
                x: Double.random(in: 0...UIScreen.main.bounds.width),
                y: -50,
                rotation: Double.random(in: 0...360),
                scale: Double.random(in: 0.5...1.5),
                color: colors.randomElement() ?? .red,
                velocity: Double.random(in: 100...300),
                angularVelocity: Double.random(in: -5...5)
            ))
        }

        confettiTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                for i in confettiPieces.indices {
                    confettiPieces[i].y += confettiPieces[i].velocity * 0.05
                    confettiPieces[i].rotation += confettiPieces[i].angularVelocity
                }
                confettiPieces.removeAll { $0.y > UIScreen.main.bounds.height + 50 }
                if confettiPieces.isEmpty {
                    confettiTimer?.invalidate()
                    confettiTimer = nil
                }
            }
        }
    }

    private func startArrowBounce() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            arrowBounce = true
        }
    }

    private func tabLabel(for tab: Int) -> String {
        switch tab {
        case 0: return "Home"
        case 1: return "Menu"
        case 2: return "Scan Receipt"
        case 3: return "Rewards"
        case 4: return "More"
        default: return ""
        }
    }
}

// MARK: - Preview

#Preview {
    WalkthroughOverlayView(
        includeWelcome: true,
        onComplete: {},
        onStepChanged: { _ in },
        onClaimWelcomePoints: {}
    )
}
