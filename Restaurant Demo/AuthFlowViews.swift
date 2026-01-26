import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - Onboarding Progress Indicator
struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int = 3
    
    private let stepLabels = ["Phone", "Verify", "Details"]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                VStack(spacing: 6) {
                    // Step circle
                    ZStack {
                        Circle()
                            .stroke(step <= currentStep ? Theme.primaryGold : Theme.modernSecondary.opacity(0.3), lineWidth: 2)
                            .frame(width: 28, height: 28)
                        
                        if step < currentStep {
                            // Completed step - checkmark
                            Circle()
                                .fill(Theme.primaryGold)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        } else if step == currentStep {
                            // Current step - filled
                            Circle()
                                .fill(Theme.primaryGold)
                                .frame(width: 24, height: 24)
                            Text("\(step + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            // Future step - number only
                            Text("\(step + 1)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.modernSecondary.opacity(0.5))
                        }
                    }
                    
                    // Step label
                    Text(stepLabels[step])
                        .font(.system(size: 10, weight: step == currentStep ? .bold : .medium, design: .rounded))
                        .foregroundColor(step <= currentStep ? Theme.primaryGold : Theme.modernSecondary.opacity(0.5))
                }
                
                // Connector line between steps
                if step < totalSteps - 1 {
                    Rectangle()
                        .fill(step < currentStep ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: 30)
                        .offset(y: -10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Theme.primaryGold.opacity(0.15), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Main Container (The Router)
struct AuthFlowView: View {
    @StateObject private var authVM = AuthenticationViewModel()
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @Environment(\.dismiss) var dismiss
    
    // Integer stage identifier used to drive view transitions
    private var navStage: Int {
        if authVM.shouldNavigateToPreferences { return 5 }
        else if authVM.shouldNavigateToCustomization { return 4 }
        else if authVM.didAuthenticate { return 3 }
        else if authVM.shouldNavigateToUserDetails { return 2 }
        else if authVM.verificationID == nil { return 0 }
        else { return 1 }
    }
    
    // Progress step for the indicator (0-2)
    private var progressStep: Int {
        if authVM.shouldNavigateToUserDetails { return 2 }
        else if authVM.verificationID != nil { return 1 }
        else { return 0 }
    }
    
    // Whether to show progress (hide for ContentView, preferences, and customization)
    private var showProgress: Bool {
        !authVM.didAuthenticate && !authVM.shouldNavigateToPreferences && !authVM.shouldNavigateToCustomization
    }
    
    var body: some View {
        ZStack {
            // Themed gradient background matching the app's design language
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
            
            VStack(spacing: 0) {
                // Progress indicator at top - animated visibility
                OnboardingProgressView(currentStep: progressStep)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                    .opacity(showProgress ? 1 : 0)
                    .scaleEffect(showProgress ? 1 : 0.9)
                    .frame(height: showProgress ? nil : 0)
                    .clipped()
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showProgress)
                
                // Main content
                Group {
                    if authVM.shouldNavigateToPreferences == true {
                        UserPreferencesView(uid: Auth.auth().currentUser?.uid ?? "")
                            .environmentObject(UserViewModel())
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .onAppear { 
                                print("🔵 Navigation: UserPreferencesView")
                                authVM.printNavigationState()
                            }
                    } else if authVM.shouldNavigateToCustomization == true {
                        AccountCustomizationView(uid: Auth.auth().currentUser?.uid ?? "")
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .onAppear { 
                                print("🔵 Navigation: AccountCustomizationView")
                                authVM.printNavigationState()
                            }
                    } else if authVM.didAuthenticate {
                        // User exists, go to ContentView
                        ContentView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .onAppear { 
                                print("🔵 Navigation: ContentView")
                                authVM.printNavigationState()
                            }
                    } else if authVM.shouldNavigateToUserDetails == true {
                        UserDetailsEntryView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .onAppear { 
                                print("🔵 Navigation: UserDetailsEntryView")
                                authVM.printNavigationState()
                            }
                    } else if authVM.verificationID == nil {
                        EnterPhoneView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                            .onAppear { 
                                print("🔵 Navigation: EnterPhoneView")
                                authVM.printNavigationState()
                            }
                    } else if !authVM.didAuthenticate && !authVM.shouldNavigateToUserDetails {
                        EnterCodeView()
                            // CRITICAL: No transition animation for OTP screen
                            // Animations during view appearance can interfere with iOS autofill detection
                            // and first-responder timing, causing OTP insertion to fail
                            .transition(.identity)
                            .onAppear { 
                                print("🔵 Navigation: EnterCodeView")
                                authVM.printNavigationState()
                            }
                    } else {
                        Text("No navigation condition met")
                            .onAppear { 
                                print("🔴 No navigation condition met!")
                                authVM.printNavigationState()
                            }
                    }
                }
                .environmentObject(authVM)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: navStage)
        }
        .onReceive(authVM.$didAuthenticate) { didAuth in
            print("🔵 didAuthenticate changed to: \(didAuth)")
            if didAuth {
                isLoggedIn = true
            }
        }
        .onReceive(authVM.$shouldNavigateToUserDetails) { shouldNavigate in
            print("🔵 shouldNavigateToUserDetails changed to: \(shouldNavigate)")
        }
        .onReceive(authVM.$shouldNavigateToCustomization) { shouldNavigate in
            print("🔵 shouldNavigateToCustomization changed to: \(shouldNavigate)")
        }
        .onAppear {
            // Reset navigation state when AuthFlowView appears to ensure clean navigation
            print("🔵 AuthFlowView: onAppear, resetting navigation state")
            authVM.resetAllNavigationState()
        }
        .onReceive(authVM.$shouldNavigateToSplash) { shouldNavigate in
            if shouldNavigate {
                authVM.reset()
                dismiss()
            }
        }
    }
}

// MARK: - Screen 1: Enter Phone Number
struct EnterPhoneView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var legalDestination: LegalDestination? = nil
    @State private var showMissingLegalAlert: Bool = false
    @State private var missingLegalTitle: String = ""
    @FocusState private var phoneFocused: Bool
    @State private var contentVisible = false
    
    private struct LegalDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Spacer(minLength: 8)
                
                // Beautiful header with brand imagery
                VStack(spacing: 10) {
                    // Dumpling phone image with bounce animation
                    Image("dumpphone")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                        .shadow(color: Theme.primaryGold.opacity(0.4), radius: 15, x: 0, y: 8)
                    
                    // Title with gold gradient
                    VStack(spacing: 4) {
                        Text("Welcome to")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                        
                        Text("Dumpling House Rewards")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                    }
                    .multilineTextAlignment(.center)
                    
                    // Subtitle
                    Text("Time to earn points!")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .opacity(contentVisible ? 1.0 : 0.0)
                .offset(y: contentVisible ? 0 : 15)
                
                // Phone input card with gold border
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Theme.primaryGold)
                            Text("Your Phone Number")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                        }
                        
                        // Phone input field
                        HStack(spacing: 12) {
                            Text("+1")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Theme.modernCardSecondary)
                                )
                            
                            TextField("(555) 123-4567", text: $authVM.phoneNumber)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(phoneFocused ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2), lineWidth: phoneFocused ? 2 : 1)
                                        )
                                )
                                .focused($phoneFocused)
                                .onChange(of: authVM.phoneNumber) { newValue in
                                    // Format phone number
                                    authVM.phoneNumber = formatPhoneNumber(newValue)
                                    let digits = newValue.filter { $0.isNumber }
                                    if digits.count == 10 {
                                        phoneFocused = false
                                    }
                                }
                        }
                        
                        if !authVM.phoneNumber.isEmpty {
                            Button(action: { authVM.phoneNumber = "" }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text("Clear")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Theme.modernSecondary)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Theme.darkGoldGradient, lineWidth: 2)
                        )
                        .shadow(color: Theme.primaryGold.opacity(0.15), radius: 12, x: 0, y: 6)
                )
                .padding(.horizontal, 20)
                .opacity(contentVisible ? 1.0 : 0.0)
                .offset(y: contentVisible ? 0 : 15)
                
                // Privacy Policy with gold checkbox
                HStack(spacing: 10) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            authVM.acceptedPrivacyPolicy.toggle()
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(authVM.acceptedPrivacyPolicy ? Theme.primaryGold : Theme.modernSecondary.opacity(0.4), lineWidth: 2)
                                .frame(width: 24, height: 24)
                            
                            if authVM.acceptedPrivacyPolicy {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.primaryGold)
                                    .frame(width: 24, height: 24)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I accept the")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.modernPrimary)

                        HStack(spacing: 6) {
                            Button("Privacy Policy") { openLegal(title: "Privacy Policy", url: Config.privacyPolicyURL) }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.primaryGold)

                            Text("and")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.modernPrimary)

                            Button("Terms of Service") { openLegal(title: "Terms of Service", url: Config.termsOfServiceURL) }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.primaryGold)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .opacity(contentVisible ? 1.0 : 0.0)
                .offset(y: contentVisible ? 0 : 15)
                .sheet(item: $legalDestination) { destination in
                    SimplifiedSafariView(url: destination.url) {
                        legalDestination = nil
                    }
                }
                .alert("Link Not Set", isPresented: $showMissingLegalAlert) {
                    Button("OK") {}
                } message: {
                    Text("No URL is configured yet for \(missingLegalTitle).")
                }
                
                Spacer(minLength: 12)
                
                // Action button
                VStack(spacing: 12) {
                    if authVM.isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.0)
                                .tint(Theme.primaryGold)
                            Text("Sending code...")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                        }
                        .padding()
                    } else {
                        Button(action: {
                            let digits = authVM.phoneNumber.filter { $0.isNumber }
                            if !authVM.acceptedPrivacyPolicy {
                                authVM.errorMessage = "Please accept the Privacy Policy and Terms of Service to continue."
                                return
                            }
                            if digits.count != 10 {
                                authVM.errorMessage = "Please enter a valid 10-digit phone number."
                                return
                            }
                            authVM.sendVerificationCode()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 18, weight: .black))
                                
                                Text("SEND CODE")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .tracking(0.5)
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 18, weight: .black))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 20)
                    }
                    
                    if !authVM.errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(Theme.energyRed)
                            Text(authVM.errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.energyRed)
                        }
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .opacity(contentVisible ? 1.0 : 0.0)
                .offset(y: contentVisible ? 0 : 15)
                
                Spacer(minLength: 20)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            authVM.resetPhoneAndSMS()
            // Trigger smooth fade-in after navigation settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.4)) {
                    contentVisible = true
                }
            }
            // Focus keyboard after content is visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                phoneFocused = true
            }
        }
        .alert("Account Banned", isPresented: $authVM.showBanAlert) {
            Button("OK", role: .cancel) {
                authVM.showBanAlert = false
            }
        } message: {
            Text("This phone number cannot be used to create an account. Please contact support if you believe this is an error.")
        }
    }

    private func openLegal(title: String, url: URL?) {
        guard let url else {
            missingLegalTitle = title
            showMissingLegalAlert = true
            return
        }
        legalDestination = LegalDestination(url: url)
    }
    
    // Phone number formatter
    private func formatPhoneNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limitedDigits = String(digits.prefix(10))
        
        switch limitedDigits.count {
        case 0...3:
            return limitedDigits
        case 4...6:
            let areaCode = limitedDigits.prefix(3)
            let prefix = limitedDigits.dropFirst(3)
            return "(\(areaCode)) \(prefix)"
        case 7...10:
            let areaCode = limitedDigits.prefix(3)
            let prefix = limitedDigits.dropFirst(3).prefix(3)
            let lineNumber = limitedDigits.dropFirst(6)
            return "(\(areaCode)) \(prefix)-\(lineNumber)"
        default:
            return limitedDigits
        }
    }
}

