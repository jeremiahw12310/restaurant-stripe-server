import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LaunchView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    
    // Using an enum for the animation state is clearer and less error-prone.
    enum LaunchPhase {
        case initial
        case animating
        case finished
    }
    
    @State private var launchPhase: LaunchPhase = .initial
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle? = nil
    @State private var loginGateCheckToken: UUID = UUID()
    
    var body: some View {
        ZStack {
            // The content that will be revealed underneath is always present in the hierarchy.
            if isLoggedIn {
                ContentView()
            } else {
                // We pass a binding of the launchPhase to the SplashView
                // so it knows when to start its own animation.
                SplashView(launchPhase: $launchPhase)
            }
            
            // The launch screen overlay.
            if launchPhase != .finished {
                // ✅ FIX: By placing the image in the background of a view that fills the space,
                // we guarantee it is always perfectly centered and properly scaled.
                Color.black // A solid black background to prevent any transparency glitches.
                    .overlay(
                        Image("dumpsplash") // Ensure this image is in your Assets.xcassets
                            .resizable()
                            .scaledToFill()
                    )
                    .ignoresSafeArea()
                    // ✅ FIX: The image starts already zoomed in and animates to a larger scale.
                    .scaleEffect(launchPhase == .animating ? 1.1 : 1.1)
                    .opacity(launchPhase == .animating ? 0 : 1) // Fades out during animation.
                    .onAppear(perform: startAnimation)
            }
        }
        .onAppear {
            // Keep AppStorage in sync with Firebase Auth state, but ONLY enter the logged-in UI
            // once the user's Firestore profile doc exists. This prevents a half-signed-in state
            // where Auth is present but users/{uid} is missing (causes "Friend"/"user not found").
            if authListenerHandle == nil {
                authListenerHandle = Auth.auth().addStateDidChangeListener { _, user in
                    gateLoggedInState(for: user)
                }
            }
            // Also sync immediately on appear (covers cold start edge cases)
            gateLoggedInState(for: Auth.auth().currentUser)
        }
        .onDisappear {
            if let handle = authListenerHandle {
                Auth.auth().removeStateDidChangeListener(handle)
                authListenerHandle = nil
            }
        }
    }
    
    private func gateLoggedInState(for user: User?) {
        // Bump token to invalidate any in-flight Firestore checks.
        let token = UUID()
        loginGateCheckToken = token

        // No auth user -> definitely logged out.
        guard let user else {
            if isLoggedIn { isLoggedIn = false }
            return
        }

        // Auth user exists. Only treat as logged-in if their Firestore profile exists.
        let uid = user.uid
        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, error in
            // Ignore stale responses.
            guard loginGateCheckToken == token else { return }

            // If snapshot exists and has data, allow logged-in UI.
            if let snapshot, snapshot.exists, let data = snapshot.data(), !data.isEmpty {
                if !isLoggedIn { isLoggedIn = true }
                return
            }

            // If Firestore is temporarily unavailable, don't lock existing users out.
            // (This does NOT reintroduce the bug: the deleted-account case returns snapshot.exists == false without an error.)
            if error != nil {
                if !isLoggedIn { isLoggedIn = true }
                return
            }

            // Missing profile doc -> remain logged out so the auth flow can collect details.
            if isLoggedIn { isLoggedIn = false }
        }
    }

    private func startAnimation() {
        let animationDelay = isLoggedIn ? 1.5 : 0.5
        
        // This is the animation that the user sees.
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
            withAnimation(.easeInOut(duration: 1.2)) {
                launchPhase = .animating
            }
        }
        
        // This timer removes the launch view from the hierarchy after the animation is complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay + 1.2) {
            launchPhase = .finished
        }
    }
}
