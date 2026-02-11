//
//  ReservationSheetView.swift
//  Restaurant Demo
//
//  Form for customers to create a table reservation; submits to POST /reservations.
//

import SwiftUI
import FirebaseAuth

// MARK: - View Model

final class ReservationSheetViewModel: ObservableObject {
    @Published var date: Date = Calendar.current.startOfDay(for: Date())
    @Published var time: Date = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date()) ?? Date()
    @Published var partySize: Int = 2
    @Published var customerName: String = ""
    @Published var phone: String = ""
    @Published var email: String = ""
    @Published var specialRequests: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSuccess = false

    private let minPartySize = 1
    private let maxPartySize = 20

    var partySizeRange: ClosedRange<Int> { minPartySize...maxPartySize }

    func incrementPartySize() {
        if partySize < maxPartySize { partySize += 1 }
    }

    func decrementPartySize() {
        if partySize > minPartySize { partySize -= 1 }
    }

    /// Format time for API (e.g. "6:30 PM")
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Format date for API (YYYY-MM-DD)
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func submit() {
        errorMessage = nil
        let name = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneTrimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errorMessage = "Please enter your name."
            return
        }
        if phoneTrimmed.isEmpty {
            errorMessage = "Please enter your phone number."
            return
        }

        guard let user = Auth.auth().currentUser else {
            errorMessage = "Please sign in to make a reservation."
            return
        }

        let dateStr = Self.formatDate(date)
        let timeStr = Self.formatTime(time)
        let today = Calendar.current.startOfDay(for: Date())
        let selectedDay = Calendar.current.startOfDay(for: date)
        if selectedDay < today {
            errorMessage = "Please select today or a future date."
            return
        }

        isLoading = true
        user.getIDToken { [weak self] token, err in
            guard let self = self else { return }
            DispatchQueue.main.async { self.isLoading = false }
            if let err = err {
                DispatchQueue.main.async {
                    self.errorMessage = "Sign-in error. Please try again."
                }
                return
            }
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/reservations") else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid configuration."
                }
                return
            }

            var body: [String: Any] = [
                "customerName": name,
                "phone": phoneTrimmed,
                "date": dateStr,
                "time": timeStr,
                "partySize": partySize
            ]
            if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !specialRequests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["specialRequests"] = specialRequests.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                DispatchQueue.main.async { self.errorMessage = "Invalid form data." }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, response, _ in
                DispatchQueue.main.async {
                    guard let http = response as? HTTPURLResponse else {
                        self.errorMessage = "Request failed."
                        return
                    }
                    if http.statusCode == 201 {
                        self.showSuccess = true
                    } else {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let msg = json["error"] as? String {
                            self.errorMessage = msg
                        } else {
                            self.errorMessage = "Unable to create reservation. Please try again."
                        }
                    }
                }
            }.resume()
        }
    }
}

// MARK: - Sheet View

struct ReservationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var viewModel = ReservationSheetViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        dateTimeSection
                        partySizeSection
                        contactSection
                        specialRequestsSection
                        if let msg = viewModel.errorMessage {
                            Text(msg)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        submitButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Reserve a Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                viewModel.customerName = userVM.firstName
                viewModel.phone = userVM.phoneNumber
            }
            .alert("Reservation requested", isPresented: $viewModel.showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("We'll confirm your reservation soon. Our team may call you if needed.")
            }
        }
    }

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date & Time")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)

            DatePicker("Date", selection: $viewModel.date, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)

            DatePicker("Time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
        )
    }

    private var partySizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Party size")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)

            HStack {
                Button(action: { viewModel.decrementPartySize() }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.primaryGold)
                }
                .disabled(viewModel.partySize <= viewModel.partySizeRange.lowerBound)

                Text("\(viewModel.partySize)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
                    .frame(minWidth: 44)

                Button(action: { viewModel.incrementPartySize() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.primaryGold)
                }
                .disabled(viewModel.partySize >= viewModel.partySizeRange.upperBound)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
        )
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)

            TextField("Name", text: $viewModel.customerName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .autocapitalization(.words)

            TextField("Phone", text: $viewModel.phone)
                .textFieldStyle(.roundedBorder)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)

            TextField("Email (optional)", text: $viewModel.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
        )
    }

    private var specialRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Special requests (optional)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)

            TextField("Dietary needs, high chair, etc.", text: $viewModel.specialRequests, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
        )
    }

    private var submitButton: some View {
        Button(action: {
            viewModel.submit()
        }) {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Request reservation")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(viewModel.isLoading ? Theme.modernSecondary : Theme.energyOrange)
            )
            .foregroundColor(.white)
        }
        .disabled(viewModel.isLoading)
    }
}

#Preview {
    ReservationSheetView()
        .environmentObject(UserViewModel())
}
