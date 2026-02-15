//
//  ReservationCard.swift
//  Restaurant Demo
//
//  Home card for reserving a table; matches Crowd Meter and Location card styling.
//

import SwiftUI

struct ReservationCard: View {
    @Binding var animate: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                HStack {
                    Text("RESERVE A TABLE")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .tracking(1.2)
                    Spacer()
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.darkGoldGradient)
                }

                // Seating status (no open/closed claim)
                HStack(spacing: 6) {
                    Text("Seating available")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Full-width premium CTA
                HStack(spacing: 8) {
                    Text("Reserve Now")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 26, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.darkGoldGradient)
                        .shadow(color: Theme.goldShadow, radius: 10, x: 0, y: 4)
                )
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Theme.darkGoldGradient, lineWidth: 3)
                    )
                    .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                    .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 20)
            .scaleEffect(animate ? 1.0 : 0.9)
            .opacity(animate ? 1.0 : 0.0)
            .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.1), value: animate)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Theme.modernBackground.ignoresSafeArea()
        ReservationCard(animate: .constant(true)) {}
    }
}
