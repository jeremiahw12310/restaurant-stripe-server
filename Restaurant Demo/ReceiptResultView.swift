import SwiftUI

struct ReceiptResultView: View {
    let outcome: ReceiptScanOutcome
    var comboState: ComboGenerationState = .loading
    var personalizedCombo: PersonalizedCombo? = nil
    let onPrimary: (() -> Void)?
    let onSecondary: (() -> Void)?
    let onDismiss: (() -> Void)?
    var onRetryCombo: (() -> Void)? = nil
    var onViewCombo: (() -> Void)? = nil
    
    @EnvironmentObject var menuViewModel: MenuViewModel

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 20)

                hero
                    .frame(width: 220, height: 220)
                    .shadow(color: Theme.cardShadow, radius: 14, x: 0, y: 8)
                    .scaleEffect(1.02)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(heroAccessibilityLabel)

                VStack(spacing: 8) {
                    Text(WittyLineProvider.shared.headline(for: outcome))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(titleColor)
                        .padding(.horizontal, 24)

                    if let label = labelText {
                        Text(label)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(labelBackground)
                            )
                            .foregroundColor(labelForeground)
                    }

                    if let body = bodyText {
                        Text(body)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }

                if case .success(let points, let total) = outcome {
                    statsCard(points: points, total: total)
                        .padding(.top, 4)
                        .padding(.horizontal, 24)
                }

                Spacer()

                HStack(spacing: 12) {
                    if let secondary = secondaryButtonTitle {
                        Button(action: { onSecondary?() }) {
                            Text(secondary)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Theme.darkGoldGradient, lineWidth: 2)
                                )
                        }
                        .foregroundColor(Theme.modernPrimary)
                    }

                    if let primary = primaryButtonTitle {
                        Button(action: { onPrimary?() }) {
                            Text(primary)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Theme.darkGoldGradient)
                                        .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                                )
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }

            // Close affordance
            VStack {
                HStack {
                    Spacer()
                    Button(action: { onDismiss?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.25))
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
            // Subtle celebratory overlay on success
            if case .success = outcome {
                BobaRainView()
                    .allowsHitTesting(false)
                    .opacity(0.9)
            }
        }
    }

    private var backgroundView: some View {
        switch outcome {
        case .success:
            return AnyView(Theme.successGradient)
        default:
            return AnyView(
                LinearGradient(
                    gradient: Gradient(colors: [Theme.modernBackground, Theme.modernCardSecondary, Theme.modernBackground]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var hero: some View {
        switch outcome {
        case .duplicate:
            return AnyView(
                Image("herostop")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            )
        case .success:
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Theme.modernCard)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 100, weight: .bold))
                        .foregroundStyle(Theme.darkGoldGradient)
                }
            )
        case .notFromRestaurant:
            return AnyView(
                Image("herosad")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            )
        case .unreadable:
            return AnyView(systemHero("camera.viewfinder"))
        case .tooOld:
            return AnyView(systemHero("calendar.badge.exclamationmark"))
        case .mismatch:
            return AnyView(systemHero("exclamationmark.triangle.fill"))
        case .network:
            return AnyView(systemHero("wifi.exclamationmark"))
        case .server:
            return AnyView(systemHero("bolt.horizontal.circle.fill"))
        case .suspicious:
            return AnyView(systemHero("shield.lefthalf.filled"))
        case .rateLimited:
            return AnyView(systemHero("clock.fill"))
        }
    }

    private func systemHero(_ name: String) -> some View {
        ZStack {
            Circle().fill(Theme.modernCard)
            Image(systemName: name)
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(LinearGradient(
                    gradient: Gradient(colors: [Theme.energyOrange, Theme.energyRed]),
                    startPoint: .top, endPoint: .bottom
                ))
        }
    }

    private var labelText: String? {
        switch outcome {
        case .duplicate: return "Hero Alert"
        case .notFromRestaurant: return "Restaurant Mismatch"
        case .unreadable: return "Scan Issue"
        case .tooOld: return "Date Window"
        case .mismatch: return "Data Mismatch"
        case .network: return "Connection Issue"
        case .server: return "Server Issue"
        case .suspicious: return "Not Accepted"
        case .rateLimited: return "Rate Limited"
        case .success: return nil
        }
    }

    private var bodyText: String? {
        switch outcome {
        case .duplicate(let order, let date):
            var detail = "This receipt was already used."
            if let order = order, let date = date { detail = "This receipt was already used on \(date). Order #\(order)." }
            return detail
        case .notFromRestaurant: return "We can only accept receipts from Dumpling House."
        case .unreadable: return "Try brighter lighting and fill the frame."
        case .tooOld: return "Receipts must be scanned within 48 hours of purchase."
        case .mismatch: return "We couldn’t match totals. Check your photo and try again."
        case .network: return "You can retry in a moment."
        case .server: return "Please try again shortly."
        case .suspicious: return "This receipt cannot be processed at this time."
        case .rateLimited: return "Please wait a while and try again."
        case .success: return nil
        }
    }

    private var primaryButtonTitle: String? {
        switch outcome {
        case .success: return "View Rewards"
        case .duplicate: return "View History"
        case .notFromRestaurant: return "Got It"
        case .unreadable: return "Got It"
        case .tooOld: return "Got It"
        case .mismatch: return "Got It"
        case .network: return "Retry"
        case .server: return "Retry"
        case .suspicious: return "Got It"
        case .rateLimited: return "Got It"
        }
    }

    private var secondaryButtonTitle: String? {
        switch outcome {
        case .success: return "Order Now"
        default: return "Scan Another"
        }
    }

    private var titleColor: Color {
        switch outcome {
        case .success: return .white
        default: return Theme.modernPrimary
        }
    }

    private var labelBackground: Color {
        switch outcome {
        case .success: return Color.white.opacity(0.18)
        default: return Theme.modernCard
        }
    }

    private var labelForeground: Color {
        switch outcome {
        case .success: return .white
        default: return Theme.modernSecondary
        }
    }

    private var heroAccessibilityLabel: String {
        switch outcome {
        case .duplicate: return "Receipt already used"
        case .success: return "+points added"
        case .notFromRestaurant: return "Receipt from different restaurant"
        case .unreadable: return "Receipt unreadable"
        case .tooOld: return "Receipt too old"
        case .mismatch: return "Totals mismatch"
        case .network: return "Network issue"
        case .server: return "Server issue"
        case .suspicious: return "Receipt not accepted"
        case .rateLimited: return "Rate limited"
        }
    }

    private func statsCard(points: Int, total: Double) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Receipt Total")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: "$%.2f", total))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            HStack {
                Text("Points Earned")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("+\(points)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.12))
        )
    }
}