// MARK: - Screen 2: Enter SMS Code
// Wrapped in UIViewControllerRepresentable for precise focus control
struct EnterCodeView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    
    var body: some View {
        EnterCodeViewController()
            .environmentObject(authVM)
    }
}

// MARK: - UIViewController Wrapper for OTP Focus Control
struct EnterCodeViewController: UIViewControllerRepresentable {
    @EnvironmentObject var authVM: AuthenticationViewModel
    
    func makeUIViewController(context: Context) -> EnterCodeHostingController {
        let controller = EnterCodeHostingController(authVM: authVM)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: EnterCodeHostingController, context: Context) {
        uiViewController.updateAuthVM(authVM)
    }
}

// MARK: - Hosting Controller with Focus Control
class EnterCodeHostingController: UIHostingController<EnterCodeContentView> {
    private var authVM: AuthenticationViewModel
    private var hasFocusedOnce = false
    
    init(authVM: AuthenticationViewModel) {
        self.authVM = authVM
        super.init(rootView: EnterCodeContentView(authVM: authVM))
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateAuthVM(_ newAuthVM: AuthenticationViewModel) {
        self.authVM = newAuthVM
        rootView = EnterCodeContentView(authVM: newAuthVM)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // CRITICAL: Focus the OTP field in viewDidAppear after view is fully laid out
        // This is the most reliable timing - view is stable, no animations running
        // Only focus once per appearance to avoid interrupting autofill
        guard !hasFocusedOnce else { return }
        hasFocusedOnce = true
        
        // Small delay to ensure view hierarchy is completely settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.focusOTPField()
        }
    }
    
