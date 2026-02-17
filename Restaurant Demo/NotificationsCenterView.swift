//
//  NotificationsCenterView.swift
//  Restaurant Demo
//
//  Displays all notifications including referral bonuses, reservation alerts, and general notifications
//

import SwiftUI
import FirebaseAuth

struct NotificationsCenterView: View {
    @ObservedObject private var notificationService = NotificationService.shared
    @Environment(\.dismiss) private var dismiss

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
    
    // MARK: - Notifications List (chronological with type separators)

    private func sectionTitleAndIcon(for type: AppNotification.NotificationType) -> (title: String, icon: String) {
        switch type {
        case .referral:
            return ("Friend Referrals", "person.badge.plus.fill")
        case .reservationNew:
            return ("Reservations", "calendar.badge.plus")
        case .adminBroadcast, .adminIndividual, .system, .rewardGift:
            return ("General", "bell.fill")
        }
    }

    private func typeSectionHeader(title: String, icon: String) -> some View {
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
    }

    private var notificationsList: some View {
        let notifications = notificationService.notifications
        return ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notification in
                    let showTypeHeader = index == 0 || notification.type != notifications[index - 1].type
                    let (sectionTitle, sectionIcon) = sectionTitleAndIcon(for: notification.type)

                    VStack(alignment: .leading, spacing: 10) {
                        if showTypeHeader {
                            typeSectionHeader(title: sectionTitle, icon: sectionIcon)
                        }
                        if notification.type == .reservationNew {
                            ReservationNotificationCard(notification: notification)
                        } else {
                            NotificationCard(notification: notification)
                        }
                    }
                    .padding(.top, (showTypeHeader && index > 0) ? 10 : 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .refreshable {
            if Auth.auth().currentUser != nil {
                notificationService.startNotificationsListener()
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
        case .reservationNew:
            return "calendar.badge.plus"
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
        case .reservationNew:
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
        case .reservationNew:
            return Theme.energyOrange.opacity(0.15)
        }
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Reservation Notification Card (Confirm / Call)

struct ReservationNotificationCard: View {
    let notification: AppNotification
    @State private var isConfirming = false
    @State private var confirmError: String?
    private let notificationService = NotificationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.energyOrange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.energyOrange)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(notification.title)
                        .font(.system(size: 16, weight: notification.read ? .medium : .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    Text(notification.body)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .lineLimit(3)
                    Text(relativeTimeString(from: notification.createdAt))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary.opacity(0.7))
                }
                Spacer()
                if !notification.read {
                    Circle()
                        .fill(Theme.primaryGold)
                        .frame(width: 8, height: 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openAdminOffice, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        NotificationCenter.default.post(name: .openAdminReservationsWithPendingFilter, object: nil)
                    }
                }
            }

            if let err = confirmError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                if let id = notification.reservationId, !id.isEmpty {
                    Button(action: { confirmReservation(id: id) }) {
                        HStack(spacing: 6) {
                            if isConfirming {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Confirm")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.energyGreen))
                    }
                    .disabled(isConfirming)
                }

                if let phone = notification.reservationPhone, !phone.isEmpty,
                   let url = URL(string: "tel:\(phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? phone)") {
                    Button(action: { UIApplication.shared.open(url) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14))
                            Text("Call")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.energyBlue))
                    }
                }
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
        .buttonStyle(PlainButtonStyle())
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func confirmReservation(id: String) {
        guard Auth.auth().currentUser != nil else {
            confirmError = "Please sign in to confirm."
            return
        }
        isConfirming = true
        confirmError = nil
        Auth.auth().currentUser?.getIDToken { token, err in
            if err != nil {
                DispatchQueue.main.async {
                    isConfirming = false
                    confirmError = "Sign-in error. Try again."
                }
                return
            }
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/reservations/\(id)") else {
                DispatchQueue.main.async {
                    isConfirming = false
                    confirmError = "Invalid configuration."
                }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "confirmed"])

            URLSession.shared.dataTask(with: request) { _, response, _ in
                DispatchQueue.main.async {
                    isConfirming = false
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        notificationService.markNotificationAsRead(notificationId: notification.id)
                    } else {
                        confirmError = "Failed to confirm. Try again."
                    }
                }
            }.resume()
        }
    }
}
