import SwiftUI
import FirebaseAuth

struct MoreView: View {
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var sharedRewardsVM: RewardsViewModel
    @Environment(\.openURL) private var openURL
    @StateObject private var notificationService = NotificationService.shared

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
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Account") {
                    NavigationLink {
                        NotificationsCenterView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .frame(width: 22)
                            Text("Notifications")
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
                        .contentShape(Rectangle())
                    }
                    
                    if userVM.isAdmin {
                        NavigationLink {
                            AdminSuspiciousFlagsView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .frame(width: 22)
                                Text("Suspicious Activity")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        
                        NavigationLink {
                            AdminBannedHistoryView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.badge.xmark")
                                    .frame(width: 22)
                                Text("Banned Account History")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
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

                    NavigationLink {
                        FeedView()
                    } label: {
                        settingsRowLabel(title: "Community (Coming Soon)", systemImage: "person.3.fill")
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
            .navigationTitle("More")
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
        .padding(20)
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
}

private struct SafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}
