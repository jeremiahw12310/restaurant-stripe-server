import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

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
    @State private var isBanned: Bool = false
    @StateObject private var userVM = UserViewModel()
    
    var body: some View {
        ZStack {
            // The content that will be revealed underneath is always present in the hierarchy.
            if isLoggedIn {
                if isBanned {
                    // Banned users see deletion-only screen
                    BannedAccountDeletionView()
                        .environmentObject(userVM)
                } else {
                    // Normal users see full app
                    ContentView()
                }
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
                // Check if user is banned (by profile flag) and also by bannedNumbers collection (phone-based).
                let userIsBanned = data["isBanned"] as? Bool ?? false
                let rawPhone = (data["phone"] as? String) ?? ""
                let normalizedPhone = normalizePhoneForBannedLookup(rawPhone)
                let digitsOnly = normalizedPhone.replacingOccurrences(of: "+", with: "")
                let hashedId = bannedNumbersDocIdHash(normalizedPhone)

                // If no phone, fall back to the profile flag only.
                guard !normalizedPhone.isEmpty else {
                    DispatchQueue.main.async {
                        self.isBanned = userIsBanned
                        if !isLoggedIn { isLoggedIn = true }
                    }
                    return
                }

                let db = Firestore.firestore()
                // Prefer hashed doc IDs to reduce enumeration risk; fall back to legacy IDs for compatibility.
                if !hashedId.isEmpty {
                    db.collection("bannedNumbers").document(hashedId).getDocument { hashedSnap, _ in
                        guard loginGateCheckToken == token else { return }
                        let bannedByHash = hashedSnap?.exists == true
                        if bannedByHash {
                            DispatchQueue.main.async {
                                self.isBanned = true
                                if !isLoggedIn { isLoggedIn = true }
                            }
                            return
                        }

                        db.collection("bannedNumbers").document(normalizedPhone).getDocument { bannedSnap, _ in
                            guard loginGateCheckToken == token else { return }
                            let bannedByNormalized = bannedSnap?.exists == true

                            // If not found, try digits-only legacy format.
                            if !bannedByNormalized && digitsOnly != normalizedPhone {
                                db.collection("bannedNumbers").document(digitsOnly).getDocument { altSnap, _ in
                                    guard loginGateCheckToken == token else { return }
                                    let bannedByDigits = altSnap?.exists == true
                                    DispatchQueue.main.async {
                                        self.isBanned = userIsBanned || bannedByNormalized || bannedByDigits
                                        if !isLoggedIn { isLoggedIn = true }
                                    }
                                }
                            } else {
                                DispatchQueue.main.async {
                                    self.isBanned = userIsBanned || bannedByNormalized
                                    if !isLoggedIn { isLoggedIn = true }
                                }
                            }
                        }
                    }
                } else {
                    db.collection("bannedNumbers").document(normalizedPhone).getDocument { bannedSnap, _ in
                        guard loginGateCheckToken == token else { return }
                        let bannedByNormalized = bannedSnap?.exists == true

                        if !bannedByNormalized && digitsOnly != normalizedPhone {
                            db.collection("bannedNumbers").document(digitsOnly).getDocument { altSnap, _ in
                                guard loginGateCheckToken == token else { return }
                                let bannedByDigits = altSnap?.exists == true
                                DispatchQueue.main.async {
                                    self.isBanned = userIsBanned || bannedByNormalized || bannedByDigits
                                    if !isLoggedIn { isLoggedIn = true }
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.isBanned = userIsBanned || bannedByNormalized
                                if !isLoggedIn { isLoggedIn = true }
                            }
                        }
                    }
                }
                return
            }

            // If Firestore is temporarily unavailable, don't lock existing users out.
            // (This does NOT reintroduce the bug: the deleted-account case returns snapshot.exists == false without an error.)
            if error != nil {
                DispatchQueue.main.async {
                    self.isBanned = false
                    if !isLoggedIn { isLoggedIn = true }
                }
                return
            }

            // Missing profile doc -> remain logged out so the auth flow can collect details.
            DispatchQueue.main.async {
                self.isBanned = false
                if isLoggedIn { isLoggedIn = false }
            }
        }
    }

    /// Normalizes a phone number string into `+1XXXXXXXXXX` when possible (for bannedNumbers lookup).
    private func normalizePhoneForBannedLookup(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 10 else { return "" }
        let last10 = String(digits.suffix(10))
        return "+1" + last10
    }

    private func bannedNumbersDocIdHash(_ normalizedPhone: String) -> String {
        guard !normalizedPhone.isEmpty else { return "" }
        let data = Data(normalizedPhone.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
