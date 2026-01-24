//
//  AccountDeletionView.swift
//  Restaurant Demo
//
//  Provides a simple UI to drive phone re-authentication and full account deletion
//

import SwiftUI
import FirebaseAuth

struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userVM: UserViewModel
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @State private var isSendingCode: Bool = false
    @State private var isDeleting: Bool = false
    @State private var smsCode: String = ""
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What Happens When You Delete")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Permanently Deleted:")
                            .font(.subheadline.bold())
                        Text("• Your account and login credentials")
                        Text("• Points balance and points history")
                        Text("• Referral connections")
                        Text("• Notifications")
                        
                        Text("Anonymized (kept for records):")
                            .font(.subheadline.bold())
                            .padding(.top, 8)
                        Text("• Receipt scan history (shows as \"Deleted User\")")
                        Text("• Redeemed rewards history")
                        Text("• Community posts and replies")
                        
                        Text("This action is immediate and cannot be undone.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                
                if userVM.isAwaitingDeletionSMSCode {
                    Section(header: Text("Enter SMS Code")) {
                        TextField("123456", text: $smsCode)
                            .keyboardType(.numberPad)
                        Button(action: finalizeDeletion) {
                            if isDeleting {
                                ProgressView().progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Confirm Deletion")
                            }
                        }
                        .disabled(isDeleting || smsCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    Section {
                        Button(role: .destructive, action: sendCodeOrDelete) {
                            if isSendingCode {
                                ProgressView().progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Delete Account")
                            }
                        }
                        .disabled(isSendingCode)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Account Deletion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            // If auth session is missing, force return to Get Started (per desired behavior).
            // This prevents the user getting stuck on a delete screen that can never succeed.
            if Auth.auth().currentUser == nil {
                errorMessage = "Your session expired. Please sign in again."
                isLoggedIn = false
                // Dismiss on next runloop so the alert/message can set state without warnings.
                DispatchQueue.main.async {
                    dismiss()
                }
            }
        }
    }
    
    private func sendCodeOrDelete() {
        isSendingCode = true
        errorMessage = nil
        userVM.deleteAccount { started in
            DispatchQueue.main.async {
                isSendingCode = false
                if started {
                    // Either deletion succeeded immediately or SMS flow began
                    if !userVM.isAwaitingDeletionSMSCode {
                        // Deleted; force sign-out + return to Get Started
                        userVM.signOut()
                        isLoggedIn = false
                        dismiss()
                    }
                } else {
                    errorMessage = "Unable to start account deletion. Please try again."
                }
            }
        }
    }
    
    private func finalizeDeletion() {
        let code = smsCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isDeleting = true
        errorMessage = nil
        userVM.finalizeAccountDeletion(withSMSCode: code) { success in
            DispatchQueue.main.async {
                isDeleting = false
                if success {
                    // Deleted; force sign-out + return to Get Started
                    userVM.signOut()
                    isLoggedIn = false
                    dismiss()
                } else {
                    errorMessage = "Invalid or expired code. Please request a new code and try again."
                }
            }
        }
    }
}

#Preview {
    AccountDeletionView()
        .environmentObject(UserViewModel())
}


