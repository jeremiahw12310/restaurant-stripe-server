import SwiftUI
import Combine
import MapKit
import CoreLocation
import UIKit

struct HomeView: View {
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
    
    // MARK: - Location Constants
    private let locationCoordinate = CLLocationCoordinate2D(latitude: 36.1412, longitude: -86.8085)
    private let phoneNumber = "+16158914728"
    private let address = "2117 Belcourt Ave, Nashville, TN 37212"
    
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
                        HStack {
                            // Welcome and Name (Left side)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Welcome back,")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                
                                Text(userVM.firstName)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            // Loyalty Status (Right side)
                            VStack(spacing: 8) {
                                // Progress Bar
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 120, height: 6)
                                    
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(loyaltyStatusColor)
                                        .frame(width: max(0, min(CGFloat(loyaltyProgressPercentage) * 120, 120)), height: 6)
                                        .animation(.easeInOut(duration: 0.5), value: userVM.lifetimePoints)
                                }
                                
                                // Status Badge
                                Text(loyaltyStatus)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(loyaltyStatusColor)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // MARK: - Points Display with Glass Effect
                        VStack(spacing: 20) {
                            HStack {
                                // Beautiful Avatar with Glass Effect
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [userVM.avatarColor, userVM.avatarColor.opacity(0.7)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 70, height: 70)
                                        .shadow(color: userVM.avatarColor.opacity(0.3), radius: 10, x: 0, y: 5)
                                    
                                    Text(userVM.avatarEmoji)
                                        .font(.system(size: 35))
                                        .shadow(radius: 2)
                                }
                                .onTapGesture {
                                    showSignOutConfirmation = true
                                }

                                Spacer()
                                
                                // Points Display with Glass Effect
                                VStack(spacing: 8) {
                                    Text("\(Int(animatedPoints))")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .contentTransition(.numericText())
                                    
                                    Text("POINTS")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .tracking(1.5)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                                )
                            }
                            
                            // Progress Bar with Glass Effect
                            VStack(spacing: 8) {
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.ultraThinMaterial)
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [userVM.avatarColor, userVM.avatarColor.opacity(0.7)]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(0, min(CGFloat(animatedPoints / 10000.0) * UIScreen.main.bounds.width - 60, UIScreen.main.bounds.width - 60)), height: 8)
                                        .animation(.easeInOut(duration: 0.5), value: animatedPoints)
                                }
                                
                                HStack {
                                    Text("0")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("10,000")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(25)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal, 20)
                        
                        // MARK: - Rewards Section
                        VStack(spacing: 20) {
                            HStack {
                                Text("Available Rewards")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            // Sample rewards - you can make this dynamic based on user's points
                            VStack(spacing: 12) {
                                rewardCard(
                                    title: "Free Appetizer",
                                    description: "Any appetizer under $8",
                                    pointsRequired: 2000,
                                    currentPoints: Int(animatedPoints),
                                    color: .orange
                                )
                                
                                rewardCard(
                                    title: "50% Off Entrée",
                                    description: "Any entrée on the menu",
                                    pointsRequired: 5000,
                                    currentPoints: Int(animatedPoints),
                                    color: .purple
                                )
                                
                                rewardCard(
                                    title: "Free Dessert",
                                    description: "Any dessert of your choice",
                                    pointsRequired: 1500,
                                    currentPoints: Int(animatedPoints),
                                    color: .pink
                                )
                            }
                        }
                        .padding(25)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal, 20)
                        
                        // MARK: - Location Card with Glass Effect
                        VStack(spacing: 20) {
                            // Map with Glass Effect
                            ZStack {
                                Map(position: $mapCameraPosition) {
                                     Marker("Dumpling House", coordinate: locationCoordinate)
                                }
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(.ultraThinMaterial, lineWidth: 1)
                                )
                                
                                // Floating Info Card
                                VStack {
                                    HStack {
                                        Text("📍")
                                            .font(.title2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Dumpling House")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Text("2117 Belcourt Ave")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
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

                            // Action Buttons
                            HStack(spacing: 15) {
                                actionButton(
                                    title: "Call Us",
                                    icon: "phone.fill",
                                    color: Color(red: 0.2, green: 0.8, blue: 0.4),
                                    action: makeCall
                                )
                                
                                actionButton(
                                    title: "Directions",
                                    icon: "location.fill",
                                    color: Color(red: 0.2, green: 0.6, blue: 0.9),
                                    action: openDirections
                                )
                            }
                            
                            // Order Button
                            actionButton(
                                title: "Order Now",
                                icon: "bag.fill",
                                color: .orange,
                                action: openOrderView
                            )
                        }
                        .padding(25)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        )
                        .padding(.horizontal, 20)
                        
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
            if oldValue == 0 && newValue > 0 {
                startCountingAnimation(to: Double(newValue))
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
            Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
                time += 1/60
                if Date().timeIntervalSince(lastScroll) > 0.7 {
                    if glimmerOpacity > 0 {
                        // Fade out much more smoothly and slowly
                        glimmerOpacity = max(0, glimmerOpacity - 0.01)
                    }
                }
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
                            gradient: Gradient(colors: [color, color.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
            )
        }
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
    }
    
    private func startCountingAnimation(to finalValue: Double) {
        timer?.cancel()
        animatedPoints = 0
        guard finalValue > 0 else { return }
        
        let duration = min(max(finalValue / 1000.0, 1.0), 3.0)
        let startTime = Date()

        timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect().sink { _ in
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime >= duration {
                animatedPoints = finalValue
                timer?.cancel()
            } else {
                let progress = elapsedTime / duration
                animatedPoints = progress * finalValue
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
#Preview {
    HomeView()
}
