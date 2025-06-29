import SwiftUI
import Combine
import MapKit
import CoreLocation
import UIKit
import Firebase
import FirebaseAuth

struct HomeView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @StateObject private var userVM = UserViewModel()
    @AppStorage("isLoggedIn") private var isLoggedIn = true
    
    // MARK: - State Variables
    @State private var animatedPoints: Double = 0.0
    @State private var timer: AnyCancellable?
    @State private var mapCameraPosition: MapCameraPosition
    // ✅ NEW: State to control the visibility of the sign-out alert.
    @State private var showSignOutConfirmation = false
    @State private var glimmerOpacity: Double = 0
    @State private var lastScroll: Date = Date()
    @State private var scrollOffset: CGFloat = 0
    @State private var time: Double = 0
    @State private var glimmerPhase: CGFloat = 0
    @State private var showAvatarOptions = false
    @State private var showAccountCustomization = false
    @State private var showDetailedRewards = false
    
    // Animation coordination states
    @State private var launchAnimationComplete = false
    @State private var pointsAnimationStarted = false
    @State private var cardAnimations: [Bool] = [false, false, false, false] // Points, Rewards, Location, Map
    
    // MARK: - Location Constants
    private let locationCoordinate = CLLocationCoordinate2D(latitude: 36.13663, longitude: -86.80233)
    private let phoneNumber = "+16158914728"
    private let address = "2117 Belcourt Ave, Nashville, TN 37212"
    
    // MARK: - Reward Options
    private var rewardOptions: [RewardOption] {
        [
            RewardOption(title: "Free Appetizer", description: "Any appetizer under $8", pointsRequired: 2000, color: .orange),
            RewardOption(title: "50% Off Entrée", description: "Any entrée on the menu", pointsRequired: 5000, color: .purple),
            RewardOption(title: "Free Dessert", description: "Any dessert of your choice", pointsRequired: 1500, color: .pink),
            RewardOption(title: "Free Drink", description: "Any beverage", pointsRequired: 1000, color: .blue),
            RewardOption(title: "25% Off Order", description: "Entire order discount", pointsRequired: 7500, color: .green),
            RewardOption(title: "Free Delivery", description: "Next order delivery free", pointsRequired: 3000, color: .red)
        ]
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    init() {
        _mapCameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: locationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        ZStack {
            // Main background (adapts to light/dark)
            Color(.systemBackground)
                .ignoresSafeArea()

            if colorScheme == .light && glimmerOpacity > 0 {
                Color.black
                    .opacity(0.36 * glimmerOpacity)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.7), value: glimmerOpacity)
            }

            // Glimmer overlay
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

            ScrollView {
                VStack(spacing: 25) {
                    if userVM.isLoading {
                        Spacer()
                        ProgressView("Loading Profile...")
                            .scaleEffect(1.2)
                        Spacer()
                    } else {
                        // MARK: - Top Header with Welcome and Status
                        HStack(alignment: .center) {
                            // Welcome and Name (Left side)
                            VStack(alignment: .leading, spacing: 4) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Welcome back,")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                        .opacity(cardAnimations[0] ? 1.0 : 0.0)
                                        .animation(.easeInOut(duration: 0.5).delay(0.3), value: cardAnimations[0])
                                    
                                    Text(userVM.firstName)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .opacity(cardAnimations[0] ? 1.0 : 0.0)
                                        .animation(.easeInOut(duration: 0.5).delay(0.4), value: cardAnimations[0])
                                }
                            }
                            .layoutPriority(1)
                            
                            Spacer(minLength: 10)
                            
                            // Logo - fill header height, as big as possible
                            GeometryReader { geo in
                                Image("logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                                    .scaleEffect(cardAnimations[0] ? 1.0 : 0.8)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5), value: cardAnimations[0])
                                    .layoutPriority(2)
                            }
                            .frame(width: 100, height: 100) // Slightly larger frame, but header height controls max size
                        }
                        .frame(minHeight: 60, maxHeight: 100)
                        .padding(.horizontal, 20)
                        .padding(.top, 0)
                        .padding(.bottom, 0)
                        
                        // MARK: - Points Display with Glass Effect
                        VStack(spacing: 20) {
                            // Main Points Display and Avatar
                            HStack(spacing: 20) {
                                avatarView
                                
                                // Lifetime Status and Points (Next to avatar)
                                loyaltyStatusView
                                
                                Spacer()
                                
                                // Points Counter (Rightmost) with enhanced animation
                                pointsCounterView
                            }
                            
                            // Progress Bar with enhanced visual effects
                            progressBarView
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal, 20)
                        .scaleEffect(cardAnimations[0] ? 1.0 : 0.8)
                        .opacity(cardAnimations[0] ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardAnimations[0])
                        
                        // MARK: - Rewards Section
                        VStack(spacing: 20) {
                            HStack {
                                HStack(spacing: 8) {
                                    Text("🎁")
                                        .font(.title2)
                                        .scaleEffect(cardAnimations[1] ? 1.0 : 0.0)
                                        .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: cardAnimations[1])
                                    
                                    Text("Available Rewards")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .opacity(cardAnimations[1] ? 1.0 : 0.0)
                                        .animation(.easeInOut(duration: 0.5).delay(0.3), value: cardAnimations[1])
                                }
                                
                                Spacer()
                                
                                Button("View All") {
                                    // Navigate to detailed rewards view
                                    showDetailedRewards = true
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.blue)
                                .opacity(cardAnimations[1] ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.5).delay(0.4), value: cardAnimations[1])
                            }
                            
                            // Scrollable diagonal rewards with enhanced animations
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    ForEach(Array(rewardOptions.enumerated()), id: \.element.title) { index, reward in
                                        DiagonalRewardCard(
                                            title: reward.title,
                                            description: reward.description,
                                            pointsRequired: reward.pointsRequired,
                                            currentPoints: Int(animatedPoints),
                                            color: reward.color
                                        )
                                        .scaleEffect(cardAnimations[1] ? 1.0 : 0.8)
                                        .opacity(cardAnimations[1] ? 1.0 : 0.0)
                                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5 + Double(index) * 0.1), value: cardAnimations[1])
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .frame(height: 120)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal, 20)
                        .scaleEffect(cardAnimations[1] ? 1.0 : 0.8)
                        .opacity(cardAnimations[1] ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardAnimations[1])
                        
                        // MARK: - Location Card with Glass Effect
                        VStack(spacing: 20) {
                            // Map with Glass Effect and decorative elements
                            ZStack {
                                Map(position: $mapCameraPosition, interactionModes: []) {
                                    Marker("Dumpling House", coordinate: locationCoordinate)
                                }
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(.ultraThinMaterial, lineWidth: 1)
                                )
                                
                                // Location label (no emojis)
                                VStack {
                                    HStack {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.title2)
                                            .foregroundColor(.red)
                                            .scaleEffect(cardAnimations[2] ? 1.0 : 0.0)
                                            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: cardAnimations[2])
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Dumpling House")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .opacity(cardAnimations[2] ? 1.0 : 0.0)
                                                .animation(.easeInOut(duration: 0.5).delay(0.3), value: cardAnimations[2])
                                            
                                            Text("2117 Belcourt Ave")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .opacity(cardAnimations[2] ? 1.0 : 0.0)
                                                .animation(.easeInOut(duration: 0.5).delay(0.4), value: cardAnimations[2])
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(.ultraThinMaterial)
                                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                                    )
                                    .padding(.horizontal, 15)
                                    .padding(.top, 15)
                                    
                                    Spacer()
                                }
                            }

                            // Action Buttons with enhanced animations
                            HStack(spacing: 15) {
                                actionButton(
                                    title: "Call Us",
                                    icon: "phone.fill",
                                    color: Color(red: 0.2, green: 0.8, blue: 0.4),
                                    action: makeCall
                                )
                                .scaleEffect(cardAnimations[2] ? 1.0 : 0.8)
                                .opacity(cardAnimations[2] ? 1.0 : 0.0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.7), value: cardAnimations[2])
                                
                                actionButton(
                                    title: "Directions",
                                    icon: "location.fill",
                                    color: Color(red: 0.2, green: 0.6, blue: 0.9),
                                    action: openDirections
                                )
                                .scaleEffect(cardAnimations[2] ? 1.0 : 0.8)
                                .opacity(cardAnimations[2] ? 1.0 : 0.0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.8), value: cardAnimations[2])
                            }
                            
                            // Order Button with enhanced animation
                            actionButton(
                                title: "Order Now",
                                icon: "bag.fill",
                                color: .orange,
                                action: openOrderView
                            )
                            .scaleEffect(cardAnimations[2] ? 1.0 : 0.8)
                            .opacity(cardAnimations[2] ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.9), value: cardAnimations[2])
                        }
                        .padding(25)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal, 20)
                        .scaleEffect(cardAnimations[2] ? 1.0 : 0.8)
                        .opacity(cardAnimations[2] ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardAnimations[2])
                        
                        Spacer(minLength: 50)
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
        }
        .onAppear(perform: setupView)
        .onChange(of: userVM.points) { oldValue, newValue in
            // Only start animation if we haven't already started it and the launch animation is complete
            if oldValue == 0 && newValue > 0 && !pointsAnimationStarted {
                // Don't start automatically - wait for our coordinated timing
            }
        }
        .onDisappear {
            timer?.cancel()
        }
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
        .onAppear {
            // Animate glimmer phase
            withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                glimmerPhase = 1
            }
            // Timer to fade out glimmer after scrolling stops
            Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
                time += 1/30
                if Date().timeIntervalSince(lastScroll) > 0.7 {
                    if glimmerOpacity > 0 {
                        // Fade out much more smoothly and slowly
                        glimmerOpacity = max(0, glimmerOpacity - 0.01)
                    }
                }
            }
            // Always reload user data and image on appear
            userVM.loadUserData()
            // Force refresh profile image to ensure latest image is shown
            userVM.forceRefreshProfileImage()
            print("🖼️ HomeView: loadUserData() and forceRefreshProfileImage() called")
        }
        .confirmationDialog("Profile Options", isPresented: $showAvatarOptions, titleVisibility: .visible) {
            Button("Edit Profile") {
                showAccountCustomization = true
            }
            Button("Sign Out", role: .destructive) {
                showSignOutConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAccountCustomization) {
            AccountCustomizationView(uid: Auth.auth().currentUser?.uid ?? "")
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showDetailedRewards) {
            DetailedRewardsView(rewardOptions: rewardOptions, currentPoints: Int(animatedPoints))
        }
    }
    
    // MARK: - Helper Views
    
    private var avatarView: some View {
        ZStack {
            // Decorative background glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [userVM.avatarColor.opacity(0.3), Color.clear]),
                        center: .center,
                        startRadius: 25,
                        endRadius: 60
                    )
                )
                .frame(width: 110, height: 110)
                .scaleEffect(cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 1.0).delay(1.2), value: cardAnimations[0])
            
            if let profileImage = userVM.profileImage {
                profileImageView(profileImage)
            } else {
                emojiAvatarView
            }
        }
        .onTapGesture {
            showAvatarOptions = true
        }
    }
    
    private func profileImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 90, height: 90)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .scaleEffect(cardAnimations[0] ? 1.0 : 0.8)
            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3), value: cardAnimations[0])
            .onAppear {
                print("🖼️ HomeView: Profile image displayed")
            }
    }
    
    private var emojiAvatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [userVM.avatarColor, userVM.avatarColor.opacity(0.7)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 90, height: 90)
                .shadow(color: userVM.avatarColor.opacity(0.3), radius: 10, x: 0, y: 5)
                .scaleEffect(cardAnimations[0] ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.3), value: cardAnimations[0])
            
            Text(userVM.avatarEmoji)
                .font(.system(size: 45))
                .shadow(radius: 2)
                .scaleEffect(cardAnimations[0] ? 1.0 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(1.4), value: cardAnimations[0])
        }
        .onAppear {
            print("🖼️ HomeView: No profile image, showing emoji avatar")
        }
    }
    
    private var loyaltyStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loyaltyStatus)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(loyaltyStatusColor)
                )
                .opacity(cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.5), value: cardAnimations[0])
            
            Text("Lifetime: \(userVM.lifetimePoints)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .opacity(cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.6), value: cardAnimations[0])
        }
    }
    
    private var pointsCounterView: some View {
        VStack(spacing: 4) {
            Text("\(Int(animatedPoints))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .animation(.easeInOut(duration: 0.3), value: animatedPoints)
                .scaleEffect(cardAnimations[0] ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.7), value: cardAnimations[0])
            
            Text("POINTS")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(1)
                .opacity(cardAnimations[0] ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(1.8), value: cardAnimations[0])
        }
    }
    
    private var progressBarView: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                // Radial glow behind the bar
                GeometryReader { geo in
                    let barWidth = max(0, min(CGFloat(animatedPoints / 10000.0) * (UIScreen.main.bounds.width - 120), UIScreen.main.bounds.width - 120))
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [progressBarColor.opacity(0.12), Color.clear]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 13
                            )
                        )
                        .frame(width: barWidth, height: 14)
                        .offset(y: -1)
                        .opacity(barWidth > 0 ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .frame(height: 12)
                
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .frame(height: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                
                // Progress bar
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [progressBarColor, progressBarColor.opacity(0.7), progressBarColor.opacity(0.9)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(CGFloat(animatedPoints / 10000.0) * (UIScreen.main.bounds.width - 120), UIScreen.main.bounds.width - 120)), height: 12)
                    .animation(.easeInOut(duration: 0.5), value: animatedPoints)
            }
            
            HStack {
                Text("0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(cardAnimations[0] ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.5).delay(1.9), value: cardAnimations[0])
                
                Spacer()
                
                Text("10,000")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(cardAnimations[0] ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.5).delay(2.0), value: cardAnimations[0])
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
    
    // Update progressBarColor to change every 150 points
    private var progressBarColor: Color {
        let points = Int(animatedPoints)
        let colorIndex = (points / 150) % 6
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .red]
        return colors[colorIndex]
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
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color, color.opacity(0.8), color.opacity(0.9)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: color.opacity(0.4), radius: 15, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .scaleEffect(1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
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
        // Create a placemark with the exact address
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let placemark = placemarks?.first {
                // Convert CLPlacemark to MKPlacemark
                let mkPlacemark = MKPlacemark(coordinate: placemark.location?.coordinate ?? locationCoordinate, addressDictionary: placemark.addressDictionary as? [String: Any])
                let mapItem = MKMapItem(placemark: mkPlacemark)
                mapItem.name = "Dumpling House"
                mapItem.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                ])
            } else {
                // Fallback to coordinate-based directions
                let placemark = MKPlacemark(coordinate: locationCoordinate)
                let mapItem = MKMapItem(placemark: placemark)
                mapItem.name = "Dumpling House"
                mapItem.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                ])
            }
        }
    }
    
    private func openOrderView() {
        // Navigate to order view - you'll need to implement this navigation
        print("Opening order view")
    }
    
    private func setupView() {
        if userVM.isLoading {
            userVM.loadUserData()
        }
        
        // Coordinate with LaunchView animation timing
        // LaunchView starts fading after 1.5 seconds (if logged in) or 0.5 seconds (if not logged in)
        // We want to start our animations when the launch view starts fading
        let launchFadeDelay = 1.5 // This matches the LaunchView timing
        
        DispatchQueue.main.asyncAfter(deadline: .now() + launchFadeDelay) {
            startSequentialAnimations()
        }
    }
    
    private func startSequentialAnimations() {
        // Start with points card animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            cardAnimations[0] = true
        }
        
        // Start points counting animation after points card appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !pointsAnimationStarted {
                pointsAnimationStarted = true
                startCountingAnimation(to: Double(userVM.points))
            }
        }
        
        // Animate rewards card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardAnimations[1] = true
            }
        }
        
        // Animate location card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardAnimations[2] = true
            }
        }
    }
    
    private func startCountingAnimation(to finalValue: Double) {
        timer?.cancel()
        animatedPoints = 0
        guard finalValue > 0 else { return }
        
        // Slower for low points, faster for high points, max 8s, min 0.7s
        let cappedValue = min(finalValue, 10000.0)
        let duration = max(0.7, min(8.0, 8.0 * (1.0 - cappedValue / 10000.0)))
        let startTime = Date()

        func easeOut(_ t: Double) -> Double {
            // Strong ease out: slows to a trickle at the end
            return 1 - pow(1 - t, 2.5)
        }

        timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect().sink { _ in
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime >= duration {
                animatedPoints = finalValue
                timer?.cancel()
            } else {
                let progress = elapsedTime / duration
                animatedPoints = easeOut(progress) * finalValue
            }
        }
    }
}

