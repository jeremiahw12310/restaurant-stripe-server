import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

class AuthenticationViewModel: ObservableObject {
    
    // MARK: - User Inputs
    @Published var phoneDigits: [String] = Array(repeating: "", count: 10)
    @Published var pinDigits: [String] = Array(repeating: "", count: 6)
    @Published var pinConfirmationDigits: [String] = Array(repeating: "", count: 6)
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var birthday = ""
    @Published var referralCode = ""
    
    // MARK: - State Properties
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var accountExists: Bool?
    @Published private(set) var userDocumentID: String?
    
    // MARK: - Navigation Triggers
    @Published var didAuthenticate = false
    @Published var shouldNavigateToUserDetails = false
    @Published var shouldNavigateToCustomization = false
    @Published var shouldNavigateToSplash = false
    @Published var showResetOption = false
    
    // MARK: - Computed Properties
    var phoneNumber: String { "+1" + phoneDigits.joined() }
    var pin: String { pinDigits.joined() }
    
    private var db = Firestore.firestore()
    
    // MARK: - Main Logic
    
    func checkIfPhoneExists() {
        guard phoneNumber.count == 12 else {
            errorMessage = "Please enter a valid 10-digit phone number."; return
        }
        isLoading = true; errorMessage = ""
        
        db.collection("users").whereField("phone", isEqualTo: phoneNumber).getDocuments { [weak self] (snapshot, error) in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Error: \(error.localizedDescription)"; return
                }
                
                if let document = snapshot?.documents.first {
                    self?.accountExists = true
                    self?.userDocumentID = document.documentID
                } else {
                    self?.accountExists = false
                    self?.userDocumentID = nil
                }
            }
        }
    }
    
    func signInWithPin() {
        guard pin.count == 6 else { errorMessage = "Please enter your 6-digit PIN."; return }
        isLoading = true; errorMessage = ""
        showResetOption = false
        
        let emailForAuth = "\(phoneNumber)@example.com"
        Auth.auth().signIn(withEmail: emailForAuth, password: pin) { [weak self] (result, error) in
            DispatchQueue.main.async {
                self?.isLoading = false
                if error != nil {
                    self?.errorMessage = "Incorrect PIN. Please try again."
                    self?.showResetOption = true
                    self?.pinDigits = Array(repeating: "", count: 6)
                } else {
                    self?.didAuthenticate = true
                }
            }
        }
    }
    
    func createAccountAndSaveDetails() {
        guard validateNewAccountDetails() else { return }
        isLoading = true; errorMessage = ""
        
        let emailForAuth = "\(phoneNumber)@example.com"
        
        Auth.auth().createUser(withEmail: emailForAuth, password: pin) { [weak self] (result, error) in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Could not create account: \(error.localizedDescription)"
                }; return
            }
            guard let uid = result?.user.uid else {
                DispatchQueue.main.async { self.isLoading = false; self.errorMessage = "Failed to get user ID." }; return
            }
            self.saveUserDetailsToFirestore(uid: uid)
        }
    }
    
    // ✅ FIX: Replaced the flawed `deleteAccount` function with a safe alternative.
    // This new function informs the user what to do instead of attempting an
    // impossible client-side operation, which was causing the crash.
    func requestPinReset() {
        errorMessage = "Account reset from the app is not available. Please contact support to recover your account."
        // Hide the button after one press to prevent spamming and reduce confusion.
        showResetOption = false
    }
    
    func reset() {
        phoneDigits = Array(repeating: "", count: 10)
        pinDigits = Array(repeating: "", count: 6)
        pinConfirmationDigits = Array(repeating: "", count: 6)
        errorMessage = ""; accountExists = nil; isLoading = false
        userDocumentID = nil; showResetOption = false; shouldNavigateToSplash = false
    }
    
    // MARK: - Private Helpers
    
    private func saveUserDetailsToFirestore(uid: String) {
        let userData: [String: Any] = [
            "uid": uid, "phone": phoneNumber, "firstName": firstName, "lastName": lastName,
            "birthday": birthday, "referralCode": referralCode, "points": 9000, "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(uid).setData(userData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = "Auth account created, but failed to save details: \(error.localizedDescription)"
                }
                self?.shouldNavigateToCustomization = true
            }
        }
    }
    
    private func validateNewAccountDetails() -> Bool {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "First and last name are required."; return false
        }
        return true
    }
    
    func validatePinCreation() {
        if pin.count < 6 { errorMessage = "Please create a 6-digit PIN."; return }
        if pin != pinConfirmationDigits.joined() {
            errorMessage = "PINs do not match. Please try again."
            pinDigits = Array(repeating: "", count: 6)
            pinConfirmationDigits = Array(repeating: "", count: 6)
            return
        }
        errorMessage = ""
        shouldNavigateToUserDetails = true
    }
}
