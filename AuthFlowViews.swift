import SwiftUI
import FirebaseAuth

// MARK: - Main Container (The Router)
struct AuthFlowView: View {
    @StateObject private var authVM = AuthenticationViewModel()
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        // ✅ FIX: Removed the nested NavigationStack to prevent potential conflicts and crashes.
        // The view will now correctly use the NavigationStack from SplashView.
        Group {
            if authVM.accountExists == nil {
                EnterPhoneView()
            } else if authVM.accountExists == true {
                EnterPinView()
            } else { // accountExists is false
                if authVM.shouldNavigateToUserDetails == false {
                    CreatePinView()
                } else if authVM.shouldNavigateToCustomization == false {
                    UserDetailsEntryView()
                } else {
                    AccountCustomizationView(uid: Auth.auth().currentUser?.uid ?? "")
                }
            }
        }
        .environmentObject(authVM)
        .onReceive(authVM.$didAuthenticate) { didAuth in
            if didAuth {
                isLoggedIn = true
            }
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
    @FocusState private var focusedIndex: Int?
    
    var body: some View {
        VStack(spacing: 30) {
            Text("What's your phone number?")
                .font(.title2).bold()
            
            DigitInputView(title: "Your phone number", digits: $authVM.phoneDigits, focusedIndex: $focusedIndex)
            
            Button("Clear All") {
                authVM.phoneDigits = Array(repeating: "", count: 10)
                focusedIndex = 0
            }
            .foregroundColor(.secondary)
            .padding(.top, -15)

            if authVM.isLoading { ProgressView() }
            else {
                Button("Continue") {
                    authVM.checkIfPhoneExists()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            
            if !authVM.errorMessage.isEmpty {
                 Text(authVM.errorMessage).foregroundColor(.red).padding().multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Sign In / Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            authVM.reset()
            focusedIndex = 0
        }
    }
}

// MARK: - Screen 2a: Enter PIN (Existing User)
struct EnterPinView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @FocusState private var focusedIndex: Int?

    var body: some View {
        VStack(spacing: 30) {
            Text("Account Detected!").font(.title2).bold().foregroundColor(.green)
            Text("Welcome back. Please enter your PIN to continue.").multilineTextAlignment(.center).padding(.horizontal)
            DigitInputView(title: "Your 6-digit PIN", digits: $authVM.pinDigits, isSecure: true, focusedIndex: $focusedIndex)
            
            Button("Clear All") {
                authVM.pinDigits = Array(repeating: "", count: 6)
                focusedIndex = 0
            }
            .foregroundColor(.secondary)
            .padding(.top, -15)
            
            if authVM.isLoading { ProgressView() }
            else { Button("Log In") { authVM.signInWithPin() }.buttonStyle(PrimaryButtonStyle()) }
            
            if !authVM.errorMessage.isEmpty { Text(authVM.errorMessage).foregroundColor(.red).padding().multilineTextAlignment(.center) }
            
            // ✅ FIX: Replaced the crashing NavigationLink with a safe Button.
            // This now calls a function that simply displays an error message,
            // preventing the crash and the broken "delete" logic.
            if authVM.showResetOption {
                Button("Forgot PIN?") {
                    authVM.requestPinReset()
                }
                .buttonStyle(PrimaryButtonStyle(backgroundColor: .orange))
                .padding(.top, 5)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Enter PIN")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusedIndex = 0 }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { authVM.reset() }
            }
        }
    }
}

// ✅ FIX: Removed the `DeleteAccountView` entirely as it was based on flawed logic that
// could not be securely implemented and was the source of the crash.

// MARK: - Screen 2b: Create PIN (New User)
struct CreatePinView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    @FocusState private var pinFocusedIndex: Int?
    @FocusState private var confirmPinFocusedIndex: Int?
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Create Your PIN").font(.title2).bold()
            DigitInputView(title: "Create a 6-digit PIN", digits: $authVM.pinDigits, isSecure: true, focusedIndex: $pinFocusedIndex)
            DigitInputView(title: "Confirm your PIN", digits: $authVM.pinConfirmationDigits, isSecure: true, focusedIndex: $confirmPinFocusedIndex)
            
            Button("Clear All") {
                authVM.pinDigits = Array(repeating: "", count: 6)
                authVM.pinConfirmationDigits = Array(repeating: "", count: 6)
                pinFocusedIndex = 0
            }
            .foregroundColor(.secondary)
            .padding(.top, -15)
            
            Button("Continue") {
                authVM.validatePinCreation()
            }
            .buttonStyle(PrimaryButtonStyle())
            
            if !authVM.errorMessage.isEmpty { Text(authVM.errorMessage).foregroundColor(.red) }
            Spacer()
        }
        .padding()
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pinFocusedIndex = 0 }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { authVM.reset() }
            }
        }
    }
}

// MARK: - Screen 3: Enter User Details
struct UserDetailsEntryView: View {
    @EnvironmentObject var authVM: AuthenticationViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Almost done!").font(.title2).bold()
            
            Group {
                TextField("First Name (required)", text: $authVM.firstName)
                TextField("Last Name (required)", text: $authVM.lastName)
                TextField("Birthday (MM/DD/YYYY)", text: $authVM.birthday)
                TextField("Referral Code (optional)", text: $authVM.referralCode)
            }
            .padding().background(Color.gray.opacity(0.1)).cornerRadius(10)

            if authVM.isLoading { ProgressView() }
            else {
                Button("Create Account & Finish") { authVM.createAccountAndSaveDetails() }
                    .buttonStyle(PrimaryButtonStyle(backgroundColor: .green))
            }
            
            if !authVM.errorMessage.isEmpty { Text(authVM.errorMessage).foregroundColor(.red) }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Your Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
