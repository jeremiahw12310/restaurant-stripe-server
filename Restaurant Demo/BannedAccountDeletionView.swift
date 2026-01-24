//
//  BannedAccountDeletionView.swift
//  Restaurant Demo
//
//  Full-screen deletion-only view for banned users. Cannot be dismissed.
//  Users must delete their account to proceed.
//

import SwiftUI
import FirebaseAuth

struct BannedAccountDeletionView: View {
    @EnvironmentObject var userVM: UserViewModel
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @State private var isSendingCode: Bool = false
    @State private var isDeleting: Bool = false
    @State private var smsCode: String = ""
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.red)
                            Text("Account Banned")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                        
                        Text("Your account has been banned. You can delete your account below. Please contact support if you believe this is an error.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                
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
            .navigationTitle("Account Banned")
            // No close button - user cannot dismiss this screen
        }
        .onAppear {
            // If auth session is missing, force return to Get Started
            if Auth.auth().currentUser == nil {
                errorMessage = "Your session expired. Please sign in again."
                isLoggedIn = false
            } else {
                // Load user data so deletion can access profilePhotoURL if needed
                userVM.loadUserData()
            }
        }
    }
    
    private func sendCodeOrDelete() {
        isSendingCode = true
        errorMessage = nil
        
        // Use the new archive-based deletion for banned accounts
        // This archives user data to bannedAccountHistory before deletion
        userVM.archiveAndDeleteBannedAccount { started in
            DispatchQueue.main.async {
                isSendingCode = false
                if started {
                    // Either deletion succeeded immediately or SMS flow began
                    if !userVM.isAwaitingDeletionSMSCode {
                        // Deleted; force sign-out + return to Get Started
                        userVM.signOut()
                        isLoggedIn = false
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
        
        // Use the banned-specific finalization method
        userVM.finalizeBannedAccountDeletion(withSMSCode: code) { success in
            DispatchQueue.main.async {
                isDeleting = false
                if success {
                    // Deleted; force sign-out + return to Get Started
                    userVM.signOut()
                    isLoggedIn = false
                } else {
                    errorMessage = "Invalid or expired code. Please request a new code and try again."
                }
            }
        }
    }
}

#Preview {
    BannedAccountDeletionView()
        .environmentObject(UserViewModel())
}
