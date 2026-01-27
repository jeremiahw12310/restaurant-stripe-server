//
//  AdminNotificationsView.swift
//  Restaurant Demo
//
//  Admin interface for composing and sending push notifications to customers.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AdminNotificationsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AdminNotificationsViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.95, green: 0.95, blue: 0.97)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Card
                        headerCard
                        
                        // Compose Section
                        composeSection
                        
                        // Target Selection
                        targetSelectionSection
                        
                        // Promotional Toggle
                        promotionalToggleSection
                        
                        // User Selection (if individual)
                        if viewModel.targetType == .individual {
                            userSelectionSection
                        }
                        
                        // Preview Section
                        if viewModel.canShowPreview {
                            previewSection
                        }
                        
                        // Send Button
                        sendButton
                        
                        // Sent History
                        if !viewModel.sentNotifications.isEmpty {
                            historySection
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Notification Sent", isPresented: $viewModel.showSuccessAlert) {
                Button("OK") {
                    viewModel.clearForm()
                }
            } message: {
                Text(viewModel.successMessage)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .onAppear {
                viewModel.loadSentNotifications()
            }
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send Notifications")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    Text("Reach all or individual customers")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Compose Section
    
    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compose Message")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            // Title Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                TextField("Enter notification title", text: $viewModel.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 16))
            }
            
            // Body Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Message")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                TextEditor(text: $viewModel.body)
                    .frame(minHeight: 100, maxHeight: 150)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .font(.system(size: 16))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Promotional Toggle Section
    
    private var promotionalToggleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "megaphone.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notification Type")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    Text(viewModel.isPromotional ? "Promotional - Only sent to opted-in users" : "Transactional - Sent to all users")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Toggle("", isOn: $viewModel.isPromotional)
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
            }
            
            if viewModel.isPromotional {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Promotional notifications require user opt-in. Only users who have enabled promotional notifications in their settings will receive this.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.1))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Target Selection
    
    private var targetSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipients")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            HStack(spacing: 12) {
                // All Customers Button
                Button {
                    viewModel.targetType = .all
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 16))
                        Text("All Customers")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(viewModel.targetType == .all ? .white : .blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.targetType == .all ? Color.blue : Color.blue.opacity(0.1))
                    )
                }
                
                // Individual Button
                Button {
                    viewModel.targetType = .individual
                    if viewModel.users.isEmpty {
                        viewModel.loadUsers()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                        Text("Individual")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(viewModel.targetType == .individual ? .white : .purple)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.targetType == .individual ? Color.purple : Color.purple.opacity(0.1))
                    )
                }
                
                Spacer()
            }
            
            if viewModel.targetType == .all {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        if viewModel.isPromotional {
                            Text("This will send to all customers with push notifications enabled who have opted in to promotional notifications")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        } else {
                            Text("This will send to all customers with push notifications enabled")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Include Admins Toggle
                    Toggle(isOn: $viewModel.includeAdmins) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .foregroundColor(.orange)
                            Text("Include Admins")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - User Selection Section
    
    private var userSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Select Users")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                
                Spacer()
                
                if !viewModel.selectedUserIds.isEmpty {
                    Text("\(viewModel.selectedUserIds.count) selected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.purple)
                }
            }
            
            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search by name or phone", text: $viewModel.searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.scheduleReloadUsers()
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
            )
            
            if viewModel.isLoadingUsers {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
            } else if let error = viewModel.loadUsersError {
                // Error State
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundColor(.orange)
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        viewModel.loadUsers()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                    }
                }
                .padding()
            } else {
                // User List
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredUsers, id: \.id) { user in
                            UserSelectionRow(
                                user: user,
                                isSelected: viewModel.selectedUserIds.contains(user.id),
                                onToggle: {
                                    viewModel.toggleUserSelection(user.id)
                                }
                            )
                            .onAppear {
                                viewModel.loadMoreUsersIfNeeded(currentUserId: user.id)
                            }
                        }
                        
                        if viewModel.isLoadingMoreUsers {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 8)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            // Notification Preview
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // App Icon placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "fork.knife")
                                .foregroundColor(.white)
                                .font(.system(size: 18))
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("DUMPLING HOUSE")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Text("now")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Text(viewModel.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        
                        Text(viewModel.body)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Send Button
    
    private var sendButton: some View {
        Button {
            viewModel.sendNotification()
        } label: {
            HStack(spacing: 12) {
                if viewModel.isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                }
                
                Text(viewModel.isSending ? "Sending..." : "Send Notification")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        viewModel.canSend
                            ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: viewModel.canSend ? .orange.opacity(0.4) : .clear, radius: 12, x: 0, y: 6)
            )
        }
        .disabled(!viewModel.canSend || viewModel.isSending)
    }
    
    // MARK: - History Section
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Notifications")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            ForEach(viewModel.sentNotifications.prefix(5), id: \.id) { notification in
                SentNotificationRow(notification: notification)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - User Selection Row

