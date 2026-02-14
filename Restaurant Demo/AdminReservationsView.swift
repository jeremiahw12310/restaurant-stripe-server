//
//  AdminReservationsView.swift
//  Restaurant Demo
//
//  Admin screen to list reservations from GET /reservations and Confirm/Call/Cancel per row.
//

import SwiftUI
import FirebaseAuth

// MARK: - Model (matches backend response)

struct AdminReservation: Identifiable {
    let id: String
    let userId: String
    let customerName: String
    let phone: String
    let email: String?
    let date: String
    let time: String
    let partySize: Int
    let specialRequests: String?
    let status: String
    let createdAt: Date?
    let updatedAt: Date?
    let confirmedAt: Date?
    let confirmedBy: String?

    static func from(_ json: [String: Any]) -> AdminReservation? {
        guard let id = json["id"] as? String,
              let customerName = json["customerName"] as? String,
              let phone = json["phone"] as? String,
              let date = json["date"] as? String,
              let time = json["time"] as? String,
              let partySize = json["partySize"] as? Int,
              let status = json["status"] as? String else { return nil }
        return AdminReservation(
            id: id,
            userId: json["userId"] as? String ?? "",
            customerName: customerName,
            phone: phone,
            email: json["email"] as? String,
            date: date,
            time: time,
            partySize: partySize,
            specialRequests: json["specialRequests"] as? String,
            status: status,
            createdAt: nil,
            updatedAt: nil,
            confirmedAt: nil,
            confirmedBy: json["confirmedBy"] as? String
        )
    }
}

// MARK: - View Model

final class AdminReservationsViewModel: ObservableObject {
    @Published var reservations: [AdminReservation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var nextCursor: String?
    @Published var hasMore = false
    @Published var selectedStatus: StatusFilter = .pending
    @Published var actionError: String? // per-row error for confirm/cancel

    enum StatusFilter: String, CaseIterable {
        case pending
        case confirmed
        case cancelled
        case all

        var queryValue: String? {
            switch self {
            case .pending: return "pending"
            case .confirmed: return "confirmed"
            case .cancelled: return "cancelled"
            case .all: return nil
            }
        }

        var displayName: String { rawValue.capitalized }
    }

    func loadReservations() {
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        reservations = []
        fetchPage(reset: true)
    }

    func loadMoreIfNeeded() {
        guard hasMore, !isLoading, let cursor = nextCursor else { return }
        fetchPage(reset: false, cursor: cursor)
    }

    private func fetchPage(reset: Bool, cursor: String? = nil) {
        guard let user = Auth.auth().currentUser else {
            isLoading = false
            errorMessage = "Please sign in."
            return
        }
        if reset { isLoading = true }
        user.getIDToken { [weak self] token, err in
            guard let self = self else { return }
            if err != nil {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Sign-in error. Try again."
                }
                return
            }
            guard let token = token else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Missing auth token."
                }
                return
            }
            var urlString = "\(Config.backendURL)/reservations?limit=50"
            if let status = self.selectedStatus.queryValue {
                urlString += "&status=\(status)"
            }
            if let c = cursor {
                urlString += "&cursor=\(c.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c)"
            }
            guard let url = URL(string: urlString) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Invalid URL."
                }
                return
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { data, response, _ in
                DispatchQueue.main.async {
                    self.isLoading = false
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let list = json["reservations"] as? [[String: Any]] else {
                        self.errorMessage = "Failed to load reservations."
                        return
                    }
                    let newItems = list.compactMap { AdminReservation.from($0) }
                    if reset {
                        self.reservations = newItems
                    } else {
                        self.reservations.append(contentsOf: newItems)
                    }
                    self.nextCursor = json["nextCursor"] as? String
                    self.hasMore = (json["hasMore"] as? Bool) ?? false
                }
            }.resume()
        }
    }

    func setFilter(_ filter: StatusFilter) {
        selectedStatus = filter
        loadReservations()
    }

    func confirmReservation(id: String, onDone: @escaping (Bool) -> Void) {
        updateStatus(id: id, status: "confirmed", onDone: onDone)
    }

    func cancelReservation(id: String, onDone: @escaping (Bool) -> Void) {
        updateStatus(id: id, status: "cancelled", onDone: onDone)
    }

    private func updateStatus(id: String, status: String, onDone: @escaping (Bool) -> Void) {
        guard Auth.auth().currentUser != nil else {
            actionError = "Please sign in."
            onDone(false)
            return
        }
        Auth.auth().currentUser?.getIDToken { token, err in
            if err != nil {
                DispatchQueue.main.async {
                    self.actionError = "Sign-in error."
                    onDone(false)
                }
                return
            }
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/reservations/\(id)") else {
                DispatchQueue.main.async {
                    self.actionError = "Invalid configuration."
                    onDone(false)
                }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["status": status])
            URLSession.shared.dataTask(with: request) { _, response, _ in
                DispatchQueue.main.async {
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        self.actionError = nil
                        self.loadReservations()
                        onDone(true)
                    } else {
                        self.actionError = "Failed to update."
                        onDone(false)
                    }
                }
            }.resume()
        }
    }
}

