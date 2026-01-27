import SwiftUI

struct PersonalizedComboCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background matching Home theme
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.darkGoldGradient, lineWidth: 2)
                    )
                    .shadow(color: Theme.goldShadow, radius: 16, x: 0, y: 8)
                    .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)

                // Subtle gold glow
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [Theme.lightGold.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .blur(radius: 1)
                    .allowsHitTesting(false)

                HStack(spacing: 16) {
                    // Dumpling Hero image (no gold circle background)
                    Image("newhero")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Personalized Combo")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.darkGoldGradient)

                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.lightGold)
                                .opacity(0.9)
                        }

                        Text("Dumpling Hero • Just for you")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.modernSecondary)

                        // Accent divider
                        Rectangle()
                            .fill(Theme.darkGoldGradient)
                            .frame(width: 64, height: 2)
                            .cornerRadius(1)
                            .opacity(0.8)
                    }

                    Spacer(minLength: 8)

                    // Chevron
                    ZStack {
                        Circle()
                            .fill(Theme.lightGold.opacity(0.18))
                            .frame(width: 30, height: 30)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.primaryGold)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    PersonalizedComboCard {
        DebugLogger.debug("Personalized combo tapped", category: "Combo")
    }
    .background(Color.black)
} 