struct JellyGlimmerView: View {
    var scrollOffset: CGFloat
    var time: Double
    var colorScheme: ColorScheme
    var pop: Bool

    var body: some View {
        ZStack {
            JellyBlob(color: .purple, baseX: 0.2, baseY: 0.3, scrollOffset: scrollOffset, time: time, size: 280, speed: 0.7, colorScheme: colorScheme, pop: pop)
            JellyBlob(color: .blue, baseX: 0.7, baseY: 0.2, scrollOffset: scrollOffset, time: time, size: 220, speed: 1.1, colorScheme: colorScheme, pop: pop)
            JellyBlob(color: .pink, baseX: 0.5, baseY: 0.7, scrollOffset: scrollOffset, time: time, size: 260, speed: 0.9, colorScheme: colorScheme, pop: pop)
            JellyBlob(color: .yellow, baseX: 0.8, baseY: 0.8, scrollOffset: scrollOffset, time: time, size: 180, speed: 1.3, colorScheme: colorScheme, pop: pop)
            JellyBlob(color: .cyan, baseX: 0.3, baseY: 0.8, scrollOffset: scrollOffset, time: time, size: 200, speed: 1.5, colorScheme: colorScheme, pop: pop)
        }
        .blendMode(.screen)
        .ignoresSafeArea()
    }
}