    private func focusOTPField() {
        // Find the UITextField in the view hierarchy
        func findTextField(in view: UIView) -> UITextField? {
            if let textField = view as? UITextField {
                return textField
            }
            for subview in view.subviews {
                if let textField = findTextField(in: subview) {
                    return textField
                }
            }
            return nil
        }
        
        if let textField = findTextField(in: view) {
            textField.becomeFirstResponder()
        }
    }
}

// MARK: - Content View (the actual SwiftUI content)
struct EnterCodeContentView: View {
    @ObservedObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var headerAnimated = false
    @State private var cardAnimated = false
    @State private var buttonAnimated = false
    @State private var countdown: Int = 60
    @State private var canResend: Bool = false
    @State private var timer: Timer?
    @State private var localCode: String = ""
    @State private var codeFieldFocused: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)
                
                // Header with notification dumpling
                VStack(spacing: 20) {
                    // Notification dumpling image
                    Image("dumpnot")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .shadow(color: Theme.primaryGold.opacity(0.4), radius: 20, x: 0, y: 10)
                        .scaleEffect(headerAnimated ? 1.0 : 0.8)
                        .opacity(headerAnimated ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: headerAnimated)
                    
                    // Title
                    VStack(spacing: 8) {
                        Text("Check Your Messages! 📱")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                        
                        Text("We sent a 6-digit code to your phone")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .opacity(headerAnimated ? 1.0 : 0.0)
                    .offset(y: headerAnimated ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: headerAnimated)
                }
                .padding(.horizontal, 20)
                
                // Code input card
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Theme.primaryGold)
                            Text("Enter Verification Code")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                        }
                        
                        // UIKit-based OTP text field for reliable iOS autofill
                        // Uses target-action pattern which fires AFTER autofill completes,
                        // unlike SwiftUI's onChange which can interrupt the autofill process
                        // Focus is controlled by UIViewController.viewDidAppear for maximum reliability
                        VStack(spacing: 8) {
                            OTPTextField(
                                text: $localCode,
                                onComplete: { code in
                                    guard !authVM.isVerifying else { return }
                                    authVM.smsCode = code
                                    authVM.verifyCodeAndSignIn()
                                },
                                shouldBecomeFirstResponder: codeFieldFocused
                            )
                            .frame(height: 50)
                            
                            // Subtle hint that field is tappable (helps with autofill reliability)
                            if localCode.isEmpty {
                                Text("Tap to enter code or use autofill")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary.opacity(0.7))
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.primaryGold, lineWidth: 2)
                                )
                        )
                    }
                    
                    // Countdown timer and resend
                    HStack(spacing: 16) {
                        if canResend {
                            Button(action: {
                                resendCode()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Resend Code")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(Theme.primaryGold)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Resend in \(countdown)s")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(Theme.modernSecondary)
                        }
                        
                        Spacer()
                        
                        if !localCode.isEmpty {
                            Button(action: { 
                                localCode = ""
                                authVM.smsCode = ""
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text("Clear")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Theme.modernSecondary)
                            }
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Theme.darkGoldGradient, lineWidth: 2)
                        )
                        .shadow(color: Theme.primaryGold.opacity(0.15), radius: 12, x: 0, y: 6)
                )
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                // CRITICAL: No animations on the code input card
                // Any animation (scale, opacity, etc.) during first-responder setup can interfere
                // with iOS autofill detection and OTP insertion
                // The field must be completely static when becoming first responder
                .opacity(1.0)
                // Tap-to-focus: allows manual re-focus if needed
                .onTapGesture {
                    codeFieldFocused = true
                }
                
                Spacer(minLength: 20)
                
                // Action button
                VStack(spacing: 16) {
                    if authVM.isVerifying {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.0)
                                .tint(Theme.primaryGold)
                            Text("Verifying...")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                        }
                        .padding()
                    } else {
                        Button(action: {
                            // Ensure authVM has the latest value before verifying
                            authVM.smsCode = localCode
                            authVM.verifyCodeAndSignIn()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 18, weight: .black))
                                
                                Text("VERIFY CODE")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .tracking(0.5)
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .black))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 20)
                        .disabled(localCode.filter { $0.isNumber }.count < 6)
                        .opacity(localCode.filter { $0.isNumber }.count == 6 ? 1.0 : 0.6)
                        .scaleEffect(buttonAnimated ? 1.0 : 0.95)
                        .opacity(buttonAnimated ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: buttonAnimated)
                    }
                    
                    if !authVM.errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(Theme.energyRed)
                            Text(authVM.errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.energyRed)
                        }
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Spacer(minLength: 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Sync local code with view model
            localCode = authVM.smsCode
            
            // Trigger animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                headerAnimated = true
                cardAnimated = true
                buttonAnimated = true
            }
            
            // Start countdown timer
            startCountdown()
        }
        .onDisappear {
            // Clean up
            timer?.invalidate()
        }
        // Ban alert removed - banned users are redirected to deletion screen in LaunchView
    }
    
    private func startCountdown() {
        countdown = 60
        canResend = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                canResend = true
                timer?.invalidate()
            }
        }
    }
    
    private func resendCode() {
        authVM.sendVerificationCode()
        startCountdown()
    }
}

