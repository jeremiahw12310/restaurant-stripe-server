import SwiftUI

/// In-app explanation shown before iOS displays the camera permission prompt.
struct CameraPrePermissionView: View {
    let isPermissionDenied: Bool
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        benefitsCard
                        ctaButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Scan Receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Not now") { onDismiss() }
                }
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

                Image(systemName: "camera.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.darkGoldGradient)
            }
            .shadow(color: Theme.primaryGold.opacity(0.25), radius: 10, x: 0, y: 5)

            Text("Allow camera access?")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .multilineTextAlignment(.center)

            Text("We use your camera to scan receipts quickly and accurately.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why we need this")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)

            benefitRow(
                icon: "doc.viewfinder",
                title: "Fast scanning",
                subtitle: "Capture receipts in seconds with live detection"
            )
            benefitRow(
                icon: "checkmark.seal.fill",
                title: "Accurate points",
                subtitle: "Clear images help verify totals correctly"
            )
            benefitRow(
                icon: "lock.fill",
                title: "Privacy first",
                subtitle: "Camera access is only used during scanning"
            )

            Text("You can change this anytime in Settings.")
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

    private var ctaButtons: some View {
        VStack(spacing: 12) {
            Button {
                if isPermissionDenied {
                    onOpenSettings()
                } else {
                    onRequestAccess()
                }
            } label: {
                HStack {
                    Spacer()
                    Text(isPermissionDenied ? "Open Settings" : "Enable Camera")
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
                onDismiss()
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
}
