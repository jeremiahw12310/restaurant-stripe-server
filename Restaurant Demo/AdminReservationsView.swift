//
//  AdminReservationsView.swift
//  Restaurant Demo
//
//  Admin screen to list reservations from GET /reservations and Confirm/Call/Cancel per row.
//  Redesigned for easier viewing and managing pending reservations.
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

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return date }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let display = DateFormatter()
        display.dateFormat = "EEEE, MMM d"
        return display.string(from: d)
    }

    /// Short date for list/notifications, e.g. "Feb 17", "Oct 3". Matches backend notification format.
    var formattedDateShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let d = formatter.date(from: date) else { return date }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        display.locale = Locale(identifier: "en_US_POSIX")
        return display.string(from: d)
    }

    var isToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return false }
        return Calendar.current.isDateInToday(d)
    }
}

// MARK: - View Model

final class AdminReservationsViewModel: ObservableObject {
    @Published var reservations: [AdminReservation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var nextCursor: String?
    @Published var hasMore = false
    @Published var selectedStatus: StatusFilter = .all
    @Published var actionError: String? // per-row error for confirm/cancel

    init(initialFilter: StatusFilter? = nil) {
        selectedStatus = initialFilter ?? .all
    }

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

    func deleteReservation(id: String, onDone: @escaping (Bool) -> Void) {
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
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { _, response, _ in
                DispatchQueue.main.async {
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        self.actionError = nil
                        self.loadReservations()
                        onDone(true)
                    } else {
                        self.actionError = "Failed to delete."
                        onDone(false)
                    }
                }
            }.resume()
        }
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
    @StateObject private var viewModel: AdminReservationsViewModel
    @State private var selectedReservation: AdminReservation?