struct UserSelectionRow: View {
    let user: NotificationUser
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.purple : Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .bold))
                    } else {
                        Text(user.avatarEmoji)
                            .font(.system(size: 18))
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.firstName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                        
                        if user.isAdmin {
                            HStack(spacing: 3) {
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .font(.system(size: 10))
                                Text("Admin")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                        }
                    }
                    
                    if !user.phone.isEmpty {
                        Text(user.phone)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if user.hasFcmToken {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                    } else {
                        Image(systemName: "bell.slash")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.purple.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Sent Notification Row

struct SentNotificationRow: View {
    let notification: SentNotification
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(notification.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Spacer()
                
                Text(notification.sentAt, style: .relative)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Text(notification.body)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(2)
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: notification.targetType == "all" ? "person.3.fill" : "person.fill")
                        .font(.system(size: 11))
                    Text(notification.targetType == "all" ? "All" : "\(notification.targetUserIds?.count ?? 0) users")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.blue)
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("\(notification.successCount)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.green)
                
                if notification.failureCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text("\(notification.failureCount)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - View Model

class AdminNotificationsViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var body: String = ""
    @Published var targetType: TargetType = .all
    @Published var includeAdmins: Bool = false
    @Published var isPromotional: Bool = true // Default to true (promotional) for compliance
    @Published var selectedUserIds: Set<String> = []
    @Published var searchQuery: String = ""
    
    @Published var users: [NotificationUser] = []
    @Published var isLoadingUsers: Bool = false
    @Published var loadUsersError: String?
    @Published var hasMoreUsers: Bool = true
    @Published var isLoadingMoreUsers: Bool = false
    @Published var isSending: Bool = false
    
    @Published var showSuccessAlert: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var successMessage: String = ""
    @Published var errorMessage: String = ""
    
    @Published var sentNotifications: [SentNotification] = []
    
    private let db = Firestore.firestore()
    private var nextUsersCursor: String?
    private var currentUsersRequestId: UUID?
    private var searchDebounceWorkItem: DispatchWorkItem?
    
    enum TargetType {
        case all
        case individual
    }
    
    var filteredUsers: [NotificationUser] {
        // Users are already server-filtered when searching.
        return users
    }
    
    var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (targetType == .all || !selectedUserIds.isEmpty)
    }
    
    var canShowPreview: Bool {
        !title.isEmpty || !body.isEmpty
    }
    
    // MARK: - Load Users
    
    func loadUsers() {
        fetchUsersPage(isReset: true)
    }
    
    func scheduleReloadUsers() {
        searchDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fetchUsersPage(isReset: true)
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    
    func loadMoreUsersIfNeeded(currentUserId: String) {
        guard hasMoreUsers, !isLoadingUsers, !isLoadingMoreUsers else { return }
        guard let lastId = users.last?.id, lastId == currentUserId else { return }
        fetchUsersPage(isReset: false)
    }
    
    private func fetchUsersPage(isReset: Bool) {
        if isReset {
            isLoadingUsers = true
            isLoadingMoreUsers = false
            loadUsersError = nil
            hasMoreUsers = true
            nextUsersCursor = nil
            users.removeAll()
        } else {
            isLoadingMoreUsers = true
        }
        
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let currentUser = Auth.auth().currentUser else {
            isLoadingUsers = false
            isLoadingMoreUsers = false
            loadUsersError = "Not authenticated. Please log in again."
            return
        }
        
        let requestId = UUID()
        currentUsersRequestId = requestId
        
        // Timeout safeguard
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, self.currentUsersRequestId == requestId else { return }
            DispatchQueue.main.async {
                self.isLoadingUsers = false
                self.isLoadingMoreUsers = false
                self.loadUsersError = "Loading timed out. Please check your connection and try again."
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem)
        
        currentUser.getIDToken { [weak self] token, error in
            guard let self else { return }
            guard self.currentUsersRequestId == requestId else { return }
            
            guard let token else {
                timeoutWorkItem.cancel()
                DispatchQueue.main.async {
                    self.isLoadingUsers = false
                    self.isLoadingMoreUsers = false
                    self.loadUsersError = "Failed to get authentication token: \(error?.localizedDescription ?? "unknown")"
                }
                return
            }
            
            var components = URLComponents(string: "\(Config.backendURL)/admin/users")
            var items: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "50")
            ]
            
            if let cursor = self.nextUsersCursor, !cursor.isEmpty, !isReset {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
            
            if !q.isEmpty {
                items.append(URLQueryItem(name: "q", value: q))
            }
            
            components?.queryItems = items
            
            guard let url = components?.url else {
                timeoutWorkItem.cancel()
                DispatchQueue.main.async {
                    self.isLoadingUsers = false
                    self.isLoadingMoreUsers = false
                    self.loadUsersError = "Invalid server URL"
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data, response, networkError in
                timeoutWorkItem.cancel()
                
                DispatchQueue.main.async {
                    guard self.currentUsersRequestId == requestId else { return }
                    
                    self.isLoadingUsers = false
                    self.isLoadingMoreUsers = false
                    
                    if let networkError {
                        self.loadUsersError = "Network error: \(networkError.localizedDescription)"
                        return
                    }
                    
                    guard let http = response as? HTTPURLResponse else {
                        self.loadUsersError = "Invalid response"
                        return
                    }
                    
                    guard let data else {
                        self.loadUsersError = "No data returned"
                        return
                    }
                    
                    guard http.statusCode == 200 else {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let msg = json["error"] as? String {
                            self.loadUsersError = msg
                        } else {
                            self.loadUsersError = "Failed to load users (status \(http.statusCode))"
                        }
                        return
                    }
                    
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        self.loadUsersError = "Failed to parse server response"
                        return
                    }
                    
                    let hasMore = json["hasMore"] as? Bool ?? false
                    let nextCursor = json["nextCursor"] as? String
                    let rawUsers = json["users"] as? [[String: Any]] ?? []
                    
                    let parsed: [NotificationUser] = rawUsers.compactMap { u in
                        // Exclude employees from customer targeting (but allow admins)
                        if (u["isEmployee"] as? Bool) == true { return nil }
                        
                        let id = u["id"] as? String ?? ""
                        if id.isEmpty { return nil }
                        
                        let firstName = u["firstName"] as? String ?? "Unknown"
                        let phone = u["phone"] as? String ?? ""
                        let avatarEmoji = u["avatarEmoji"] as? String ?? "👤"
                        let hasFcmToken = u["hasFcmToken"] as? Bool ?? false
                        let isAdmin = (u["isAdmin"] as? Bool) == true
                        
                        return NotificationUser(
                            id: id,
                            firstName: firstName,
                            phone: phone,
                            avatarEmoji: avatarEmoji,
                            hasFcmToken: hasFcmToken,
                            isAdmin: isAdmin
                        )
                    }
                    .sorted { $0.firstName < $1.firstName }
                    
                    if isReset {
                        self.users = parsed
                    } else {
                        self.users.append(contentsOf: parsed)
                    }
                    
                    self.hasMoreUsers = hasMore
                    self.nextUsersCursor = nextCursor
                }
            }.resume()
        }
    }
    
    // MARK: - Toggle User Selection
    
    func toggleUserSelection(_ userId: String) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }
    
    // MARK: - Send Notification
    
    func sendNotification() {
        guard canSend else { return }
        
        isSending = true
        
        Auth.auth().currentUser?.getIDToken { [weak self] idToken, error in
            guard let self = self, let idToken = idToken else {
                DispatchQueue.main.async {
                    self?.isSending = false
                    self?.errorMessage = "Failed to get authentication token"
                    self?.showErrorAlert = true
                }
                return
            }
            
            let requestBody: [String: Any] = [
                "title": self.title.trimmingCharacters(in: .whitespacesAndNewlines),
                "body": self.body.trimmingCharacters(in: .whitespacesAndNewlines),
                "targetType": self.targetType == .all ? "all" : "individual",
                "userIds": self.targetType == .individual ? Array(self.selectedUserIds) : [],
                "includeAdmins": self.includeAdmins,
                "isPromotional": self.isPromotional
            ]
            
            guard let url = URL(string: "\(Config.backendURL)/admin/notifications/send") else {
                DispatchQueue.main.async {
                    self.isSending = false
                    self.errorMessage = "Invalid server URL"
                    self.showErrorAlert = true
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    self?.isSending = false
                    
                    if let error = error {
                        self?.errorMessage = "Network error: \(error.localizedDescription)"
                        self?.showErrorAlert = true
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self?.errorMessage = "Invalid response"
                        self?.showErrorAlert = true
                        return
                    }
                    
                    if httpResponse.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let successCount = json["successCount"] as? Int ?? 0
                            let failureCount = json["failureCount"] as? Int ?? 0
                            self?.successMessage = "Notification sent successfully!\n\(successCount) delivered, \(failureCount) failed"
                        } else {
                            self?.successMessage = "Notification sent successfully!"
                        }
                        self?.showSuccessAlert = true
                        self?.loadSentNotifications()
                    } else {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMsg = json["error"] as? String {
                            self?.errorMessage = errorMsg
                        } else {
                            self?.errorMessage = "Failed to send notification (status: \(httpResponse.statusCode))"
                        }
                        self?.showErrorAlert = true
                    }
                }
            }.resume()
        }
    }
    
    // MARK: - Clear Form
    
    func clearForm() {
        title = ""
        body = ""
        selectedUserIds.removeAll()
        targetType = .all
        includeAdmins = false
        isPromotional = true // Reset to default (promotional)
    }
    
    // MARK: - Load Sent Notifications
    
    func loadSentNotifications() {
        db.collection("sentNotifications")
            .order(by: "sentAt", descending: true)
            .limit(to: 10)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    DebugLogger.debug("❌ Error loading sent notifications: \(error.localizedDescription)", category: "Admin")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    self?.sentNotifications = documents.map { doc in
                        let data = doc.data()
                        return SentNotification(
                            id: doc.documentID,
                            title: data["title"] as? String ?? "",
                            body: data["body"] as? String ?? "",
                            sentAt: (data["sentAt"] as? Timestamp)?.dateValue() ?? Date(),
                            targetType: data["targetType"] as? String ?? "all",
                            targetUserIds: data["targetUserIds"] as? [String],
                            successCount: data["successCount"] as? Int ?? 0,
                            failureCount: data["failureCount"] as? Int ?? 0
                        )
                    }
                }
            }
    }
}

// MARK: - Models

struct NotificationUser: Identifiable {
    let id: String
    let firstName: String
    let phone: String
    let avatarEmoji: String
    let hasFcmToken: Bool
    let isAdmin: Bool
}

struct SentNotification: Identifiable {
    let id: String
    let title: String
    let body: String
    let sentAt: Date
    let targetType: String
    let targetUserIds: [String]?
    let successCount: Int
    let failureCount: Int
}

// MARK: - Preview

#if DEBUG
struct AdminNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        AdminNotificationsView()
    }
}
#endif
