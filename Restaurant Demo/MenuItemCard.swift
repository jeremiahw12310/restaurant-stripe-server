import SwiftUI
import Kingfisher

// Import our new design system
import Foundation

// MARK: - Menu Item Card
struct MenuItemCard: View {
    let item: MenuItem
    let isPressed: Bool
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var userVM = UserViewModel()
    @EnvironmentObject var menuVM: MenuViewModel
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image area (no card background) - use cached if available; URL from MenuItem.resolvedImageURL
            if let imageURL = item.resolvedImageURL {
                let urlString = imageURL.absoluteString
                
                // Use cached image if available, otherwise fall back to Kingfisher
                if let cachedImage = menuVM.cachedItemImages[urlString] {
                    // Cached image - instant display!
                    Image(uiImage: cachedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 154, height: 154)
                        .background(Color.clear)
                        .clipped()
                } else {
                    // Fallback to Kingfisher for uncached images
                    KFImage(imageURL)
                        .resizable()
                        .placeholder {
                            ZStack {
                                Color.black
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.1)
                            }
                        }
                        .onFailure { error in
                            DebugLogger.debug("❌ Image loading failed for item \(item.id): \(error.localizedDescription)", category: "Menu")
                            DebugLogger.debug("❌ Failed URL: \(imageURL)", category: "Menu")
                        }
                        .onSuccess { _ in
                            DebugLogger.debug("✅ Image loaded successfully for item \(item.id)", category: "Menu")
                        }
                        .fade(duration: 0.3)
                        .cacheMemoryOnly()
                        .scaledToFit()
                        .frame(width: 154, height: 154)
                        .background(Color.clear)
                        .clipped()
                }
            } else {
                ZStack {
                    Color.clear
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                        Text("No image")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(width: 154, height: 154)
                .onAppear {
                    DebugLogger.debug("🖼️ No valid image URL for item: \(item.id)", category: "Menu")
                    DebugLogger.debug("🖼️ Raw imageURL: '\(item.imageURL)'", category: "Menu")
                }
            }
            
            // Gradient overlay for better text readability
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.7)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 154, height: 70)
            .offset(y: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.id)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
                Text(String(format: "$%.2f", item.price))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.top, 4)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, -24)
            .frame(width: 154, alignment: .leading)
            .allowsHitTesting(false)
        }
        .frame(width: 220, height: 220)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onAppear {
            userVM.loadUserData()
        }
    }
}

// MARK: - Preview
struct MenuItemCard_Previews: PreviewProvider {
    static var previews: some View {
        MenuItemCard(item: MenuItem(
            id: "Sample Dumpling",
            description: "Delicious steamed dumplings with pork and vegetables",
            price: 12.99,
            imageURL: "gs://dumplinghouseapp.firebasestorage.app/Subject.png",
            isAvailable: true,
            paymentLinkID: ""
        ), isPressed: false)
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.light)
        .previewDisplayName("Light Mode")
        
        MenuItemCard(item: MenuItem(
            id: "Sample Dumpling",
            description: "Delicious steamed dumplings with pork and vegetables",
            price: 12.99,
            imageURL: "gs://dumplinghouseapp.firebasestorage.app/Subject.png",
            isAvailable: true,
            paymentLinkID: ""
        ), isPressed: false)
        .padding()
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark Mode")
    }
} 