    init(initialFilter: AdminReservationsViewModel.StatusFilter? = nil) {
        _viewModel = StateObject(wrappedValue: AdminReservationsViewModel(initialFilter: initialFilter))
    }
    @State private var successMessage: String?
    @State private var showSuccessOverlay = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    statusFilter
                    statsBar
                    if viewModel.errorMessage != nil {
                        errorBanner
                    }
                    if viewModel.isLoading && viewModel.reservations.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading reservations...")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                        }
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
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.loadReservations() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.darkGoldGradient)
                    }
                }
            }
            .onAppear {
                viewModel.loadReservations()
            }
            .sheet(item: $selectedReservation) { res in
                AdminReservationDetailSheet(
                    reservation: res,
                    viewModel: viewModel,
                    onDismiss: { selectedReservation = nil },
                    onSuccess: { msg in
                        successMessage = msg
                        showSuccessOverlay = true
                        selectedReservation = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.25)) { showSuccessOverlay = false }
                        }
                    }
                )
            }
            .overlay {
                if showSuccessOverlay, let msg = successMessage {
                    successToast(message: msg)
                }
            }
        }
    }

    private var statusFilter: some View {
        VStack(spacing: 0) {
            Picker("Status", selection: $viewModel.selectedStatus) {
                ForEach(AdminReservationsViewModel.StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .onChange(of: viewModel.selectedStatus) { _, newValue in
                viewModel.setFilter(newValue)
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: statusIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.darkGoldGradient)
                Text("\(viewModel.reservations.count) \(viewModel.selectedStatus.displayName.lowercased())")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }
            if !viewModel.reservations.isEmpty {
                let todayCount = viewModel.reservations.filter { $0.isToday }.count
                if todayCount > 0 {
                    Text("·")
                        .foregroundColor(Theme.modernSecondary)
                    Text("\(todayCount) today")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Theme.modernCardSecondary.opacity(0.6))
    }

    private var statusIconName: String {
        switch viewModel.selectedStatus {
        case .pending: return "clock.badge.questionmark"
        case .confirmed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .all: return "tray.full.fill"
        }
    }

    private var errorBanner: some View {
        Group {
            if let msg = viewModel.errorMessage {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.energyRed)
                    Text(msg)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    Spacer()
                    Button("Retry") { viewModel.loadReservations() }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.energyRed.opacity(0.1))
                .padding(.horizontal, 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 56))
                .foregroundStyle(Theme.darkGoldGradient.opacity(0.6))
            Text(emptyStateTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            Text(emptyStateSubtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        switch viewModel.selectedStatus {
        case .pending: return "clock.badge.questionmark"
        case .confirmed: return "checkmark.circle"
        case .cancelled: return "xmark.circle"
        case .all: return "tray"
        }
    }

    private var emptyStateTitle: String {
        switch viewModel.selectedStatus {
        case .pending: return "No pending reservations"
        case .confirmed: return "No confirmed reservations"
        case .cancelled: return "No cancelled reservations"
        case .all: return "No reservations"
        }
    }

    private var emptyStateSubtitle: String {
        viewModel.selectedStatus == .pending
            ? "New requests will appear here. Pull down to refresh."
            : "Reservations with status \"\(viewModel.selectedStatus.displayName)\" will appear here."
    }

    private var reservationsByDate: [(String, [AdminReservation])] {
        let grouped = Dictionary(grouping: viewModel.reservations) { $0.date }
        let sortedKeys = grouped.keys.sorted()
        return sortedKeys.map { (key: $0, list: grouped[$0] ?? []) }
    }

    /// When filter is All: sections by status (Pending, Confirmed, Cancelled), each sorted by date; empty sections omitted.
    private var reservationsByStatus: [(String, [AdminReservation])] {
        let pending = viewModel.reservations.filter { $0.status == "pending" }
            .sorted { ($0.date, $0.time) < ($1.date, $1.time) }
        let confirmed = viewModel.reservations.filter { $0.status == "confirmed" }
            .sorted { ($0.date, $0.time) < ($1.date, $1.time) }
        let cancelled = viewModel.reservations.filter { $0.status == "cancelled" }
            .sorted { ($0.date, $0.time) < ($1.date, $1.time) }
        var result: [(String, [AdminReservation])] = []
        if !pending.isEmpty { result.append(("Pending", pending)) }
        if !confirmed.isEmpty { result.append(("Confirmed", confirmed)) }
        if !cancelled.isEmpty { result.append(("Cancelled", cancelled)) }
        return result
    }

    private func sectionTitle(for dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let d = formatter.date(from: dateStr) else { return dateStr }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        display.locale = Locale(identifier: "en_US_POSIX")
        return display.string(from: d)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if viewModel.selectedStatus == .all {
                    ForEach(reservationsByStatus, id: \.0) { statusName, reservations in
                        Section {
                            ForEach(reservations) { res in
                                ReservationRowView(
                                    reservation: res,
                                    viewModel: viewModel,
                                    onTapRow: { selectedReservation = res },
                                    onSuccess: { msg in
                                        successMessage = msg
                                        showSuccessOverlay = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                            withAnimation(.easeOut(duration: 0.25)) { showSuccessOverlay = false }
                                        }
                                    }
                                )
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Text(statusName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.modernPrimary)
                                Text("(\(reservations.count))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.modernSecondary)
                            }
                            .padding(.top, statusName == reservationsByStatus.first?.0 ? 4 : 16)
                            .padding(.bottom, 4)
                        }
                    }
                } else {
                    ForEach(reservationsByDate, id: \.0) { dateStr, reservations in
                        Section {
                            ForEach(reservations) { res in
                                ReservationRowView(
                                    reservation: res,
                                    viewModel: viewModel,
                                    onTapRow: { selectedReservation = res },
                                    onSuccess: { msg in
                                        successMessage = msg
                                        showSuccessOverlay = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                            withAnimation(.easeOut(duration: 0.25)) { showSuccessOverlay = false }
                                        }
                                    }
                                )
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Text(sectionTitle(for: dateStr))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.modernPrimary)
                                if dateStr == reservationsByDate.first?.0 {
                                    Text("(\(reservations.count))")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Theme.modernSecondary)
                                }
                            }
                            .padding(.top, dateStr == reservationsByDate.first?.0 ? 4 : 16)
                            .padding(.bottom, 4)
                        }
                    }
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

    private func successToast(message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Theme.energyGreen)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            )
            .padding(.top, 8)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeOut(duration: 0.25), value: showSuccessOverlay)
    }
}

