import SwiftUI
import StoreKit

/// View displayed when the app requires an update to continue
struct UpdateRequiredView: View {
    let minimumVersion: String
    let currentVersion: String
    let updateMessage: String?
    let onRetry: () -> Void
    
    @State private var isChecking = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // App Icon or Logo
                Image("dumpsplash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .cornerRadius(20)
                
                // Title
                Text("Update Required")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                // Message
                VStack(spacing: 12) {
                    if let message = updateMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
                        Text("A new version of Dumpling House is available.")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Text("Please update to continue using the app.")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                // Version Info
                VStack(spacing: 4) {
                    Text("Current Version: \(currentVersion)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("Required Version: \(minimumVersion)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Update Button
                Button(action: {
                    openAppStore()
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                        Text("Update Now")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .padding(.horizontal, 40)
                }
                .padding(.bottom, 20)
                
                // Retry Button (for network issues)
                Button(action: {
                    isChecking = true
                    Task {
                        await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        isChecking = false
                        onRetry()
                    }
                }) {
                    Text(isChecking ? "Checking..." : "Retry")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
                .disabled(isChecking)
                .padding(.bottom, 40)
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
