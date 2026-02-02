//
//  NotificationsCenterView.swift
//  Restaurant Demo
//
//  Displays all notifications including referral bonuses and general notifications
//

import SwiftUI
import FirebaseAuth

struct NotificationsCenterView: View {
    @ObservedObject private var notificationService = NotificationService.shared
    @Environment(\.dismiss) private var dismiss
    
    private var referralNotifications: [AppNotification] {
        notificationService.notifications.filter { $0.type == .referral }
    }
    
    private var generalNotifications: [AppNotification] {
        notificationService.notifications.filter { $0.type != .referral }
    }
    
    private var hasUnreadNotifications: Bool {
        notificationService.unreadNotificationCount > 0
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Theme.modernBackground
                    .ignoresSafeArea()
                
                if notificationService.notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                // Ensure listener is active
                if Auth.auth().currentUser != nil {
                    notificationService.startNotificationsListener()
                    // Auto-mark all notifications as read when viewing
                    if notificationService.unreadNotificationCount > 0 {
                        notificationService.markAllNotificationsAsRead()
                    }
                }
            }
        }
    }
    
    // MARK: - Notifications List
    
    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Referral Notifications Section
                if !referralNotifications.isEmpty {
                    notificationSection(
                        title: "Friend Referrals",
                        notifications: referralNotifications,
                        icon: "person.badge.plus.fill"
                    )
                }
                
                // General Notifications Section
                if !generalNotifications.isEmpty {
                    notificationSection(
                        title: "General",
                        notifications: generalNotifications,
                        icon: "bell.fill"
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .refreshable {
            // Refresh notifications
            if Auth.auth().currentUser != nil {
                notificationService.startNotificationsListener()
            }
        }
    }
    
    private func notificationSection(title: String, notifications: [AppNotification], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.primaryGold)
                
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
                    .cornerRadius(1)
            }
            
            // Notification Cards
            VStack(spacing: 10) {
                ForEach(notifications) { notification in
                    NotificationCard(notification: notification)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.modernSecondary.opacity(0.5))
            
            Text("No Notifications")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            
            Text("You'll see friend referrals and updates here")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Notification Card

struct NotificationCard: View {
    let notification: AppNotification
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .top, spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(notificationBackgroundColor)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: notificationIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(notificationIconColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(notification.title)
                        .font(.system(size: 16, weight: notification.read ? .medium : .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                        .lineLimit(2)
                    
                    Text(notification.body)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .lineLimit(3)
                    
                    Text(relativeTimeString(from: notification.createdAt))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary.opacity(0.7))
                        .padding(.top, 2)
                }
                
                Spacer()
                
                // Unread Indicator
                if !notification.read {
                    Circle()
                        .fill(Theme.primaryGold)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(notification.read ? Theme.modernCardSecondary.opacity(0.3) : Theme.modernCardSecondary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(notification.read ? Color.clear : Theme.primaryGold.opacity(0.3), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: notification.read)
    }
    
    private func handleTap() {
        if notification.type == .rewardGift {
            // Post notification to navigate to rewards tab
            NotificationCenter.default.post(name: .navigateToRewardsTab, object: nil)
            dismiss()
        }
    }
    
    private var notificationIcon: String {
        switch notification.type {
        case .referral:
            return "person.badge.plus.fill"
        case .adminBroadcast, .adminIndividual:
            return "megaphone.fill"
        case .system:
            return "info.circle.fill"
        case .rewardGift:
            return "gift.fill"
        }
    }
    
    private var notificationIconColor: Color {
        switch notification.type {
        case .referral:
            return Theme.primaryGold
        case .adminBroadcast, .adminIndividual:
            return Theme.energyBlue
        case .system:
            return Theme.modernSecondary
        case .rewardGift:
            return Theme.energyOrange
        }
    }
    
    private var notificationBackgroundColor: Color {
        switch notification.type {
        case .referral:
            return Theme.primaryGold.opacity(0.15)
        case .adminBroadcast, .adminIndividual:
            return Theme.energyBlue.opacity(0.15)
        case .system:
            return Theme.modernSecondary.opacity(0.1)
        case .rewardGift:
            return Theme.energyOrange.opacity(0.15)
        }
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
