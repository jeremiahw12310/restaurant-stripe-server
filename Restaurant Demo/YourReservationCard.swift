//
//  YourReservationCard.swift
//  Restaurant Demo
//
//  Gold-themed card showing the user's active reservation with progress tracking.
//

import SwiftUI
import FirebaseAuth

// MARK: - Model

struct UserReservation: Identifiable {
    let id: String
    let customerName: String
    let date: String      // "YYYY-MM-DD"
    let time: String      // "h:mm a"
    let partySize: Int
    let status: String    // "pending" | "confirmed"
    let specialRequests: String?

    /// Friendly formatted date, e.g. "Saturday, Feb 14"
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return date }
        let display = DateFormatter()
        display.dateFormat = "EEEE, MMM d"
        return display.string(from: d)
    }

    /// True when the reservation date is today.
    var isToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return false }
        return Calendar.current.isDateInToday(d)
    }

    /// Number of days until the reservation (0 = today).
    var daysUntil: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: d)
        return max(0, Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0)
    }
}

// MARK: - ViewModel

final class UserReservationViewModel: ObservableObject {
    @Published var reservation: UserReservation?
    @Published var isLoading = false

    func load() {
        guard let user = Auth.auth().currentUser else {
            reservation = nil
            return
        }

        isLoading = true
        user.getIDToken { [weak self] token, err in
            guard let self = self else { return }
            if err != nil || token == nil {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            guard let url = URL(string: "\(Config.backendURL)/reservations/mine") else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, response, _ in
                DispatchQueue.main.async {
                    self.isLoading = false
                    guard let data = data,
                          let http = response as? HTTPURLResponse,
                          http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let items = json["reservations"] as? [[String: Any]],
                          let first = items.first else {
                        self.reservation = nil
                        return
                    }
                    self.reservation = UserReservation(
                        id: first["id"] as? String ?? "",
                        customerName: first["customerName"] as? String ?? "",
                        date: first["date"] as? String ?? "",
                        time: first["time"] as? String ?? "",
                        partySize: first["partySize"] as? Int ?? 1,
                        status: first["status"] as? String ?? "pending",
                        specialRequests: first["specialRequests"] as? String
                    )
                }
            }.resume()
        }
    }
}

// MARK: - Progress Step

private enum ReservationStep: Int, CaseIterable {
    case submitted = 0
    case confirmed = 1
    case enjoy = 2

    var label: String {
        switch self {
        case .submitted: return "Submitted"
        case .confirmed: return "Confirmed"
        case .enjoy:     return "Enjoy"
        }
    }

    var icon: String {
        switch self {
        case .submitted: return "paperplane.fill"
        case .confirmed: return "checkmark.seal.fill"
        case .enjoy:     return "fork.knife"
        }
    }
}

// MARK: - Card View

struct YourReservationCard: View {
    let reservation: UserReservation
    @Binding var animate: Bool

    /// Which step index is currently completed (inclusive).
    private var completedStep: Int {
        if reservation.status == "confirmed" && reservation.isToday {
            return 2
        } else if reservation.status == "confirmed" {
            return 1
        }
        return 0 // pending = only submitted
    }

    private var statusMessage: String {
        if reservation.status == "confirmed" && reservation.isToday {
            return "Today's the day! Your table is ready."
        } else if reservation.status == "confirmed" {
            let days = reservation.daysUntil
            if days == 1 {
                return "You're all set! See you tomorrow."
            }
            return "You're all set! See you \(reservation.formattedDate)."
        }
        return "Awaiting confirmation from the restaurant..."
    }

    private var statusIcon: String {
        if reservation.status == "confirmed" && reservation.isToday {
            return "party.popper.fill"
        } else if reservation.status == "confirmed" {
            return "checkmark.circle.fill"
        }
        return "clock.fill"
    }

    var body: some View {
        VStack(spacing: 20) {
            // MARK: Header
            HStack {
                Text("YOUR RESERVATION")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .tracking(1.2)
                Spacer()
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.darkGoldGradient)
            }

            // MARK: Progress Bar
            progressBar

            // MARK: Reservation Details
            detailsRow

            // MARK: Status Message
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(reservation.status == "confirmed" ? Theme.energyGreen : Theme.primaryGold)

                Text(statusMessage)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .lineLimit(2)

                Spacer()
            }
        }
        .padding(24)
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
        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.05), value: animate)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 0) {
            ForEach(ReservationStep.allCases, id: \.rawValue) { step in
                let isCompleted = step.rawValue <= completedStep
                let isActive = step.rawValue == completedStep

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isCompleted ? AnyShapeStyle(Theme.darkGoldGradient) : AnyShapeStyle(Color.gray.opacity(0.15)))
                            .frame(width: 36, height: 36)

                        Image(systemName: step.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isCompleted ? .white : Color.gray.opacity(0.4))
                    }
                    .overlay(
                        isActive ?
                        Circle()
                            .stroke(Theme.primaryGold.opacity(0.4), lineWidth: 3)
                            .frame(width: 44, height: 44)
                            .scaleEffect(animate ? 1.0 : 0.8)
                            .opacity(animate ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animate)
                        : nil
                    )

                    Text(step.label)
                        .font(.system(size: 11, weight: isCompleted ? .bold : .medium, design: .rounded))
                        .foregroundColor(isCompleted ? Theme.modernPrimary : Theme.modernSecondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)

                if step.rawValue < ReservationStep.allCases.count - 1 {
                    let lineCompleted = step.rawValue < completedStep
                    Rectangle()
                        .fill(lineCompleted ? Theme.primaryGold : Color.gray.opacity(0.15))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .offset(y: -10)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Details Row

    private var detailsRow: some View {
        HStack(spacing: 16) {
            // Date
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.darkGoldGradient)
                Text(reservation.formattedDate)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }

            // Divider
            Circle()
                .fill(Theme.primaryGold.opacity(0.5))
                .frame(width: 4, height: 4)

            // Time
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.darkGoldGradient)
                Text(reservation.time)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }

            // Divider
            Circle()
                .fill(Theme.primaryGold.opacity(0.5))
                .frame(width: 4, height: 4)

            // Party Size
            HStack(spacing: 5) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.darkGoldGradient)
                Text("\(reservation.partySize)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.primaryGold.opacity(0.06))
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.modernBackground.ignoresSafeArea()
        VStack(spacing: 20) {
            YourReservationCard(
                reservation: UserReservation(
                    id: "1",
                    customerName: "John",
                    date: "2026-02-14",
                    time: "6:30 PM",
                    partySize: 4,
                    status: "pending",
                    specialRequests: nil
                ),
                animate: .constant(true)
            )
            YourReservationCard(
                reservation: UserReservation(
                    id: "2",
                    customerName: "Jane",
                    date: "2026-02-14",
                    time: "7:00 PM",
                    partySize: 2,
                    status: "confirmed",
                    specialRequests: nil
                ),
                animate: .constant(true)
            )
        }
    }
}