struct JellyBlob: View {
    var color: Color
    var baseX: CGFloat
    var baseY: CGFloat
    var scrollOffset: CGFloat
    var time: Double
    var size: CGFloat
    var speed: Double
    var colorScheme: ColorScheme
    var pop: Bool
    
    var body: some View {
        let x = baseX + 0.04 * CGFloat(sin(time * speed + Double(baseX) * 2)) + 0.0005 * scrollOffset
        let y = baseY + 0.04 * CGFloat(cos(time * speed + Double(baseY) * 2)) + 0.0007 * scrollOffset
        let scale = 1 + 0.08 * CGFloat(sin(time * speed * 0.7 + Double(baseY)))
        if colorScheme == .light && pop {
            return Circle()
                .fill(color)
                .frame(width: size * scale, height: size * scale)
                .position(x: UIScreen.main.bounds.width * x,
                          y: UIScreen.main.bounds.height * y)
                .blur(radius: 40)
                .opacity(0.75)
                .shadow(color: .white.opacity(0.18), radius: 40)
        } else {
            return Circle()
                .fill(color)
                .frame(width: size * scale, height: size * scale)
                .position(x: UIScreen.main.bounds.width * x,
                          y: UIScreen.main.bounds.height * y)
                .blur(radius: 40)
                .opacity(0.45)
                .shadow(color: .clear, radius: 40)
        }
    }
}

