import SwiftUI
import FirebaseAuth

// MARK: - Main Container (The Router)
struct AuthFlowView: View {
    @StateObject private var authVM = AuthenticationViewModel()
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Adaptive background that works in both light and dark mode
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // ✅ FIX: Removed the nested NavigationStack to prevent potential conflicts and crashes.
            // The view will now correctly use the NavigationStack from SplashView.
            Group {
                if authVM.isEmailMode {
                    EmailAuthView()
                } else if authVM.shouldNavigateToCustomization == true {
                    Text("Showing AccountCustomizationView")
                        .onAppear { print("🔵 Navigation: AccountCustomizationView") }
                    AccountCustomizationView(uid: Auth.auth().currentUser?.uid ?? "")
                } else if authVM.didAuthenticate {
                    // User exists, go to ContentView
                    Text("Showing ContentView")
                        .onAppear { print("🔵 Navigation: ContentView") }
                    ContentView()
                } else if authVM.shouldNavigateToUserDetails == true {
                    Text("Showing UserDetailsEntryView")
                        .onAppear { print("🔵 Navigation: UserDetailsEntryView") }
                    UserDetailsEntryView()
                } else if authVM.verificationID == nil {
                    Text("Showing EnterPhoneView")
                        .onAppear { print("🔵 Navigation: EnterPhoneView") }
                    EnterPhoneView()
                } else if !authVM.didAuthenticate && !authVM.shouldNavigateToUserDetails {
                    Text("Showing EnterCodeView")
                        .onAppear { print("🔵 Navigation: EnterCodeView") }
                    EnterCodeView()
                } else {
                    Text("No navigation condition met")
                        .onAppear { 
                            print("🔴 No navigation condition met!")
                            print("🔵 verificationID: \(authVM.verificationID?.prefix(10) ?? "nil")")
                            print("🔵 didAuthenticate: \(authVM.didAuthenticate)")
                            print("🔵 shouldNavigateToUserDetails: \(authVM.shouldNavigateToUserDetails)")
                            print("🔵 shouldNavigateToCustomization: \(authVM.shouldNavigateToCustomization)")
                        }
                }
            }
            .environmentObject(authVM)
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
            .onReceive(authVM.$shouldNavigateToSplash) { shouldNavigate in
                if shouldNavigate {
                    authVM.reset()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Screen 1: Enter Phone Number
struct EnterPhoneView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Beautiful header
            VStack(spacing: 16) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("Welcome to Dumpling House!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Sign in to earn loyalty points, track your orders, and get exclusive rewards")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
            
            // Phone input with beautiful styling
            VStack(spacing: 20) {
                PhoneNumberInputView(title: "Your phone number", phoneNumber: $authVM.phoneNumber)
                    .padding(.horizontal, 20)
                
                Button("Clear All") {
                    authVM.phoneNumber = ""
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 200)
            
            // Privacy Policy Checkbox
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: {
                        authVM.acceptedPrivacyPolicy.toggle()
                    }) {
                        Image(systemName: authVM.acceptedPrivacyPolicy ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(authVM.acceptedPrivacyPolicy ? .blue : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I accept the")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        +
                        Text(" Privacy Policy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                        +
                        Text(" and")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        +
                        Text(" Terms of Service")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                
                // Email authentication option
                VStack(spacing: 12) {
                    Divider()
                        .background(Color(.separator))
                        .padding(.horizontal, 20)
                    
                    Text("Or continue with email")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Button("Sign in with Email") {
                        authVM.isEmailMode = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.horizontal, 20)
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                if authVM.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                } else {
                    Button("Continue with Phone") {
                        authVM.sendVerificationCode()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                }
                
                if !authVM.errorMessage.isEmpty {
                    Text(authVM.errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .navigationTitle("Sign In / Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            authVM.resetPhoneAndSMS()
        }
    }
}

// MARK: - Screen 2: Enter SMS Code
struct EnterCodeView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var codeFocused: Bool
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "message.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                Text("Enter the code we sent you")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text("Check your SMS messages for a 6-digit code.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            VStack(spacing: 20) {
                TextField("6-digit code", text: $authVM.smsCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                    .focused($codeFocused)
            }
            Spacer()
            VStack(spacing: 16) {
                if authVM.isVerifying {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                } else {
                    Button("Verify & Continue") {
                        authVM.verifyCodeAndSignIn()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                }
                if !authVM.errorMessage.isEmpty {
                    Text(authVM.errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .navigationTitle("Verify Code")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            codeFocused = true
        }
    }
}

// MARK: - Screen 3: Enter User Details
struct UserDetailsEntryView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Beautiful header
            VStack(spacing: 16) {
                Image(systemName: "person.badge.plus.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("Almost done!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Tell us a bit about yourself")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            
            // Form fields with beautiful styling
            VStack(spacing: 20) {
                BeautifulTextField(placeholder: "First Name (required)", text: $authVM.firstName)
                    .textContentType(.givenName)
                    .autocapitalization(.words)
                
                BeautifulTextField(placeholder: "Last Name (required)", text: $authVM.lastName)
                    .textContentType(.familyName)
                    .autocapitalization(.words)
                
                // Birthday with DatePicker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Birthday")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    DatePicker("Birthday", selection: Binding(
                        get: {
                            if let date = dateFormatter.date(from: authVM.birthday) {
                                return date
                            }
                            return Date()
                        },
                        set: { newDate in
                            authVM.birthday = dateFormatter.string(from: newDate)
                        }
                    ), displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.05), radius: 5, x: 0, y: 2)
                }
                
                BeautifulTextField(placeholder: "Referral Code (optional)", text: $authVM.referralCode)
                    .textContentType(.none)
                    .autocapitalization(.none)
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                if authVM.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                } else {
                    Button("Create Account & Finish") {
                        authVM.createAccountAndSaveDetails()
                    }
                    .buttonStyle(PrimaryButtonStyle(backgroundColor: .green))
                    .padding(.horizontal, 20)
                }
                
                if !authVM.errorMessage.isEmpty {
                    Text(authVM.errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .navigationTitle("User Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { authVM.reset() }
                    .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Email Authentication View
struct EmailAuthView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isSignUp = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Beautiful header
            VStack(spacing: 16) {
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text(isSignUp ? "Create Account" : "Sign In")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Use your email to access your account and earn loyalty points")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
            
            // Email and Password inputs
            VStack(spacing: 20) {
                BeautifulTextField(placeholder: "Email address", text: $authVM.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                BeautifulTextField(placeholder: "Password", text: $authVM.password, isSecure: true)
                    .textContentType(isSignUp ? .newPassword : .password)
                
                if isSignUp {
                    Text("Password must be at least 6 characters")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            
            // Privacy Policy Checkbox
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: {
                        authVM.acceptedPrivacyPolicy.toggle()
                    }) {
                        Image(systemName: authVM.acceptedPrivacyPolicy ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(authVM.acceptedPrivacyPolicy ? .blue : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I accept the")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        +
                        Text(" Privacy Policy")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                        +
                        Text(" and")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        +
                        Text(" Terms of Service")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                if authVM.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                } else {
                    Button(isSignUp ? "Create Account" : "Sign In") {
                        if isSignUp {
                            authVM.createAccountWithEmail()
                        } else {
                            authVM.signInWithEmail()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                }
                
                // Toggle between sign in and sign up
                Button(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up") {
                    isSignUp.toggle()
                    authVM.errorMessage = ""
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 20)
                
                // Back to phone option
                Button("Back to Phone Sign In") {
                    authVM.isEmailMode = false
                    authVM.errorMessage = ""
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 20)
                
                if !authVM.errorMessage.isEmpty {
                    Text(authVM.errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .navigationTitle(isSignUp ? "Create Account" : "Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { 
                    authVM.isEmailMode = false
                    authVM.errorMessage = ""
                }
                .foregroundColor(.blue)
            }
        }
    }
}
