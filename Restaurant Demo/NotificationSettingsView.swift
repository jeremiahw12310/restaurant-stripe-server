//
//  NotificationSettingsView.swift
//  Restaurant Demo
//
//  User settings for notification preferences, including promotional opt-in/opt-out
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

struct NotificationSettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var promotionalNotificationsEnabled: Bool = false
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            headerSection
                            
                            // Permission Status
                            permissionStatusSection
                            
                            // Promotional Notifications Toggle
                            promotionalToggleSection
                            
                            // Notification Types Explanation
                            notificationTypesSection
                            
                            // iOS Settings Link
                            iosSettingsSection
                            
                            // View Notifications Link
                            viewNotificationsSection
                            
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Notification Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadPreferences()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
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
                
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.darkGoldGradient)
            }
            .shadow(color: Theme.primaryGold.opacity(0.3), radius: 10, x: 0, y: 4)
            
            Text("Manage Your Notifications")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.darkGoldGradient)
            
            Text("Control what notifications you receive")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Permission Status Section
    
    private var permissionStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: notificationService.hasNotificationPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(notificationService.hasNotificationPermission ? .green : .orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Permission")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    Text(notificationService.hasNotificationPermission ? "Notifications are enabled" : "Notifications are disabled")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                
                Spacer()
            }
            
            if !notificationService.hasNotificationPermission {
                Button {
                    openIOSSettings()
                } label: {
                    HStack {
                        Text("Enable in Settings")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.primaryGold)
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.primaryGold.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Promotional Toggle Section
    
    private var promotionalToggleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "megaphone.fill")
                    .foregroundColor(Theme.energyBlue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Promotional Notifications")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    Text("Special offers, announcements, and updates")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $promotionalNotificationsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Theme.primaryGold))
                    .onChange(of: promotionalNotificationsEnabled) { _, newValue in
                        savePromotionalPreference(enabled: newValue)
                    }
            }
            
            // Consent Language (Required by Apple)
            VStack(alignment: .leading, spacing: 8) {
                Text("By enabling this, you'll receive promotional notifications including special offers, announcements, and updates from Dumpling House. You can change this setting at any time.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.modernCardSecondary.opacity(0.3))
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.primaryGold.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Notification Types Section
    
    private var notificationTypesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification Types")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            
            VStack(alignment: .leading, spacing: 12) {
                notificationTypeRow(
                    icon: "person.badge.plus.fill",
                    title: "Friend Referrals",
                    description: "Always enabled - you'll be notified when friends join using your referral code",
                    color: Theme.primaryGold
                )
                
                notificationTypeRow(
                    icon: "gift.fill",
                    title: "Rewards & Points",
                    description: "Always enabled - updates about your rewards and points balance",
                    color: Theme.energyOrange
                )
                
                notificationTypeRow(
                    icon: "info.circle.fill",
                    title: "Account Updates",
                    description: "Always enabled - important account and security notifications",
                    color: Theme.modernSecondary
                )
                
                notificationTypeRow(
                    icon: "megaphone.fill",
                    title: "Promotional",
                    description: "Opt-in only - special offers, announcements, and marketing updates",
                    color: Theme.energyBlue,
                    isOptional: true
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.primaryGold.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func notificationTypeRow(icon: String, title: String, description: String, color: Color, isOptional: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    if isOptional {
                        Text("(Optional)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Theme.modernCardSecondary.opacity(0.5))
                            )
                    }
                }
                
                Text(description)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
    
    // MARK: - iOS Settings Section
    
    private var iosSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Settings")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            
            Text("For more granular control over notification sounds, badges, and lock screen display, you can adjust these in iOS Settings.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Button {
                openIOSSettings()
            } label: {
                HStack {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                    Text("Open iOS Settings")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.modernPrimary)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.modernCardSecondary.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.primaryGold.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.primaryGold.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - View Notifications Section
    
    private var viewNotificationsSection: some View {
        NavigationLink {
            NotificationsCenterView()
        } label: {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 16))
                Text("View All Notifications")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                if notificationService.unreadNotificationCount > 0 {
                    Text("\(notificationService.unreadNotificationCount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.primaryGold)
                        )
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.modernSecondary)
            }
            .foregroundColor(Theme.modernPrimary)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.modernCardSecondary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.primaryGold.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Methods
    
    private func loadPreferences() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        db.collection("users").document(uid).getDocument { [self] snapshot, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    print("❌ NotificationSettingsView: Error loading preferences: \(error.localizedDescription)")
                    errorMessage = "Failed to load preferences"
                    showError = true
                    return
                }
                
                if let data = snapshot?.data() {
                    promotionalNotificationsEnabled = data["promotionalNotificationsEnabled"] as? Bool ?? false
                } else {
                    // Default to false if field doesn't exist
                    promotionalNotificationsEnabled = false
                }
            }
        }
    }
    
    private func savePromotionalPreference(enabled: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        isSaving = true
        
        notificationService.updatePromotionalPreference(enabled: enabled) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isSaving = false
                
                if let error = error {
                    print("❌ NotificationSettingsView: Error saving preference: \(error.localizedDescription)")
                    self?.errorMessage = "Failed to save preference"
                    self?.showError = true
                    // Revert toggle on error
                    self?.promotionalNotificationsEnabled = !enabled
                } else if !success {
                    self?.errorMessage = "Failed to save preference"
                    self?.showError = true
                    self?.promotionalNotificationsEnabled = !enabled
                }
            }
        }
    }
    
    private func openIOSSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}
