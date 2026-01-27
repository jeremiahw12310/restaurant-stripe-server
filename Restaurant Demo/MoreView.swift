import SwiftUI
import FirebaseAuth

struct MoreView: View {
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var sharedRewardsVM: RewardsViewModel
    @Environment(\.openURL) private var openURL
    @ObservedObject private var notificationService = NotificationService.shared

    @State private var showDietaryPreferences: Bool = false
    @State private var showRewards: Bool = false
    @State private var showAccountDeletion: Bool = false
    @State private var showSignOutConfirm: Bool = false

    @State private var safariDestination: SafariDestination? = nil
    @State private var missingLinkTitle: String = ""
    @State private var showMissingLinkAlert: Bool = false

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    userSummaryCard
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    notificationsPreviewCard
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Account") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        settingsRowLabel(title: "Notification Settings", systemImage: "gearshape.fill")
                    }
                    

                    Button {
                        showDietaryPreferences = true
                    } label: {
                        settingsRowLabel(title: "Dietary Preferences", systemImage: "leaf")
                    }

                    Button {
                        showRewards = true
                    } label: {
                        settingsRowLabel(title: "Rewards", systemImage: "gift.fill")
                    }
                }

                Section("Support & Legal") {
                    Button {
                        contactSupport()
                    } label: {
                        settingsRowLabel(title: "Contact Support", systemImage: "envelope")
                    }

                    Button {
                        openLegalLink(title: "Privacy Policy", url: Config.privacyPolicyURL)
                    } label: {
                        settingsRowLabel(title: "Privacy Policy", systemImage: "hand.raised")
                    }

                    Button {
                        openLegalLink(title: "Terms of Service", url: Config.termsOfServiceURL)
                    } label: {
                        settingsRowLabel(title: "Terms of Service", systemImage: "doc.text")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        settingsRowLabel(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button(role: .destructive) {
                        showAccountDeletion = true
                    } label: {
                        settingsRowLabel(title: "Delete Account", systemImage: "trash")
                    }
                } header: {
                    Text("Danger Zone")
                }
            }
            .listSectionSeparator(.hidden)
            .navigationTitle("More")
            .onAppear {
                // Clear notification badges when entering More tab
                if Auth.auth().currentUser != nil {
                    notificationService.markAllNotificationsAsRead()
                }
            }
            .sheet(isPresented: $showDietaryPreferences) {
                UserPreferencesView(uid: uid)
                    .environmentObject(userVM)
            }
            .sheet(isPresented: $showRewards) {
                UnifiedRewardsScreen(mode: .modal)
                    .environmentObject(userVM)
                    .environmentObject(sharedRewardsVM)
            }
            .sheet(isPresented: $showAccountDeletion) {
                AccountDeletionView()
                    .environmentObject(userVM)
            }
            .sheet(item: $safariDestination) { destination in
                SimplifiedSafariView(url: destination.url) {
                    safariDestination = nil
                }
            }
            .alert("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    userVM.signOut()
                }
            } message: {
                Text("You’ll need to log in again to access your account.")
            }
            .alert("Link Not Set", isPresented: $showMissingLinkAlert) {
                Button("OK") {}
            } message: {
                Text("No URL is configured yet for \(missingLinkTitle).")
            }
        }
    }

    // MARK: - Helpers
    private var userSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if userVM.isLoading {
                userSummarySkeleton
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)

                        Text("\(userVM.points) pts")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                            .monospacedDigit()
                    }

                    Spacer()

                    if !userBadges.isEmpty {
                        badgesRow
                    }
                }

                Divider()
                    .overlay(Color.black.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    infoRow(label: "Lifetime points", value: "\(userVM.lifetimePoints)")

                    if let masked = maskedPhone(userVM.phoneNumber) {
                        infoRow(label: "Phone", value: masked)
                    }

                    if userVM.hasAccountCreatedDate {
                        infoRow(label: "Member since", value: memberSinceText(userVM.accountCreatedDate))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 18, x: 0, y: 8)
                .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var userSummarySkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 140, height: 14)

                Spacer()

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 110, height: 22)
            }
            .redacted(reason: .placeholder)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 210, height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 180, height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 160, height: 12)
            }
            .redacted(reason: .placeholder)
        }
    }

    private var badgesRow: some View {
        HStack(spacing: 6) {
            ForEach(userBadges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.modernCardSecondary)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Theme.primaryGold.opacity(0.35), lineWidth: 1)
                            )
                    )
            }
        }
        .foregroundColor(Theme.modernSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Badges: \(userBadges.joined(separator: ", "))")
    }

    private var userBadges: [String] {
        var badges: [String] = []
        if userVM.isVerified { badges.append("Verified") }
        if userVM.isAdmin { badges.append("Admin") }
        if userVM.isEmployee { badges.append("Employee") }
        return badges
    }

    private var displayName: String {
        let trimmed = userVM.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "User" : trimmed
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func maskedPhone(_ phone: String) -> String? {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 4 else { return nil }
        let last4 = String(digits.suffix(4))
        return "••• ••• \(last4)"
    }

    private func memberSinceText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private func settingsRowLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
            Text(title)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func openLegalLink(title: String, url: URL?) {
        guard let url else {
            missingLinkTitle = title
            showMissingLinkAlert = true
            return
        }
        safariDestination = SafariDestination(url: url)
    }

    private func contactSupport() {
        if let email = Config.supportEmail, !email.isEmpty,
           let url = URL(string: "mailto:\(email)") {
            openURL(url)
        } else {
            missingLinkTitle = "Support Email"
            showMissingLinkAlert = true
        }
    }
    
    // MARK: - Notifications Preview Card
    
    private var notificationsPreviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.primaryGold)
                    
                    Text("Notifications")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }
                
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
            }
            
            // Notifications List (up to 3)
            let previewNotifications = Array(notificationService.notifications.prefix(3))
            
            if previewNotifications.isEmpty {
                // Empty State
                VStack(spacing: 8) {
                    Text("No notifications yet")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    
                    Text("You'll see updates here")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.modernSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(previewNotifications) { notification in
                        compactNotificationRow(notification: notification)
                    }
                }
            }
            
            // View All Button
            NavigationLink {
                NotificationsCenterView()
            } label: {
                HStack {
                    Spacer()
                    Text("View All Notifications")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.primaryGold)
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.primaryGold.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.primaryGold.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.primaryGold.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            // Ensure listener is active
            if Auth.auth().currentUser != nil {
                notificationService.startNotificationsListener()
            }
        }
    }
    
    private func compactNotificationRow(notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(notificationIconBackgroundColor(for: notification.type))
                    .frame(width: 32, height: 32)
                
                Image(systemName: notificationIcon(for: notification.type))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(notificationIconColor(for: notification.type))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(notification.title)
                        .font(.system(size: 14, weight: notification.read ? .medium : .semibold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !notification.read {
                        Circle()
                            .fill(Theme.primaryGold)
                            .frame(width: 6, height: 6)
                    }
                }
                
                HStack {
                    Text(notification.body)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(relativeTimeString(from: notification.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func notificationIcon(for type: AppNotification.NotificationType) -> String {
        switch type {
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
    
    private func notificationIconColor(for type: AppNotification.NotificationType) -> Color {
        switch type {
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
    
    private func notificationIconBackgroundColor(for type: AppNotification.NotificationType) -> Color {
        switch type {
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

private struct SafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}