struct DiagonalRewardCard: View {
    var title: String
    var description: String
    var pointsRequired: Int
    var currentPoints: Int
    var color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Text(description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("\(pointsRequired) points")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                
                Button(action: {
                    // Handle reward claim
                    print("Claiming reward: \(title)")
                }) {
                    Text(currentPoints >= pointsRequired ? "Claim" : "Locked")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(currentPoints >= pointsRequired ? color : .gray)
                        )
                }
                .disabled(currentPoints < pointsRequired)
            }
        }
        .padding(16)
        .frame(width: 145, height: 130)
        .background(
            ZStack {
                // Glow with rounded corners
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.clear)
                    .shadow(color: color.opacity(0.45), radius: 16, x: 0, y: 4)
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(color.opacity(0.4), lineWidth: 1.5)
                    )
            }
        )
        .clipped()
    }
}

#Preview {
    HomeView()
}

// MARK: - Supporting Structures and Views

struct RewardOption {
    let title: String
    let description: String
    let pointsRequired: Int
    let color: Color
}

struct DetailedRewardsView: View {
    let rewardOptions: [RewardOption]
    let currentPoints: Int
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(rewardOptions, id: \.title) { reward in
                            DetailedRewardCard(
                                title: reward.title,
                                description: reward.description,
                                pointsRequired: reward.pointsRequired,
                                currentPoints: currentPoints,
                                color: reward.color
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("All Rewards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

struct DetailedRewardCard: View {
    var title: String
    var description: String
    var pointsRequired: Int
    var currentPoints: Int
    var color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(pointsRequired) points")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                    
                    Spacer()
                    
                    if currentPoints < pointsRequired {
                        Text("\(pointsRequired - currentPoints) more needed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    // Handle reward claim
                    print("Claiming reward: \(title)")
                }) {
                    Text(currentPoints >= pointsRequired ? "Claim Reward" : "Not Enough Points")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(currentPoints >= pointsRequired ? color : .gray)
                        )
                }
                .disabled(currentPoints < pointsRequired)
            }
        }
        .padding(16)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(currentPoints >= pointsRequired ? color.opacity(0.3) : Color(.separator), lineWidth: 1)
                )
        )
        .opacity(currentPoints >= pointsRequired ? 1.0 : 0.6)
    }
}
