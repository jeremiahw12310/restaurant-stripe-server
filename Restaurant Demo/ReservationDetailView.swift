//
//  ReservationDetailView.swift
//  Restaurant Demo
//
//  Full-page sheet showing reservation details and options (cancel, call).
//

import SwiftUI
import FirebaseAuth
import MapKit

struct ReservationDetailView: View {
    let reservation: UserReservation
    let onDismiss: () -> Void
    let onCancelSuccess: () -> Void

    @State private var showCancelAlert = false
    @State private var isCancelling = false
    @State private var errorMessage: String?

    private var completedStep: Int {
        if reservation.status == "confirmed" && reservation.isToday { return 2 }
        if reservation.status == "confirmed" { return 1 }
        return 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        heroBlock
                        progressSection
                        countdownIfNeeded
                        detailsSection
                        actionsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Your Reservation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                }
            }
            .alert("Cancel Reservation", isPresented: $showCancelAlert) {
                Button("Cancel Reservation", role: .destructive) {
                    cancelReservation()
                }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("Cancel your reservation for \(reservation.formattedDateShort) at \(reservation.time)? You can make a new one anytime.")
            }
        }
    }

    // MARK: - Hero Block

    private var heroBlock: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.formattedDateShort)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                    Text(reservation.time)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }
                Spacer()
                statusBadge
            }
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.darkGoldGradient)
                Text("Party of \(reservation.partySize)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                Spacer()
            }
        }
        .padding(24)
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
    }

    private var statusBadge: some View {
        Text(reservation.status.capitalized)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(statusBadgeColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusBadgeColor.opacity(0.2))
            )
    }

    private var statusBadgeColor: Color {
        reservation.status == "confirmed" ? Theme.energyGreen : Theme.primaryGold
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
            HStack(spacing: 0) {
                ForEach([("Submitted", "paperplane.fill"), ("Confirmed", "checkmark.seal.fill"), ("Enjoy", "fork.knife")], id: \.0) { label, icon in
                    let index = ["Submitted", "Confirmed", "Enjoy"].firstIndex(of: label) ?? 0
                    let isCompleted = index <= completedStep
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(isCompleted ? AnyShapeStyle(Theme.darkGoldGradient) : AnyShapeStyle(Color.gray.opacity(0.15)))
                                .frame(width: 32, height: 32)
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isCompleted ? .white : Color.gray.opacity(0.4))
                        }
                        Text(label)
                            .font(.system(size: 10, weight: isCompleted ? .bold : .medium, design: .rounded))
                            .foregroundColor(isCompleted ? Theme.modernPrimary : Theme.modernSecondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    if index < 2 {
                        Rectangle()
                            .fill(index < completedStep ? Theme.primaryGold : Color.gray.opacity(0.15))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .offset(y: -8)
                    }
                }
            }
        }
    }

    // MARK: - Countdown (day of)

    @ViewBuilder
    private var countdownIfNeeded: some View {
        if reservation.isToday,
           let target = reservation.reservationDateTime,
           target > Date() {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = context.date
                if target > now {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: now, to: target)
                    let h = components.hour ?? 0
                    let m = components.minute ?? 0
                    let text = h > 0 ? "In \(h)h \(m)m" : (m > 0 ? "In \(m) minute\(m == 1 ? "" : "s")" : "Coming up soon")
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.darkGoldGradient)
                        Text(text)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.primaryGold.opacity(0.12))
                    )
                }
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
            VStack(spacing: 0) {
                detailRow(icon: "calendar", title: "Date", value: reservation.formattedDateShort)
                detailRow(icon: "clock", title: "Time", value: reservation.time)
                detailRow(icon: "person.2.fill", title: "Party size", value: "\(reservation.partySize)")
                if let notes = reservation.specialRequests, !notes.isEmpty {
                    detailRow(icon: "note.text", title: "Notes", value: notes)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.modernCard)
                    .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
            )
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.darkGoldGradient)
                .frame(width: 24, alignment: .center)
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.energyRed)
                    .multilineTextAlignment(.center)
            }

            if let url = URL(string: "tel:\(Config.restaurantPhoneNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Config.restaurantPhoneNumber)"),
               UIApplication.shared.canOpenURL(url) {
                Button(action: { UIApplication.shared.open(url) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                        Text("Call restaurant")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.energyBlue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCancelling)
            }

            Button(action: openDirections) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                    Text("Directions")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.energyBlue)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)

            Button(action: { showCancelAlert = true }) {
                HStack(spacing: 8) {
                    if isCancelling {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel reservation")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.energyRed)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)
        }
    }

    // MARK: - Directions

    private func openDirections() {
        let coordinate = CLLocationCoordinate2D(
            latitude: Config.restaurantLatitude,
            longitude: Config.restaurantLongitude
        )
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "Dumpling House"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Cancel API

    private func cancelReservation() {
        errorMessage = nil
        isCancelling = true
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Please sign in."
            isCancelling = false
            return
        }
        user.getIDToken { token, err in
            if err != nil {
                DispatchQueue.main.async {
                    errorMessage = "Sign-in error. Try again."
                    isCancelling = false
                }
                return
            }
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/reservations/mine/\(reservation.id)") else {
                DispatchQueue.main.async {
                    errorMessage = "Invalid configuration."
                    isCancelling = false
                }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "cancelled"])
            URLSession.shared.dataTask(with: request) { _, response, _ in
                DispatchQueue.main.async {
                    isCancelling = false
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        onCancelSuccess()
                    } else {
                        errorMessage = "Could not cancel. Please try again or contact the restaurant."
                    }
                }
            }.resume()
        }
    }
}

#Preview {
    ReservationDetailView(
        reservation: UserReservation(
            id: "1",
            customerName: "Jane",
            date: "2026-02-14",
            time: "6:30 PM",
            partySize: 4,
            status: "confirmed",
            specialRequests: "Window seat if possible",
            phone: "555-123-4567"
        ),
        onDismiss: {},
        onCancelSuccess: {}
    )
}
