import SwiftUI
import MapKit

// MARK: - Location Card Component
struct LocationCard: View {
    let cardAnimations: [Bool]
    let mapCameraPosition: Binding<MapCameraPosition>
    let locationCoordinate: CLLocationCoordinate2D
    let orderButtonPosition: Binding<CGPoint>
    let primaryGold: Color
    let makeCall: () -> Void
    let openDirections: () -> Void
    let openOrderView: () -> Void
    
    init(
        cardAnimations: [Bool],
        mapCameraPosition: Binding<MapCameraPosition>,
        locationCoordinate: CLLocationCoordinate2D,
        orderButtonPosition: Binding<CGPoint>,
        primaryGold: Color = Color(red: 1.0, green: 0.8, blue: 0.0),
        makeCall: @escaping () -> Void,
        openDirections: @escaping () -> Void,
        openOrderView: @escaping () -> Void
    ) {
        self.cardAnimations = cardAnimations
        self.mapCameraPosition = mapCameraPosition
        self.locationCoordinate = locationCoordinate
        self.orderButtonPosition = orderButtonPosition
        self.primaryGold = primaryGold
        self.makeCall = makeCall
        self.openDirections = openDirections
        self.openOrderView = openOrderView
    }
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Map(position: mapCameraPosition, interactionModes: []) {
                    Marker("Dumpling House", coordinate: locationCoordinate)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.ultraThinMaterial, lineWidth: 1)
                )
                
                VStack {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title2)
                            .foregroundColor(.red)
                            .scaleEffect(cardAnimations.indices.contains(2) && cardAnimations[2] ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2), value: cardAnimations.indices.contains(2) ? cardAnimations[2] : false)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dumpling House")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .opacity(cardAnimations.indices.contains(2) && cardAnimations[2] ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.5).delay(0.3), value: cardAnimations.indices.contains(2) ? cardAnimations[2] : false)
                            
                            Text("2117 Belcourt Ave")
                                .font(.caption)
                                .foregroundColor(.white)
                                .opacity(cardAnimations.indices.contains(2) && cardAnimations[2] ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.5).delay(0.4), value: cardAnimations.indices.contains(2) ? cardAnimations[2] : false)
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

            HStack(spacing: 15) {
                actionButton(
                    title: "Call Us",
                    icon: "phone.fill",
                    color: Color(red: 0.2, green: 0.8, blue: 0.4),
                    action: makeCall
                )
                .scaleEffect(cardAnimations.indices.contains(3) && cardAnimations[3] ? 1.0 : 0.8)
                .opacity(cardAnimations.indices.contains(3) && cardAnimations[3] ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.7), value: cardAnimations.indices.contains(3) ? cardAnimations[3] : false)
                
                actionButton(
                    title: "Directions",
                    icon: "location.fill",
                    color: Color(red: 0.2, green: 0.6, blue: 0.9),
                    action: openDirections
                )
                .scaleEffect(cardAnimations.indices.contains(3) && cardAnimations[3] ? 1.0 : 0.8)
                .opacity(cardAnimations.indices.contains(3) && cardAnimations[3] ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.8), value: cardAnimations.indices.contains(3) ? cardAnimations[3] : false)
            }
            
            GeometryReader { geometry in
                actionButton(
                    title: "Order Now",
                    icon: "bag.fill",
                    color: .orange,
                    action: {
                        let buttonFrame = geometry.frame(in: .global)
                        orderButtonPosition.wrappedValue = CGPoint(
                            x: buttonFrame.midX,
                            y: buttonFrame.midY
                        )
                        openOrderView()
                    }
                )
                .scaleEffect(cardAnimations.indices.contains(3) && cardAnimations[3] ? 1.0 : 0.8)
                .opacity(cardAnimations.indices.contains(3) && cardAnimations[3] ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.9), value: cardAnimations.indices.contains(3) ? cardAnimations[3] : false)
            }
            .frame(height: 50)
        }
        .padding(25)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(primaryGold.opacity(0.9), lineWidth: 4)
                )
                .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
                .shadow(color: primaryGold.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .padding(.horizontal, 20)
        .scaleEffect(cardAnimations.indices.contains(4) && cardAnimations[4] ? 1.0 : 0.8)
        .opacity(cardAnimations.indices.contains(4) && cardAnimations[4] ? 1.0 : 0.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: cardAnimations.indices.contains(4) ? cardAnimations[4] : false)
    }
    
    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize()
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(color)
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
    }
} 