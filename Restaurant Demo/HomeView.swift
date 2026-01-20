import SwiftUI
import Combine
import MapKit
import CoreLocation
import UIKit
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import os

// MARK: - Notification Names
extension Notification.Name {
    static let showWelcomePopup = Notification.Name("showWelcomePopup")
    static let didEarnPoints = Notification.Name("didEarnPoints")
    static let showLifetimePoints = Notification.Name("showLifetimePoints")
}

// Using Config.swift for backend URL configuration

// MARK: - Shimmer Effect View moved to LoadingComponents.swift

struct HomeView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var sharedRewardsVM: RewardsViewModel
    @AppStorage("isLoggedIn") private var isLoggedIn = true
    
    // MARK: - Colors (using enhanced Theme)
    private let modernPrimary = Theme.modernPrimary
    private let modernAccent = Theme.modernAccent
    private let modernGold = Theme.primaryGold
    private let modernBackground = Theme.modernBackground
    private let modernCard = Theme.modernCard
    private let modernSecondary = Theme.modernSecondary
    
    // MARK: - State Variables
    @State private var animatedPoints: Double = 0.0
    @State private var timer: AnyCancellable?
    @State private var mapCameraPosition: MapCameraPosition
    // ✅ NEW: State to control the visibility of the sign-out alert.
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var glimmerOpacity: Double = 0
    @State private var lastScroll: Date = Date()
    @State private var scrollOffset: CGFloat = 0
    @State private var time: Double = 0
    @State private var glimmerPhase: CGFloat = 0
    @State private var showAccountCustomization = false
    @State private var showDetailedRewards = false

    @State private var showUserPreferences = false
    @State private var showAdminOffice = false
    @State private var showRewardTierAdmin = false  // NEW: Reward tier item configuration
    @State private var showAdminNotifications = false  // NEW: Admin notifications
    @State private var showRewardsScan = false
    @State private var showPointsEarnedOverlay = false
    @State private var lastPointsEarned = 0
    @State private var pointsAnimationStarted = false
    // Replaced array with explicit flags for clarity
    @State private var headerAnimated = false
    @State private var pointsAnimated = false
    @State private var carouselAnimated = false
    @State private var rewardsAnimated = false
    @State private var showReferral = false
    @State private var deepLinkReferralCode: String? = nil
    @State private var showReferralAwardAlert = false
    @State private var crowdAnimated = false
    @State private var locationAnimated = false
    @State private var adminAnimated = false
    // Back-compat convenience for read-only usages that haven’t been migrated yet
    private var cardAnimations: [Bool] {
        [pointsAnimated, rewardsAnimated, crowdAnimated, locationAnimated, adminAnimated]
    }
    @State private var gradientOffset: Double = 0
    @State private var heroOffset: CGFloat = 400 // Start off-screen to the right
    @State private var showHeroMessage = false
    @State private var showChatbot = false
    @State private var showOrderHandoff = false
    @State private var showMapsAlert = false
    @State private var showEmployeesOnlySheet = false
    @State private var showLifetimePointsSheet = false
    @State private var showReceiptScanner = false
    @State private var showPointsHistorySheet = false
    // Glimmer timer (separate from points animation timer)
    @State private var glimmerTimer: Timer? = nil
    
    // Performance signposts (visible in Instruments → Points of Interest)
    private let perfLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "RestaurantDemo", category: "Perf")
    
    // Animation coordination states
    @State private var launchAnimationComplete = false
    
    // MARK: - Integrated Welcome State
    @State private var showIntegratedWelcome = false
    @State private var welcomeAnimationComplete = false
    @State private var welcomeConfettiPieces: [WelcomeConfettiPiece] = []
    @State private var welcomeConfettiTimer: Timer? = nil
    @State private var welcomeContentVisible = false
    @State private var welcomePointsVisible = false
    @State private var welcomeMessageVisible = false
    
    // Points earned animation states
    
    // Hero animation states
    
    // Dumpling animation and web view states
    
    // Maps selection state
    
    // MARK: - Location Constants
    private let locationCoordinate = CLLocationCoordinate2D(latitude: 36.13663, longitude: -86.80233)
    private let phoneNumber = "+16158914728"
    private let address = "2117 Belcourt Ave, Nashville, TN 37212"
    

    
    @Environment(\.colorScheme) var colorScheme

    // Staff-only: listen for any pending reward redemption so we can surface the scanner card immediately.
    @StateObject private var adminPendingRewardsVM = AdminPendingRewardsViewModel()
    
    init() {
        _mapCameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: locationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        let content = ZStack {
            // Dutch Bros style background with energy
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

            if colorScheme == .light && glimmerOpacity > 0 {
                Color.black
                    .opacity(0.15 * glimmerOpacity) // Reduced from 0.36 to 0.15 for less dark background
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.7), value: glimmerOpacity)
            }

            // Glimmer overlay (paused while referral sheet is showing to reduce stacked animations)
            if !showReferral {
                JellyGlimmerView(
                    scrollOffset: scrollOffset,
                    time: time,
                    colorScheme: colorScheme,
                    pop: true
                )
                .opacity(glimmerOpacity)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.7), value: glimmerOpacity)
                .allowsHitTesting(false)
            }
            
            // Points earned overlay
            if showPointsEarnedOverlay {
                VStack {
                    Text("+\(lastPointsEarned)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                        .overlay(
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("points")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.leading, 8)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeInOut(duration: 0.5)) { 
                                    showPointsEarnedOverlay = false 
                                }
                            }
                        }
                    Spacer()
                }
                .padding(.top, 80)
            }
            
            ScrollView {
                VStack(spacing: 25) {
                    if userVM.isLoading {
                        Spacer()
                        ProgressView("Loading Profile...")
                            .scaleEffect(1.2)
                        Spacer()
                    } else {
                        // MARK: - Priority: Rewards Scanner (staff only)
                        if (userVM.isAdmin || userVM.isEmployee), let pending = adminPendingRewardsVM.pendingReward {
                            RewardsScannerPriorityCard(
                                rewardTitle: pending.rewardTitle.isEmpty ? nil : pending.rewardTitle,
                                onTap: { showRewardsScan = true }
                            )
                            .padding(.horizontal, 20)
                        }

                        // MARK: - Unified Greeting + Points Card
                        UnifiedGreetingPointsCard(
                            animatedPoints: animatedPoints,
                            animate: $pointsAnimated,
                            onOrder: { openOrderView() },
                            onRedeem: { showDetailedRewards = true },
                            onScan: { showReceiptScanner = true },
                            onDirections: { showMapsAlert = true },
                            onRefer: {
                                print("🔗 HomeView: onRefer closure invoked")
                                showReferral = true
                            }
                        )
                        .environmentObject(userVM)
                        
                        // MARK: - Just For You Section
                        HStack(spacing: 8) {
                            Text("Just For You,")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                            
                            HStack(spacing: 6) {
                                Text(userVM.firstName.isEmpty ? "Friend" : userVM.firstName)
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundStyle(Theme.darkGoldGradient)
                                
                                if userVM.isVerified {
                                    Image("verified")
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        
                        // MARK: - Promo Carousel (Admin-editable)
                        PromoCarouselCard(
                            isActive: !showReferral,
                            openOrder: { openOrderView() },
                            openScan: { showReceiptScanner = true },
                            openRewards: { showDetailedRewards = true },
                            openCommunity: { NotificationCenter.default.post(name: .switchToMoreTab, object: nil) },
                            openPersonalizedCombo: {
                                // Navigate to menu tab and maybe present personalized combo flow if present
                                NotificationCenter.default.post(name: Notification.Name("switchToHomeTab"), object: nil)
                                // Could post another notification to trigger combo UI if implemented
                            }
                        )
                        .environmentObject(userVM)
                        .scaleEffect(carouselAnimated ? 1.0 : 0.9)
                        .opacity(carouselAnimated ? 1.0 : 0.0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: carouselAnimated)
                        
                        // MARK: - Rewards Section (extracted component)
                        HomeRewardsSection(
                            showDetailedRewards: $showDetailedRewards,
                            animate: $rewardsAnimated,
                            animatedPoints: animatedPoints
                        )
                        .environmentObject(sharedRewardsVM)
                        .environmentObject(userVM)
                        
                        // MARK: - Crowd Meter Card
                        CrowdMeterCard()
                            .scaleEffect(crowdAnimated ? 1.0 : 0.8)
                            .opacity(crowdAnimated ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: crowdAnimated)
                        
                        // MARK: - Location Section
                        HomeLocationSection(
                            mapCameraPosition: $mapCameraPosition,
                            locationCoordinate: locationCoordinate,
                            animate: $locationAnimated,
                            makeCall: makeCall,
                            openDirections: openDirections,
                            openOrder: { openOrderView() }
                        )
                        
                        // Pinned Post Card removed per request
                        
                        // MARK: - Admin Section
                        HomeAdminSection(
                            animate: $adminAnimated,
                            openAdminOffice: { showAdminOffice = true },
                            openRewardsScan: { showRewardsScan = true },
                            openRewardTierAdmin: { showRewardTierAdmin = true },
                            openAdminNotifications: { showAdminNotifications = true }
                        )
                        .environmentObject(userVM)

                        PoweredByFooterView()
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 20)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global).minY) { newY in
                                scrollOffset = newY
                                withAnimation(.easeInOut(duration: 0.7)) {
                                    glimmerOpacity = 1
                                }
                                lastScroll = Date()
                            }
                    }
                )
            }
            // Employees-Only Floating Button (Dutch Bros Style)
            if userVM.isEmployee {
                VStack {
                    Spacer()
                    Button(action: {
                        showEmployeesOnlySheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12, weight: .black))
                            Text("EMPLOYEES ONLY")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .tracking(0.5)
                            Text("😎")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Theme.energyGradient)
                                .shadow(color: Theme.energyOrange.opacity(0.4), radius: 12, x: 0, y: 6)
                        )
                    }
                    .padding(.bottom, 20)
                }
                .transition(.scale)
            }
            // Hero Animation - Always on top
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if showHeroMessage {
                            Button(action: {
                                showChatbot = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .black))
                                    Text("Dumpling Hero is here to help!")
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                        .tracking(0.3)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .black))
                                }
                                .foregroundColor(Theme.primaryGold)
                                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.white)
                                        .overlay(
                                            Capsule()
                                                .stroke(Theme.primaryGold, lineWidth: 2)
                                        )
                                        .shadow(color: Theme.primaryGold.opacity(0.3), radius: 8, x: 0, y: 4)
                                )
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        Button(action: {
                            showChatbot = true
                        }) {
                            Image("newhero")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64, alignment: .trailing)
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .offset(x: heroOffset)
                    }
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 100) // Reduced space - closer to tab bar
            }
            .zIndex(1000) // Ensure it's always on top
        }
        
        let lifecycle = content
            .onAppear(perform: setupView)
            .onChange(of: userVM.points) { oldValue, newValue in
                let oldPoints = Double(oldValue)
                let newPoints = Double(newValue)
                
                // Skip if values are the same (no change)
                guard abs(oldPoints - newPoints) > 0.01 else { return }
                
                // Don't animate on initial load (handled by startCountingAnimation)
                if oldValue == 0 && newValue > 0 && !pointsAnimationStarted {
                    return
                }
                
                // Animate from current animatedPoints to new value
                // This handles both increases and decreases efficiently
                animatePointsTo(targetValue: newPoints, fromCurrent: animatedPoints)
            }
            .onChange(of: userVM.isAdmin) { _, _ in
                adminPendingRewardsVM.setListeningEnabled(userVM.isAdmin || userVM.isEmployee)
            }
            .onChange(of: userVM.isEmployee) { _, _ in
                adminPendingRewardsVM.setListeningEnabled(userVM.isAdmin || userVM.isEmployee)
            }
            .onDisappear {
                // Clean up timers to prevent memory leaks
                timer?.cancel()
                glimmerTimer?.invalidate()
                glimmerTimer = nil
                welcomeConfettiTimer?.invalidate()
                welcomeConfettiTimer = nil
            }
        
        let notifications = lifecycle
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("showAvatarOptions"))) { _ in
                // Back-compat: route legacy avatar notifications to the full-screen More tab
                NotificationCenter.default.post(name: .switchToMoreTab, object: nil)
            }
        
        let alerts = notifications
            // ✅ NEW: An alert modifier that presents a confirmation dialog
            // when `showSignOutConfirmation` is true.
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Confirm", role: .destructive) {
                    // The sign-out logic is now here.
                    userVM.signOut()
                    isLoggedIn = false
                }
                // A "Cancel" button is included automatically.
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
                Button("Delete", role: .destructive) {
                    // Delete account logic
                    userVM.deleteAccount { success in
                        if success {
                            // Account deleted successfully, sign out and return to auth flow
                            userVM.signOut()
                            isLoggedIn = false
                        } else {
                            // Handle deletion failure - could show an error message
                            print("❌ Failed to delete account")
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone and will permanently remove all your data, points, and profile information.")
            }
        
        let referralHandling = alerts
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("incomingReferralCode"))) { output in
                if let code = output.userInfo?["code"] as? String, !code.isEmpty {
                    print("📩 HomeView: incomingReferralCode -> \(code)")
                    deepLinkReferralCode = code
                    showReferral = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("presentReferral"))) { _ in
                print("📩 HomeView: presentReferral notification received")
                showReferral = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("referralAwardGranted"))) { note in
                print("🎉 HomeView: referralAwardGranted -> \(note.userInfo?["bonus"] ?? 0)")
                showReferralAwardAlert = true
            }
            // Referral sheet (moved out of alert scope)
            .sheet(isPresented: $showReferral) {
                ReferralView(initialCode: deepLinkReferralCode)
                    .environmentObject(userVM)
            }
            .alert("Referral Bonus Awarded!", isPresented: $showReferralAwardAlert) {
                Button("Nice!") { showReferralAwardAlert = false }
            } message: {
                Text("You just received +50 referral bonus points.")
            }
        
        let running = referralHandling
            .onAppear {
                // Animate glimmer phase
                withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                    glimmerPhase = 1
                }
                // Start glimmer timer (will auto-pause when referral sheet is visible)
                startGlimmerTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .didEarnPoints)) { notification in
                if let points = notification.userInfo?["points"] as? Int {
                    // Always show the overlay for earned points; animation function is internally no-op if needed.
                    animatePointsEarned(points)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showLifetimePoints)) { _ in
                showLifetimePointsSheet = true
            }
        
        return running
        .sheet(isPresented: $showAccountCustomization) {
            AccountCustomizationView(uid: Auth.auth().currentUser?.uid ?? "")
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showDetailedRewards) {
            UnifiedRewardsScreen(mode: .modal)
                .environmentObject(userVM)
                .environmentObject(sharedRewardsVM)
        }
        .sheet(isPresented: $showReceiptScanner) {
            ReceiptScanView()
        }
        .sheet(isPresented: $showPointsHistorySheet) {
            PointsHistoryView()
        }
        .sheet(isPresented: $showUserPreferences) {
            UserPreferencesView(uid: Auth.auth().currentUser?.uid ?? "")
                .environmentObject(userVM)
        }
        .sheet(isPresented: $showChatbot) {
            ChatbotView()
        }
        .sheet(isPresented: $showAdminOffice) {
            AdminOfficeView()
        }
        .sheet(isPresented: $showRewardTierAdmin) {
            RewardTierAdminView()
        }
        .sheet(isPresented: $showAdminNotifications) {
            AdminNotificationsView()
        }
        .sheet(isPresented: $showRewardsScan) {
            AdminRewardsScanView()
                .environmentObject(userVM)
        }
        .sheet(isPresented: $showEmployeesOnlySheet) {
            EmployeesOnlyHomeView()
                .environmentObject(userVM)
                .environmentObject(sharedRewardsVM)
        }
        .sheet(isPresented: $showLifetimePointsSheet) {
            LifetimePointsView()
                .environmentObject(userVM)
        }

        .alert("Choose Navigation App", isPresented: $showMapsAlert) {
            Button("Apple Maps") {
                openAppleMaps()
            }
            Button("Google Maps") {
                openGoogleMaps()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Select your preferred navigation app to get directions to Dumpling House")
        }
        .overlay(
            // Integrated Welcome Overlay - shown for new users
            ZStack {
                if showIntegratedWelcome {
                    // Semi-transparent background - darker for better text contrast
                    Color.black.opacity(0.75)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    // Confetti pieces
                    ForEach(welcomeConfettiPieces) { piece in
                        Circle()
                            .fill(piece.color)
                            .frame(width: 8, height: 8)
                            .position(x: piece.x, y: piece.y)
                            .rotationEffect(.degrees(piece.rotation))
                            .scaleEffect(piece.scale)
                    }
                    
                    // Main welcome content
                    VStack(spacing: 24) {
                        Spacer()
                        
                        // Welcome icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.85, green: 0.65, blue: 0.25), Color(red: 0.75, green: 0.55, blue: 0.15)],
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
                            
                            Text("Dumpling House")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Rewards")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.darkGoldGradient)
                        }
                        .multilineTextAlignment(.center)
                        .opacity(welcomeContentVisible ? 1 : 0)
                        .offset(y: welcomeContentVisible ? 0 : 20)
                        
                        // Points earned
                        VStack(spacing: 12) {
                            Text("+5")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.25))
                                .scaleEffect(welcomePointsVisible ? 1.2 : 0.8)
                            
                            Text("Welcome Points!")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .opacity(welcomePointsVisible ? 1 : 0)
                        .offset(y: welcomePointsVisible ? 0 : 20)
                        
                        // Message
                        VStack(spacing: 16) {
                            Text("Thanks for signing up!")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Scan receipts to earn more points and unlock exclusive rewards.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 32)
                        .opacity(welcomeMessageVisible ? 1 : 0)
                        .offset(y: welcomeMessageVisible ? 0 : 20)
                        
                        Spacer()
                        
                        // Done button
                        Button(action: {
                            dismissIntegratedWelcome()
                        }) {
                            Text("Let's Go!")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.85, green: 0.65, blue: 0.25), Color(red: 0.75, green: 0.55, blue: 0.15)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                                .shadow(color: Color(red: 0.75, green: 0.55, blue: 0.15).opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 60)
                        .opacity(welcomeMessageVisible ? 1 : 0)
                        .offset(y: welcomeMessageVisible ? 0 : 20)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showIntegratedWelcome)
        )
        .sheet(isPresented: $showOrderHandoff) {
            if let url = URL(string: "https://dumplinghousetn.kwickmenu.com/") {
                SimplifiedSafariView(
                    url: url,
                    onDismiss: { showOrderHandoff = false }
                )
            }
        }
        .onChange(of: showDetailedRewards) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "RewardsModal")
        }
        .onChange(of: showReferral) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "ReferralModal")
        }
        .onChange(of: showAccountCustomization) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "AccountCustomizationModal")
        }
        .onChange(of: showReceiptScanner) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "ReceiptScannerModal")
        }
        .onChange(of: showPointsHistorySheet) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "PointsHistoryModal")
        }
        .onChange(of: showUserPreferences) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "UserPreferencesModal")
        }
        .onChange(of: showChatbot) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "ChatbotModal")
        }
        .onChange(of: showAdminOffice) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "AdminOfficeModal")
        }
        .onChange(of: showRewardTierAdmin) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "RewardTierAdminModal")
        }
        .onChange(of: showAdminNotifications) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "AdminNotificationsModal")
        }
        .onChange(of: showEmployeesOnlySheet) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "EmployeesOnlyModal")
        }
        .onChange(of: showLifetimePointsSheet) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "LifetimePointsModal")
        }
        .onChange(of: showOrderHandoff) { _, isShowing in
            handleOverlayPresentationChange(isPresented: isShowing, name: "OrderHandoffModal")
        }
    }
    
    // MARK: - Overlay / Background Work Coordination
    
    private var isAnyOverlayPresented: Bool {
        showReferral ||
        showDetailedRewards ||
        showAccountCustomization ||
        showReceiptScanner ||
        showPointsHistorySheet ||
        showUserPreferences ||
        showChatbot ||
        showAdminOffice ||
        showRewardTierAdmin ||
        showAdminNotifications ||
        showEmployeesOnlySheet ||
        showLifetimePointsSheet ||
        showOrderHandoff
    }
    
    /// Pauses or resumes Home background work (timers, animations) so modals like Rewards stay smooth.
    private func handleOverlayPresentationChange(isPresented: Bool, name: StaticString) {
        if isPresented {
            os_signpost(.begin, log: perfLog, name: name)
        } else {
            os_signpost(.end, log: perfLog, name: name)
        }
        
        if isAnyOverlayPresented {
            // Pause work that can cause frequent re-rendering while sheets are on top.
            timer?.cancel()
            timer = nil
            glimmerTimer?.invalidate()
            glimmerTimer = nil
            welcomeConfettiTimer?.invalidate()
            welcomeConfettiTimer = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                glimmerOpacity = 0
            }
        } else {
            // Resume lightweight work only when we’re truly back on Home.
            startGlimmerTimer()
            animatedPoints = Double(userVM.points)
        }
    }
    
    // MARK: - Helper Views
    
    private var avatarView: some View {
        ZStack {
            if let profileImage = userVM.profileImage {
                profileImageView(profileImage)
            } else {
                emojiAvatarView
            }
        }
        .onTapGesture {
            NotificationCenter.default.post(name: .switchToMoreTab, object: nil)
        }
    }
    
    private func profileImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 78, height: 78)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
            .scaleEffect(headerAnimated ? 1.0 : 0.8)
            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3), value: headerAnimated)
    }
    
    private var emojiAvatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            userVM.avatarColor,
                            userVM.avatarColor.opacity(0.8),
                            userVM.avatarColor.opacity(0.9)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 78, height: 78)
                .shadow(color: userVM.avatarColor.opacity(0.4), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
                .scaleEffect(headerAnimated ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3), value: headerAnimated)
            
            Text(userVM.avatarEmoji)
                .font(.system(size: 38))
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .scaleEffect(headerAnimated ? 1.0 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(1.4), value: headerAnimated)
        }
    }
    
    private var loyaltyStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loyaltyStatus)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6) // Scale down to 60% if needed
                .lineLimit(1) // Ensure single line
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    loyaltyStatusColor,
                                    loyaltyStatusColor.opacity(0.8)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: loyaltyStatusColor.opacity(0.4), radius: 8, x: 0, y: 4)
                )
                .opacity(headerAnimated ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.5), value: headerAnimated)
            
            Text("Lifetime: \(userVM.lifetimePoints)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(modernSecondary)
                .opacity(headerAnimated ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.6), value: headerAnimated)
        }
    }
    
    private var pointsCounterView: some View {
        VStack(spacing: 6) {
            Text("\(Int(animatedPoints))")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(modernPrimary)
                .minimumScaleFactor(0.3) // Scale down to 30% if needed for better fit
                .lineLimit(1) // Ensure single line
                .multilineTextAlignment(.center) // Center align for better appearance
                .animation(.easeInOut(duration: 0.3), value: animatedPoints)
                .scaleEffect(pointsAnimated ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.7), value: pointsAnimated)
            
            Text("POINTS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(modernSecondary)
                .tracking(1.5)
                .opacity(pointsAnimated ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.8), value: pointsAnimated)
        }
        .frame(maxWidth: .infinity) // Allow full width usage
        .frame(minHeight: 60) // Minimum height to maintain layout
    }
    
    private var progressBarView: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                // Background container
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.04),
                                Color.black.opacity(0.02)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 14)
                    .overlay(
                        // Border drawn on top to ensure it's visible
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                
                // Progress bar fill - clipped to container shape
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                progressBarColor,
                                progressBarColor.opacity(0.8),
                                progressBarColor.opacity(0.9),
                                progressBarColor
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(CGFloat(animatedPoints / 2000.0) * (UIScreen.main.bounds.width - 120), UIScreen.main.bounds.width - 120)), height: 14)
                    .shadow(color: progressBarColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    .animation(.easeInOut(duration: 0.5), value: animatedPoints)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            HStack {
                Text("0")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(modernSecondary)
                    .opacity(pointsAnimated ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.5).delay(1.9), value: pointsAnimated)
                
                Spacer()
                
                Text("2,000")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(modernSecondary)
                    .opacity(pointsAnimated ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.5).delay(2.0), value: pointsAnimated)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    // Loyalty status based on lifetime points
    private var loyaltyStatus: String {
        switch userVM.lifetimePoints {
        case 0..<1000:
            return "BRONZE"
        case 1000..<5000:
            return "SILVER"
        case 5000..<15000:
            return "GOLD"
        default:
            return "PLATINUM"
        }
    }
    
    private var loyaltyStatusColor: Color {
        switch loyaltyStatus {
        case "BRONZE":
            return Color(red: 0.8, green: 0.5, blue: 0.2)
        case "SILVER":
            return Color(red: 0.7, green: 0.7, blue: 0.7)
        case "GOLD":
            return Color(red: 1.0, green: 0.8, blue: 0.0)
        case "PLATINUM":
            return Color(red: 0.9, green: 0.9, blue: 1.0)
        default:
            return .gray
        }
    }
    
    private var progressBarColor: Color {
        let points = Int(animatedPoints)
        
        // Use the same colors as reward cards for smooth transitions
        let colors: [Color] = [
            .orange,    // 250 pts - Peanut Sauce
            .blue,      // 450 pts - Fruit Tea, Milk Tea, Lemonade, Coffee
            .green,     // 500 pts - Small Appetizer
            .purple,    // 650 pts - Larger Appetizer
            .pink,      // 850 pts - Pizza Dumplings
            .indigo,    // 850 pts - Lunch Special
            .brown,     // 1500 pts - 12-Piece Dumplings
            Color(red: 1.0, green: 0.84, blue: 0.0)  // 2000 pts - Full Combo (gold)
        ]
        
        // Smooth color transitions based on points
        let maxPoints = 2000.0
        let progress = min(Double(points) / maxPoints, 1.0)
        let colorIndex = min(Int(progress * Double(colors.count - 1)), colors.count - 1)
        
        // Interpolate between colors for smooth transitions
        if colorIndex < colors.count - 1 {
            let currentColor = colors[colorIndex]
            let nextColor = colors[colorIndex + 1]
            let localProgress = (progress * Double(colors.count - 1)) - Double(colorIndex)
            
            return interpolateColor(from: currentColor, to: nextColor, progress: localProgress)
        } else {
            return colors[colorIndex]
        }
    }
    
    // Helper function to interpolate between colors
    private func interpolateColor(from: Color, to: Color, progress: Double) -> Color {
        let fromComponents = UIColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = UIColor(to).cgColor.components ?? [0, 0, 0, 1]
        
        let red = fromComponents[0] + (toComponents[0] - fromComponents[0]) * CGFloat(progress)
        let green = fromComponents[1] + (toComponents[1] - fromComponents[1]) * CGFloat(progress)
        let blue = fromComponents[2] + (toComponents[2] - fromComponents[2]) * CGFloat(progress)
        let alpha = fromComponents[3] + (toComponents[3] - fromComponents[3]) * CGFloat(progress)
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
    
    private var loyaltyProgressPercentage: Double {
        let currentPoints = userVM.lifetimePoints
        switch loyaltyStatus {
        case "BRONZE":
            return min(Double(currentPoints) / 1000.0, 1.0)
        case "SILVER":
            return min(Double(currentPoints - 1000) / 4000.0, 1.0)
        case "GOLD":
            return min(Double(currentPoints - 5000) / 10000.0, 1.0)
        case "PLATINUM":
            return 1.0 // Platinum is max level
        default:
            return 0.0
        }
    }
    
    private func rewardCard(title: String, description: String, pointsRequired: Int, currentPoints: Int, color: Color) -> some View {
        let isEligible = currentPoints >= pointsRequired
        
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("\(pointsRequired) points")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
            }
            
            Spacer()
            
            Button(action: {
                // Handle reward claim
                print("Claiming reward: \(title)")
            }) {
                Text(isEligible ? "Claim" : "Locked")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isEligible ? color : .gray)
                    )
            }
            .disabled(!isEligible)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color,
                                color.opacity(0.85),
                                color.opacity(0.9),
                                color
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
    }

    private func makeCall() {
        if let url = URL(string: "tel:\(phoneNumber)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openDirections() {
        showMapsAlert = true
    }
    
    private func openAppleMaps() {
        let coordinate = locationCoordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "Dumpling House"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    private func openGoogleMaps() {
        let coordinate = locationCoordinate
        let urlString = "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving"
        
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to web version of Google Maps
            let webUrlString = "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=driving"
            if let webUrl = URL(string: webUrlString) {
                UIApplication.shared.open(webUrl)
            }
        }
    }
    
    private func openOrderView() {
        // Directly present external ordering site in SafariView
        showOrderHandoff = true
    }
    
    /// Starts or restarts the glimmer timer that drives the JellyGlimmerView background.
    /// This is paused while the referral sheet is visible to avoid unnecessary work under overlays.
    private func startGlimmerTimer() {
        glimmerTimer?.invalidate()
        glimmerTimer = nil
        
        // If referral is currently showing, don't start the timer yet.
        guard !showReferral else { return }
        
        glimmerTimer = Timer.scheduledTimer(withTimeInterval: 1/8, repeats: true) { _ in // OPTIMIZED: Reduced from 15fps to 8fps for lower energy usage
            time += 1/8
            if Date().timeIntervalSince(lastScroll) > 0.7 {
                if glimmerOpacity > 0 {
                    // Fade out much more smoothly and slowly
                    glimmerOpacity = max(0, glimmerOpacity - 0.03) // OPTIMIZED: Increased step size for faster fade
                }
            }
        }
    }
    
    private func setupView() {
        if userVM.isLoading {
            userVM.loadUserData()
        }
        
        // Start listener for active rewards
        if let uid = Auth.auth().currentUser?.uid {
            sharedRewardsVM.startActiveRedemptionListener(userId: uid)
        }

        // Staff listener for any pending reward redemption (drives the priority scanner card)
        adminPendingRewardsVM.setListeningEnabled(userVM.isAdmin || userVM.isEmployee)
        
        // Check if this is a new user who should see the integrated welcome
        // We check after a brief delay to ensure userVM has loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            checkAndShowIntegratedWelcome()
        }
    }
    
    /// Checks if the user should see the integrated welcome and shows it, or starts normal animations
    private func checkAndShowIntegratedWelcome() {
        // Determine if user should see welcome
        // New user OR user with 0 points who hasn't received welcome points yet
        let shouldShowWelcome = userVM.isNewUser || (userVM.points == 0 && !userVM.hasReceivedWelcomePoints && !userVM.isLoading)
        
        print("🎉 HomeView: checkAndShowIntegratedWelcome - isNewUser: \(userVM.isNewUser), points: \(userVM.points), hasReceivedWelcomePoints: \(userVM.hasReceivedWelcomePoints), shouldShowWelcome: \(shouldShowWelcome)")
        
        if shouldShowWelcome && !welcomeAnimationComplete {
            // Show integrated welcome first
            showIntegratedWelcome = true
            startWelcomeAnimations()
        } else {
            // Normal flow - start sequential animations after launch delay
            let remainingDelay = max(0, 1.0) // Reduced delay since we already waited 0.5s
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
                startSequentialAnimations()
            }
        }
    }
    
    /// Starts the welcome celebration animations
    private func startWelcomeAnimations() {
        // Create confetti pieces
        createWelcomeConfetti()
        
        // Animate content in sequence
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
    
    /// Creates confetti pieces for the welcome animation
    private func createWelcomeConfetti() {
        let confettiColors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        welcomeConfettiPieces = []
        
        for _ in 0..<50 {
            let piece = WelcomeConfettiPiece(
                x: Double.random(in: 0...UIScreen.main.bounds.width),
                y: -50,
                rotation: Double.random(in: 0...360),
                scale: Double.random(in: 0.5...1.5),
                color: confettiColors.randomElement() ?? .red,
                velocity: Double.random(in: 100...300),
                angularVelocity: Double.random(in: -5...5)
            )
            welcomeConfettiPieces.append(piece)
        }
        
        // Start confetti animation
        welcomeConfettiTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                for i in self.welcomeConfettiPieces.indices {
                    self.welcomeConfettiPieces[i].y += self.welcomeConfettiPieces[i].velocity * 0.05
                    self.welcomeConfettiPieces[i].rotation += self.welcomeConfettiPieces[i].angularVelocity
                }
                
                // Remove confetti that has fallen off screen
                self.welcomeConfettiPieces.removeAll { piece in
                    piece.y > UIScreen.main.bounds.height + 50
                }
                
                // Stop animation when all confetti is gone
                if self.welcomeConfettiPieces.isEmpty {
                    self.welcomeConfettiTimer?.invalidate()
                    self.welcomeConfettiTimer = nil
                }
            }
        }
    }
    
    /// Dismisses the welcome and starts the main HomeView animations
    private func dismissIntegratedWelcome() {
        // Add welcome points
        userVM.addWelcomePoints { success in
            if success {
                print("✅ Welcome points added successfully")
            } else {
                print("❌ Failed to add welcome points")
            }
        }
        
        // Mark that user is no longer new
        userVM.isNewUser = false
        
        // Update Firestore
        let db = Firestore.firestore()
        if let uid = Auth.auth().currentUser?.uid {
            db.collection("users").document(uid).updateData([
                "isNewUser": false,
                "hasReceivedWelcomePoints": true
            ]) { error in
                if let error = error {
                    print("❌ Error updating user status: \(error.localizedDescription)")
                } else {
                    print("✅ Updated user status after welcome")
                }
            }
        }
        
        // Stop confetti timer
        welcomeConfettiTimer?.invalidate()
        welcomeConfettiTimer = nil
        
        // Mark welcome as complete
        welcomeAnimationComplete = true
        
        // Fade out welcome overlay
        withAnimation(.easeInOut(duration: 0.3)) {
            showIntegratedWelcome = false
        }
        
        // Start the normal HomeView animations after welcome fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Set initial points for animation (will animate from current)
            animatedPoints = Double(userVM.points)
            startSequentialAnimations()
        }
    }
    

    
    private func startSequentialAnimations() {
        // Start with points card animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            headerAnimated = true
            pointsAnimated = true
        }
        
        // Start points counting animation after points card appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !pointsAnimationStarted {
                pointsAnimationStarted = true
                startCountingAnimation(to: Double(userVM.points))
            }
        }
        
        // Animate carousel card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                carouselAnimated = true
            }
        }
        
        // Animate rewards card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                rewardsAnimated = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                crowdAnimated = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                locationAnimated = true
            }
        }

        // Removed pinned post animation

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                adminAnimated = true
            }
        }
        
        // Animate hero sliding in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            print("🎯 Starting hero slide animation")
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                heroOffset = 0
            }
            
            // Show hero message after hero slides in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("💬 Showing hero message")
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showHeroMessage = true
                }
            }
        }
    }
    
    private func startCountingAnimation(to finalValue: Double) {
        timer?.cancel()
        animatedPoints = 0
        guard finalValue > 0 else { return }
        
        // Fixed 3-second duration as requested
        let duration = 3.0
        animatePointsTo(targetValue: finalValue, fromCurrent: 0, duration: duration)
    }
    
    // MARK: - Efficient Points Animation Function
    
    /// Animates points from current value to target value with smooth easing
    /// - Parameters:
    ///   - targetValue: The final points value to animate to
    ///   - fromCurrent: The starting value (defaults to current animatedPoints)
    ///   - duration: Optional custom duration (calculated automatically if nil)
    private func animatePointsTo(targetValue: Double, fromCurrent: Double? = nil, duration: Double? = nil) {
        // Cancel any existing animation to prevent conflicts
        timer?.cancel()
        
        let startValue = fromCurrent ?? animatedPoints
        let endValue = targetValue
        let difference = abs(endValue - startValue)
        
        // Skip animation if difference is negligible
        guard difference > 0.01 else {
            animatedPoints = endValue
            return
        }
        
        // Calculate efficient duration based on difference
        // Small changes: 0.4-0.6s, Medium: 0.7-1.0s, Large: 1.0-1.5s
        let calculatedDuration: Double
        if let customDuration = duration {
            calculatedDuration = customDuration
        } else {
            // Efficient duration calculation - scales smoothly with difference
            let baseDuration = 0.5
            let maxDuration = 1.5
            // Use logarithmic scaling for smooth duration increase
            let scaleFactor = min(log10(max(difference, 1)) / 3.0, 1.0)
            calculatedDuration = baseDuration + (maxDuration - baseDuration) * scaleFactor
        }
        
        let startTime = Date()
        
        // Efficient easing function (easeOutQuart) - fast start, slow end
        func easeOutQuart(_ t: Double) -> Double {
            return 1 - pow(1 - t, 4)
        }

        // Use efficient timer with 60fps (every 0.016s) for smooth animation
        timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect().sink { _ in
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            if elapsedTime >= calculatedDuration {
                // Animation complete - set to exact target value
                animatedPoints = endValue
                timer?.cancel()
                timer = nil
            } else {
                // Calculate animated value using easing
                let progress = min(elapsedTime / calculatedDuration, 1.0)
                let easedProgress = easeOutQuart(progress)
                animatedPoints = startValue + (endValue - startValue) * easedProgress
            }
        }
    }
    
    // MARK: - Points Animation Functions
    
    private func animatePointsEarned(_ points: Int) {
        lastPointsEarned = points
        showPointsEarnedOverlay = true
        
        // Use the efficient animation function instead of simple withAnimation
        let targetPoints = Double(userVM.points)
        animatePointsTo(targetValue: targetPoints)
    }
    
    private func animateWelcomePoints() {
        // For welcome points, animate from current to current + 5
        let targetPoints = animatedPoints + 5.0
        animatePointsTo(targetValue: targetPoints)
    }
    

}

// MARK: - Welcome Confetti Model
struct WelcomeConfettiPiece: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var rotation: Double
    var scale: Double
    var color: Color
    var velocity: Double
    var angularVelocity: Double
}

#Preview {
    HomeView()
}

// MARK: - Reward components moved to RewardsComponents.swift