// MARK: - Screen 3: Enter User Details
struct UserDetailsEntryView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var focusedField: Field?
    @State private var headerAnimated = false
    @State private var cardAnimated = false
    @State private var buttonAnimated = false
    @State private var selectedDate = Date()
    @State private var keyboardHeight: CGFloat = 0
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    enum Field {
        case firstName, lastName, referralCode
    }

    private enum ScrollTarget: Hashable {
        case referralField
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Spacer(minLength: 8)
                        
                        // Celebratory header
                        VStack(spacing: 8) {
                            // Celebration icon - smaller and more compact
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.primaryGold.opacity(0.2), Theme.deepGold.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "star.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Theme.darkGoldGradient)
                            }
                            .shadow(color: Theme.primaryGold.opacity(0.3), radius: 10, x: 0, y: 4)
                            .scaleEffect(headerAnimated ? 1.0 : 0.8)
                            .opacity(headerAnimated ? 1.0 : 0.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: headerAnimated)
                            
                            // Title
                            VStack(spacing: 4) {
                                Text("Almost a VIP! 🎉")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(Theme.darkGoldGradient)
                                
                                Text("Tell us about yourself")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary)
                            }
                            .multilineTextAlignment(.center)
                            .opacity(headerAnimated ? 1.0 : 0.0)
                            .offset(y: headerAnimated ? 0 : 20)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: headerAnimated)
                        }
                        .padding(.horizontal, 20)
                    
                        // Form card
                        VStack(spacing: 16) {
                        // First Name
                        VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.primaryGold)
                            Text("First Name")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                            Text("*")
                                .foregroundColor(Theme.energyRed)
                        }
                        
                        TextField("Your first name", text: $authVM.firstName)
                            .textContentType(.givenName)
                            .autocapitalization(.words)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .firstName ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2), lineWidth: focusedField == .firstName ? 2 : 1)
                                    )
                            )
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .lastName }
                            .onChange(of: authVM.firstName) { oldValue, newValue in
                                // Only trigger focus changes for autofill scenarios (multiple characters added at once)
                                // Autofill typically adds multiple characters in one change
                                let isAutofill = (oldValue.isEmpty && newValue.count > 1) || (newValue.count - oldValue.count > 1)
                                
                                if isAutofill && !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                    if authVM.lastName.trimmingCharacters(in: .whitespaces).isEmpty {
                                        // Last name empty, move focus there for autofill
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            focusedField = .lastName
                                        }
                                    } else {
                                        // Both filled, dismiss keyboard
                                        focusedField = nil
                                    }
                                }
                                // For manual typing (single character changes), keep focus on firstName
                            }
                    }
                    
                    // Last Name
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.primaryGold)
                            Text("Last Name")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                            Text("*")
                                .foregroundColor(Theme.energyRed)
                        }
                        
                        TextField("Your last name", text: $authVM.lastName)
                            .textContentType(.familyName)
                            .autocapitalization(.words)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(focusedField == .lastName ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2), lineWidth: focusedField == .lastName ? 2 : 1)
                                    )
                            )
                            .focused($focusedField, equals: .lastName)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .onChange(of: authVM.lastName) { oldValue, newValue in
                                // Only dismiss keyboard for autofill scenarios (multiple characters added at once)
                                // Autofill typically adds multiple characters in one change
                                let isAutofill = (oldValue.isEmpty && newValue.count > 1) || (newValue.count - oldValue.count > 1)
                                
                                if isAutofill && !newValue.trimmingCharacters(in: .whitespaces).isEmpty &&
                                   !authVM.firstName.trimmingCharacters(in: .whitespaces).isEmpty {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        focusedField = nil
                                    }
                                }
                                // For manual typing (single character changes), keep focus on lastName
                            }
                    }
                    
                    // Birthday
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.primaryGold)
                            Text("Birthday")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                            Text("(for rewards!)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.modernSecondary)
                        }
                        
                        DatePicker("Birthday", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(WheelDatePickerStyle())
                            .labelsHidden()
                            .frame(height: 120)
                            .clipped()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Theme.modernSecondary.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .onChange(of: selectedDate) { newDate in
                                authVM.birthday = dateFormatter.string(from: newDate)
                            }
                    }
                    
                    // Referral Code - special highlighting
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.energyOrange)
                            Text("Referral Code")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                            Text("(optional)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.modernSecondary)
                        }
                        
                        TextField("Enter code for bonus points!", text: $authVM.referralCodeEntered)
                            .textContentType(.none)
                            .autocapitalization(.allCharacters)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(authVM.referralCodeEntered.isEmpty ? Color.white : Theme.energyOrange.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                focusedField == .referralCode ? Theme.energyOrange :
                                                    !authVM.referralCodeEntered.isEmpty ? Theme.energyOrange.opacity(0.5) :
                                                    Theme.modernSecondary.opacity(0.2),
                                                lineWidth: focusedField == .referralCode || !authVM.referralCodeEntered.isEmpty ? 2 : 1
                                            )
                                    )
                            )
                            .focused($focusedField, equals: .referralCode)
                            .submitLabel(.done)
                            .onSubmit { authVM.createAccountAndSaveDetails() }
                        
                        if !authVM.referralCodeEntered.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.energyGreen)
                                Text("Code entered! You'll get bonus points")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.energyGreen)
                            }
                        }
                    }
                    .id(ScrollTarget.referralField)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Theme.darkGoldGradient, lineWidth: 2)
                        )
                        .shadow(color: Theme.primaryGold.opacity(0.15), radius: 12, x: 0, y: 6)
                )
                    .padding(.horizontal, 20)
                    .scaleEffect(cardAnimated ? 1.0 : 0.95)
                    .opacity(cardAnimated ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: cardAnimated)
                    
                    Spacer(minLength: 16)
                }
                // Extra scroll space so the referral field can move above the keyboard
                // while we keep the bottom action bar fixed.
                .padding(.bottom, max(0, min(keyboardHeight > 0 && keyboardHeight.isFinite ? (keyboardHeight + 160) : 0, 1000)))
            }
            .onChange(of: focusedField) { newValue in
                guard newValue == .referralCode else { return }
                // Scroll immediately when field is focused, then again after keyboard appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(ScrollTarget.referralField, anchor: .center)
                    }
                }
                // Secondary scroll after keyboard is fully shown to ensure proper positioning
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if focusedField == .referralCode {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(ScrollTarget.referralField, anchor: .center)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // Scroll when keyboard is about to show
                if focusedField == .referralCode {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(ScrollTarget.referralField, anchor: .center)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      frame.origin.y.isFinite && frame.origin.y >= 0,
                      frame.size.height.isFinite && frame.size.height >= 0,
                      frame.size.width.isFinite && frame.size.width >= 0 else { 
                    keyboardHeight = 0
                    return 
                }
                let screenHeight = UIScreen.main.bounds.height
                guard screenHeight.isFinite && screenHeight > 0 else {
                    keyboardHeight = 0
                    return
                }
                let calculatedHeight = screenHeight - frame.origin.y
                let newHeight = max(0, min(calculatedHeight, screenHeight))
                // Ensure height is finite and valid
                keyboardHeight = (newHeight.isFinite && newHeight >= 0) ? newHeight : 0
                if focusedField == .referralCode && keyboardHeight > 0 && keyboardHeight.isFinite {
                    // Scroll when keyboard frame changes to keep field visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(ScrollTarget.referralField, anchor: .center)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            }
            
            // Action button - outside ScrollView so always visible
            VStack(spacing: 12) {
                if authVM.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.0)
                            .tint(Theme.primaryGold)
                        Text("Creating your account...")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                    }
                    .padding()
                } else {
                    Button(action: {
                        authVM.createAccountAndSaveDetails()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .black))
                            
                            Text("CREATE ACCOUNT")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .tracking(0.5)
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18, weight: .black))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .disabled(authVM.firstName.isEmpty || authVM.lastName.isEmpty)
                    .opacity(authVM.firstName.isEmpty || authVM.lastName.isEmpty ? 0.6 : 1.0)
                    .scaleEffect(buttonAnimated ? 1.0 : 0.95)
                    .opacity(buttonAnimated ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: buttonAnimated)
                }
                
                if !authVM.errorMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(Theme.energyRed)
                        Text(authVM.errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.energyRed)
                    }
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.bottom, 30)
            .background(Theme.modernBackground)
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarHidden(true)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.primaryGold)
                }
            }
        }
        .onAppear {
            // Auto-fill referral code from deep link
            if authVM.referralCodeEntered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let pending = ReferralDeepLinkStore.getPending() {
                authVM.referralCodeEntered = pending
            }
            // Trigger animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                headerAnimated = true
                cardAnimated = true
                buttonAnimated = true
            }
            // Focus first field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                focusedField = .firstName
            }
        }
    }
}

// MARK: - Email Authentication View - REMOVED
// Email authentication has been removed to simplify the app and focus on Apple Sign-In and phone authentication
