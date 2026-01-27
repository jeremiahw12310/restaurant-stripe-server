import SwiftUI
import StoreKit

/// View displayed when the app requires an update to continue
struct UpdateRequiredView: View {
    let minimumVersion: String
    let currentVersion: String
    let updateMessage: String?
    let onRetry: () -> Void
    
    @State private var isButtonPressed = false
    
    var body: some View {
        ZStack {
            // Cream/white gradient background matching app style
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
            
            VStack(spacing: 24) {
                Spacer()
                
                // App Logo
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
                
                // Title
                Text("Update Required")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
                    .padding(.top, 8)
                
                // Message - only show if updateMessage is provided
                if let message = updateMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Theme.modernSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
                
                Spacer()
                
                // Update Button - matching app's gold button style
                Button(action: {
                    isButtonPressed = true
                    openAppStore()
                    // Reset after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isButtonPressed = false
                    }
                }) {
                    HStack(spacing: 12) {
                        Text("UPDATE NOW")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .tracking(0.5)
                        
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.darkGoldGradient)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                    )
                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isButtonPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonPressed)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
    
    private func openAppStore() {
        // Try to get App Store URL from the service
        if let appStoreURL = AppVersionService.shared.getAppStoreURL() {
            UIApplication.shared.open(appStoreURL)
        } else {
            // Fallback: Try to open App Store with the app's bundle identifier
            // This uses StoreKit 2's App Store URL scheme
            if let bundleId = Bundle.main.bundleIdentifier {
                if let url = URL(string: "https://apps.apple.com/app/id\(bundleId)") {
                    UIApplication.shared.open(url)
                } else {
                    // Last resort: Open App Store search
                    let encodedBundleId = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
                    if let searchURL = URL(string: "https://apps.apple.com/search?term=\(encodedBundleId)") {
                        UIApplication.shared.open(searchURL)
                    }
                }
            }
        }
    }
}

#Preview {
    UpdateRequiredView(
        minimumVersion: "1.1.0",
        currentVersion: "1.0.0",
        updateMessage: "New features and improvements are available. Please update to continue.",
        onRetry: {}
    )
}