// MARK: - View

struct AdminReservationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminReservationsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    statusFilter
                    if viewModel.errorMessage != nil {
                        errorBanner
                    }
                    if viewModel.isLoading && viewModel.reservations.isEmpty {
                        Spacer()
                        ProgressView("Loading reservations...")
                        Spacer()
                    } else if viewModel.reservations.isEmpty {
                        emptyState
                    } else {
                        listContent
                    }
                }
            }
            .navigationTitle("Reservations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.loadReservations() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                viewModel.loadReservations()
            }
        }
    }

    private var statusFilter: some View {
        Picker("Status", selection: $viewModel.selectedStatus) {
            ForEach(AdminReservationsViewModel.StatusFilter.allCases, id: \.self) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onChange(of: viewModel.selectedStatus) { _, newValue in
            viewModel.setFilter(newValue)
        }
    }

    private var errorBanner: some View {
        Group {
            if let msg = viewModel.errorMessage {
                HStack {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Retry") { viewModel.loadReservations() }
                        .font(.subheadline)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No reservations")
                .font(.headline)
            Text(viewModel.selectedStatus == .pending ? "Pending reservations will appear here." : "No \(viewModel.selectedStatus.rawValue) reservations.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.reservations) { res in
                    ReservationRowView(
                        reservation: res,
                        viewModel: viewModel
                    )
                }
                if viewModel.hasMore && !viewModel.isLoading {
                    ProgressView()
                        .padding()
                        .onAppear { viewModel.loadMoreIfNeeded() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable {
            viewModel.loadReservations()
        }
    }
}

// MARK: - Row

struct ReservationRowView: View {
    let reservation: AdminReservation
    @ObservedObject var viewModel: AdminReservationsViewModel
    @State private var isConfirming = false
    @State private var isCancelling = false
    @State private var showConfirmAlert = false
    @State private var showCancelAlert = false
    @State private var showSuccessBanner = false
    @State private var successMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Success banner
            if showSuccessBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                    Text(successMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.customerName)
                        .font(.headline)
                    Text("\(reservation.date) at \(reservation.time) · Party of \(reservation.partySize)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let req = reservation.specialRequests, !req.isEmpty {
                        Text(req)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 10) {
                if reservation.status == "pending" {
                    Button(action: {
                        showConfirmAlert = true
                    }) {
                        HStack(spacing: 4) {
                            if isConfirming {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Confirm")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green))
                    }
                    .disabled(isConfirming || isCancelling)

                    Button(action: {
                        showCancelAlert = true
                    }) {
                        HStack(spacing: 4) {
                            if isCancelling {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange))
                    }
                    .disabled(isConfirming || isCancelling)
                }

                if !reservation.phone.isEmpty,
                   let url = URL(string: "tel:\(reservation.phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reservation.phone)") {
                    Button(action: { UIApplication.shared.open(url) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                            Text("Call")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .alert("Confirm Reservation", isPresented: $showConfirmAlert) {
            Button("Confirm", role: .none) {
                isConfirming = true
                viewModel.confirmReservation(id: reservation.id) { success in
                    isConfirming = false
                    if success {
                        successMessage = "\(reservation.customerName) confirmed -- customer has been notified"
                        withAnimation { showSuccessBanner = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showSuccessBanner = false }
                        }
                    }
                }
            }
            Button("Go Back", role: .cancel) {}
        } message: {
            Text("Confirm \(reservation.customerName)'s reservation for \(reservation.date) at \(reservation.time)? The customer will be notified.")
        }
        .alert("Cancel Reservation", isPresented: $showCancelAlert) {
            Button("Cancel Reservation", role: .destructive) {
                isCancelling = true
                viewModel.cancelReservation(id: reservation.id) { success in
                    isCancelling = false
                    if success {
                        successMessage = "\(reservation.customerName)'s reservation cancelled -- customer has been notified"
                        withAnimation { showSuccessBanner = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showSuccessBanner = false }
                        }
                    }
                }
            }
            Button("Go Back", role: .cancel) {}
        } message: {
            Text("Cancel \(reservation.customerName)'s reservation for \(reservation.date) at \(reservation.time)? The customer will be notified.")
        }
    }

    private var statusBadge: some View {
        Text(reservation.status.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(statusColor.opacity(0.2)))
    }

    private var statusColor: Color {
        switch reservation.status {
        case "confirmed": return .green
        case "cancelled": return .red
        default: return .orange
        }
    }
}

#Preview {
    AdminReservationsView()
}
