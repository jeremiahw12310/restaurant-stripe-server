import SwiftUI
import FirebaseAuth

/// In-app explanation shown *before* iOS displays the system notification prompt.
/// This improves user understanding and preserves Apple-compliant explicit opt-in for promotional notifications.
struct NotificationPrePermissionView: View {
    @ObservedObject private var notificationService = NotificationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var promotionalOptIn: Bool = false
    @State private var isSavingPromo: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        benefitsCard
                        promotionalOptInCard
                        ctaButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Stay Updated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGold.opacity(0.22), Theme.deepGold.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.darkGoldGradient)
            }
            .shadow(color: Theme.primaryGold.opacity(0.25), radius: 10, x: 0, y: 5)

            Text("Turn on notifications?")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .multilineTextAlignment(.center)

            Text("We’ll only send useful updates—no spam. You’re always in control.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you’ll get")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)

            benefitRow(icon: "gift.fill", title: "Rewards & points", subtitle: "Balance changes, redemptions, and key updates")
            benefitRow(icon: "person.badge.plus.fill", title: "Referrals", subtitle: "When friends join and you earn bonuses")
            benefitRow(icon: "info.circle.fill", title: "Account updates", subtitle: "Important notices about your account")

            Text("You can change these anytime in Notification Settings.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.primaryGold.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.primaryGold.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.primaryGold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var promotionalOptInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.energyBlue.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.energyBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Promotional notifications (optional)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    Text("Special offers and announcements. Optional and can be changed anytime.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("By enabling this, you agree to receive promotional notifications from Dumpling House. You can turn this off at any time.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $promotionalOptIn)
                    .labelsHidden()
                    .disabled(isSavingPromo)
                    .toggleStyle(SwitchToggleStyle(tint: Theme.primaryGold))
                    .onChange(of: promotionalOptIn) { _, newValue in
                        savePromotionalOptIn(newValue)
                    }
            }

            if isSavingPromo {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Saving…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.modernCardSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Theme.primaryGold.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var ctaButtons: some View {
        VStack(spacing: 12) {
            Button {
                notificationService.requestNotificationPermission { _ in
                    DispatchQueue.main.async {
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Enable Notifications")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding(.vertical, 14)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.primaryGold)
                )
            }

            Button {
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Not now")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.modernCardSecondary.opacity(0.35))
                )
            }
        }
        .padding(.top, 4)
    }

    private func savePromotionalOptIn(_ enabled: Bool) {
        guard Auth.auth().currentUser != nil else { return }
        isSavingPromo = true
        notificationService.updatePromotionalPreference(enabled: enabled) { success, error in
            DispatchQueue.main.async {
                self.isSavingPromo = false
                if let error = error {
                    self.errorMessage = "Failed to save preference: \(error.localizedDescription)"
                    self.showError = true
                    self.promotionalOptIn = !enabled
                    return
                }
                if !success {
                    self.errorMessage = "Failed to save preference."
                    self.showError = true
                    self.promotionalOptIn = !enabled
                }
            }
        }
    }
}