// MARK: - Row

struct ReservationRowView: View {
    let reservation: AdminReservation
    @ObservedObject var viewModel: AdminReservationsViewModel
    var onTapRow: (() -> Void)?
    var onSuccess: ((String) -> Void)?
    @State private var isConfirming = false
    @State private var isCancelling = false
    @State private var showConfirmAlert = false
    @State private var showCancelAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: name, date/time, party, status (tap opens detail)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reservation.customerName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    Text("\(reservation.formattedDateShort) at \(reservation.time)")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    HStack(spacing: 8) {
                        Label("Party of \(reservation.partySize)", systemImage: "person.2.fill")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                        if let req = reservation.specialRequests, !req.isEmpty {
                            Text("·")
                            Text(req)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.modernSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 12)
                statusBadge
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.modernSecondary.opacity(0.7))
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapRow?() }

            Divider()
                .background(Theme.modernCardSecondary)

            // Actions: Confirm / Cancel (if pending), Call
            HStack(spacing: 10) {
                if reservation.status == "pending" {
                    Button(action: { showConfirmAlert = true }) {
                        HStack(spacing: 6) {
                            if isConfirming {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Confirm")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.energyGreen))
                    }
                    .disabled(isConfirming || isCancelling)

                    Button(action: { showCancelAlert = true }) {
                        HStack(spacing: 6) {
                            if isCancelling {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(.white)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Cancel")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.energyOrange))
                    }
                    .disabled(isConfirming || isCancelling)
                }

                if !reservation.phone.isEmpty {
                    let digitsOnly = reservation.phone.filter { $0.isNumber }
                    if !digitsOnly.isEmpty, let url = URL(string: "tel:\(digitsOnly)") {
                        Button(action: { UIApplication.shared.open(url) }) {
                            HStack(spacing: 5) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 12))
                                Text("Call")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.energyBlue))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(reservation.status == "pending" ? Theme.primaryGold.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
        )
        .alert("Confirm Reservation", isPresented: $showConfirmAlert) {
            Button("Confirm", role: .none) {
                isConfirming = true
                viewModel.confirmReservation(id: reservation.id) { success in
                    isConfirming = false
                    if success {
                        onSuccess?("\(reservation.customerName) confirmed — customer notified")
                    }
                }
            }
            Button("Go Back", role: .cancel) {}
        } message: {
            Text("Confirm \(reservation.customerName)'s reservation for \(reservation.formattedDateShort) at \(reservation.time)? The customer will be notified.")
        }
        .alert("Cancel Reservation", isPresented: $showCancelAlert) {
            Button("Cancel Reservation", role: .destructive) {
                isCancelling = true
                viewModel.cancelReservation(id: reservation.id) { success in
                    isCancelling = false
                    if success {
                        onSuccess?("\(reservation.customerName)'s reservation cancelled — customer notified")
                    }
                }
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("Cancel \(reservation.customerName)'s reservation for \(reservation.formattedDateShort) at \(reservation.time)? The customer will be notified by push notification.")
        }
    }

    private var statusBadge: some View {
        Text(reservation.status.capitalized)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(statusColor.opacity(0.2)))
    }

    private var statusColor: Color {
        switch reservation.status {
        case "confirmed": return Theme.energyGreen
        case "cancelled": return Theme.energyRed
        default: return Theme.energyOrange
        }
    }
}

// MARK: - Detail Sheet (full info + actions)

struct AdminReservationDetailSheet: View {
    let reservation: AdminReservation
    @ObservedObject var viewModel: AdminReservationsViewModel
    let onDismiss: () -> Void
    let onSuccess: (String) -> Void
    @Environment(\.dismiss) private var envDismiss
    @State private var isConfirming = false
    @State private var isCancelling = false
    @State private var showConfirmAlert = false
    @State private var showCancelAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        heroCard
                        detailsCard
                        actionsSection
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Reservation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        envDismiss()
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                }
            }
            .alert("Confirm Reservation", isPresented: $showConfirmAlert) {
                Button("Confirm", role: .none) {
                    isConfirming = true
                    viewModel.confirmReservation(id: reservation.id) { success in
                        isConfirming = false
                        if success {
                            onSuccess("\(reservation.customerName) confirmed — customer notified")
                            envDismiss()
                        }
                    }
                }
                Button("Go Back", role: .cancel) {}
            } message: {
                Text("Confirm this reservation? The customer will be notified.")
            }
            .alert("Cancel Reservation", isPresented: $showCancelAlert) {
                Button("Cancel Reservation", role: .destructive) {
                    isCancelling = true
                    viewModel.cancelReservation(id: reservation.id) { success in
                        isCancelling = false
                        if success {
                            onSuccess("\(reservation.customerName)'s reservation cancelled — customer notified")
                            envDismiss()
                        }
                    }
                }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("Cancel this reservation? The customer will be notified by push notification.")
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.formattedDateShort)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                    Text(reservation.time)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }
                Spacer()
                statusBadge
            }
            Text(reservation.customerName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.darkGoldGradient)
                Text("Party of \(reservation.partySize)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.darkGoldGradient.opacity(0.4), lineWidth: 2)
                )
                .shadow(color: Theme.goldShadow.opacity(0.4), radius: 12, x: 0, y: 6)
        )
    }

    private var statusBadge: some View {
        Text(reservation.status.capitalized)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(detailStatusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(detailStatusColor.opacity(0.2)))
    }

    private var detailStatusColor: Color {
        switch reservation.status {
        case "confirmed": return Theme.energyGreen
        case "cancelled": return Theme.energyRed
        default: return Theme.energyOrange
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Contact & notes")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            if !reservation.phone.isEmpty {
                detailRow(icon: "phone.fill", title: "Phone", value: reservation.phone, tappable: true) {
                    if let url = URL(string: "tel:\(reservation.phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reservation.phone)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            if let email = reservation.email, !email.isEmpty {
                detailRow(icon: "envelope.fill", title: "Email", value: email, tappable: true) {
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            if let req = reservation.specialRequests, !req.isEmpty {
                detailRow(icon: "text.quote", title: "Special requests", value: req, tappable: false, action: nil)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCard)
                .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
        )
    }

    private func detailRow(icon: String, title: String, value: String, tappable: Bool, action: (() -> Void)?) -> some View {
        Group {
            if tappable, let action = action {
                Button(action: action) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.darkGoldGradient)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                            Text(value)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.modernSecondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                        Text(value)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if reservation.status == "pending" {
                Button(action: { showConfirmAlert = true }) {
                    HStack(spacing: 10) {
                        if isConfirming {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Confirm reservation")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.energyGreen))
                }
                .disabled(isConfirming || isCancelling)
            }

            if reservation.status == "pending" {
                Button(action: { showCancelAlert = true }) {
                    HStack(spacing: 10) {
                        if isCancelling {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(.white)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Cancel reservation")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.energyOrange))
                }
                .disabled(isConfirming || isCancelling)
            }

            if !reservation.phone.isEmpty,
               let url = URL(string: "tel:\(reservation.phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reservation.phone)") {
                Button(action: { UIApplication.shared.open(url) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 18))
                        Text("Call customer")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.energyBlue))
                }
            }
        }
    }
}

#Preview {
    AdminReservationsView()
}
