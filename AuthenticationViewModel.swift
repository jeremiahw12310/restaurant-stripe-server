import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

class AuthenticationViewModel: ObservableObject {
    
    // MARK: - User Inputs
    @Published var phoneNumber: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var birthday = ""
    @Published var referralCode = ""
    @Published var smsCode: String = ""
    @Published var verificationID: String? = nil
    @Published var isVerifying: Bool = false
    @Published var acceptedPrivacyPolicy: Bool = false
    
    // MARK: - State Properties
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var accountExists: Bool?
    @Published private(set) var userDocumentID: String?
    @Published var isEmailMode: Bool = false
    
    // MARK: - Navigation Triggers
    @Published var didAuthenticate = false
    @Published var shouldNavigateToUserDetails = false
    @Published var shouldNavigateToCustomization = false
    @Published var shouldNavigateToSplash = false
    
    // MARK: - Computed Properties
    var formattedPhoneNumber: String { 
        // Extract digits and format for Firebase
        let digits = phoneNumber.filter { $0.isNumber }
        return "+1" + digits
    }
    
    private var db = Firestore.firestore()
    
    // MARK: - Main Logic
    
    func sendVerificationCode() {
        guard formattedPhoneNumber.count == 12 else {
            errorMessage = "Please enter a valid 10-digit phone number."; return
        }
        guard acceptedPrivacyPolicy else {
            errorMessage = "Please accept the Privacy Policy to continue."; return
        }
        isLoading = true; errorMessage = ""
        PhoneAuthProvider.provider().verifyPhoneNumber(formattedPhoneNumber, uiDelegate: nil) { [weak self] verificationID, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Failed to send code: \(error.localizedDescription)"; return
                }
                self?.verificationID = verificationID
            }
        }
    }
    
    func signInWithEmail() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password."; return
        }
        guard acceptedPrivacyPolicy else {
            errorMessage = "Please accept the Privacy Policy to continue."; return
        }
        isLoading = true; errorMessage = ""
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Sign in failed: \(error.localizedDescription)"; return
                }
                guard let uid = result?.user.uid else {
                    self?.errorMessage = "Failed to get user ID."; return
                }
                self?.checkIfUserExists(uid: uid)
            }
        }
    }
    
    func createAccountWithEmail() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password."; return
        }
        guard acceptedPrivacyPolicy else {
            errorMessage = "Please accept the Privacy Policy to continue."; return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."; return
        }
        isLoading = true; errorMessage = ""
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Account creation failed: \(error.localizedDescription)"; return
                }
                guard let uid = result?.user.uid else {
                    self?.errorMessage = "Failed to get user ID."; return
                }
                self?.shouldNavigateToUserDetails = true
            }
        }
    }
    
    func verifyCodeAndSignIn() {
        guard let verificationID = verificationID, !smsCode.isEmpty else {
            errorMessage = "Please enter the code sent to your phone."; return
        }
        isVerifying = true; errorMessage = ""
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: smsCode)
        Auth.auth().signIn(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isVerifying = false
                if let error = error {
                    self?.errorMessage = "Verification failed: \(error.localizedDescription)"; return
                }
                guard let uid = result?.user.uid else {
                    self?.errorMessage = "Failed to get user ID."; return
                }
                self?.checkIfUserExists(uid: uid)
            }
        }
    }
    
    private func checkIfUserExists(uid: String) {
        isLoading = true
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Error: \(error.localizedDescription)"; return
                }
                if let data = snapshot?.data(), !data.isEmpty {
                    self?.didAuthenticate = true
                } else {
                    self?.shouldNavigateToUserDetails = true
                }
            }
        }
    }
    
    func reset() {
        print("🔵 reset() called")
        phoneNumber = ""
        email = ""
        password = ""
        errorMessage = ""; accountExists = nil; isLoading = false
        userDocumentID = nil; shouldNavigateToSplash = false
        smsCode = ""
        verificationID = nil
        isVerifying = false
        acceptedPrivacyPolicy = false
        isEmailMode = false
        // Don't reset navigation states here as they're needed for the flow
        // didAuthenticate = false
        // shouldNavigateToUserDetails = false
        // shouldNavigateToCustomization = false
    }
    
    func resetPhoneAndSMS() {
        print("🔵 resetPhoneAndSMS() called")
        phoneNumber = ""
        smsCode = ""
        verificationID = nil
        isVerifying = false
        errorMessage = ""
        isLoading = false
    }
    
    func createAccountAndSaveDetails() {
        print("🔵 createAccountAndSaveDetails called")
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated."; return
        }
        guard validateNewAccountDetails() else { return }
        isLoading = true; errorMessage = ""
        print("🔵 About to save user details for UID: \(uid)")
        saveUserDetailsToFirestore(uid: uid)
    }
    
    // MARK: - Private Helpers
    
    private func saveUserDetailsToFirestore(uid: String) {
        print("🔵 saveUserDetailsToFirestore called")
        let userData: [String: Any] = [
            "uid": uid, 
            "phone": formattedPhoneNumber, 
            "email": email,
            "firstName": firstName, 
            "lastName": lastName,
            "birthday": birthday, 
            "referralCode": referralCode, 
            "points": 9000, 
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        print("🔵 Saving user data: \(userData)")
        
        db.collection("users").document(uid).setData(userData) { [weak self] error in
            DispatchQueue.main.async {
                print("🔵 Firestore save completed")
                self?.isLoading = false
                if let error = error {
                    print("🔴 Firestore error: \(error.localizedDescription)")
                    self?.errorMessage = "Auth account created, but failed to save details: \(error.localizedDescription)"
                } else {
                    print("✅ Firestore save successful, setting shouldNavigateToCustomization = true")
                    self?.shouldNavigateToCustomization = true
                    print("✅ shouldNavigateToCustomization is now: \(self?.shouldNavigateToCustomization ?? false)")
                }
            }
        }
    }
    
    private func validateNewAccountDetails() -> Bool {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "First and last name are required."; return false
        }
        return true
    }
    
    // Debug method to manually trigger customization navigation
    func forceNavigateToCustomization() {
        print("🔵 forceNavigateToCustomization called")
        shouldNavigateToCustomization = true
        print("✅ shouldNavigateToCustomization set to: \(shouldNavigateToCustomization)")
    }
}
