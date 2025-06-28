import SwiftUI
import Combine
import MapKit

struct HomeView: View {
    @StateObject private var userVM = UserViewModel()
    @AppStorage("isLoggedIn") private var isLoggedIn = true
    
    // MARK: - State Variables
    @State private var animatedPoints: Double = 0.0
    @State private var timer: AnyCancellable?
    @State private var mapCameraPosition: MapCameraPosition
    // ✅ NEW: State to control the visibility of the sign-out alert.
    @State private var showSignOutConfirmation = false
    
    // MARK: - Location Constants
    private let locationCoordinate = CLLocationCoordinate2D(latitude: 36.1412, longitude: -86.8085)
    private let phoneNumber = "+16158914728"
    
    init() {
        _mapCameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: locationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        VStack(spacing: 20) {
            if userVM.isLoading {
                Spacer()
                ProgressView("Loading Profile...")
                Spacer()
            } else {
                // MARK: - Rewards Header
                VStack(spacing: 16) {
                    HStack {
                        // ✅ CHANGE: The Avatar ZStack now has an .onTapGesture modifier
                        // to toggle the state for the confirmation alert.
                        ZStack {
                            Circle()
                                .fill(userVM.avatarColor)
                                .frame(width: 60, height: 60)
                                .shadow(radius: 3)
                            Text(userVM.avatarEmoji)
                                .font(.system(size: 30))
                        }
                        .onTapGesture {
                            showSignOutConfirmation = true
                        }

                        Spacer()
                        Text("\(Int(animatedPoints)) pts")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    
                    VStack(spacing: 4) {
                        ProgressView(value: animatedPoints, total: 10000.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: userVM.avatarColor))
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                            .shadow(radius: 2)
                            .animation(.linear, value: animatedPoints)
                        HStack {
                            Text("0")
                            Spacer()
                            Text("10,000")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                Text("Welcome, \(userVM.firstName)!")
                    .font(.title)
                    .fontWeight(.medium)
                
                // MARK: - Location Card
                VStack(spacing: 12) {
                    Map(position: $mapCameraPosition) {
                         Marker("Dumpling House", coordinate: locationCoordinate)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                    VStack(spacing: 12) {
                        Text("Dumpling House Nashville")
                            .font(.headline)
                        
                        HStack(spacing: 15) {
                            actionButton(title: "Call Us", icon: "phone.fill", action: makeCall)
                            actionButton(title: "Directions", icon: "arrow.triangle.turn.up.right.circle.fill", action: openDirections)
                        }
                    }
                }

                Spacer()
                
                // ✅ REMOVED: The old Sign Out button is no longer here.
            }
        }
        .padding()
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
    }
    
    // MARK: - Helper Functions
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(10)
        }
    }

    private func makeCall() {
        if let url = URL(string: "tel:\(phoneNumber)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openDirections() {
        let placemark = MKPlacemark(coordinate: locationCoordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Dumpling House"
        mapItem.openInMaps()
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

#Preview {
    HomeView()
}
