//
//  AdminBannedHistoryView.swift
//  Restaurant Demo
//
//  Admin view to see recently deleted banned accounts (archived for 24 hours)
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct BannedAccountHistory: Identifiable {
    let id: String
    let originalUserId: String
    let archivedAt: Date
    let expiresAt: Date
    let userData: UserDataSnapshot
    let receiptCount: Int
    let redeemedRewardsCount: Int
    let postCount: Int
    let referralCount: Int
    let banReason: String
    let bannedAt: Date?
    let bannedBy: String?
    
    var timeRemaining: String {
        let interval = expiresAt.timeIntervalSince(Date())
        if interval <= 0 {
            return "Expired"
        }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
    }
    
    var isExpired: Bool {
        expiresAt <= Date()
    }
    
    struct UserDataSnapshot {
        let firstName: String
        let lastName: String
        let phone: String
        let points: Int
        let lifetimePoints: Int
        let accountCreatedDate: Date?
        let avatarEmoji: String
        let avatarColor: String
        let isVerified: Bool
        let hasCompletedPreferences: Bool
    }
}

// MARK: - ViewModel

@MainActor
class AdminBannedHistoryViewModel: ObservableObject {
    @Published var historyRecords: [BannedAccountHistory] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var cleanupMessage: String?
    
    private let db = Firestore.firestore()
    
    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let snapshot = try await db.collection("bannedAccountHistory")
                .order(by: "archivedAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            var records: [BannedAccountHistory] = []
            
            for doc in snapshot.documents {
                let data = doc.data()
                
                // Parse userData
                let userDataDict = data["userData"] as? [String: Any] ?? [:]
                let userData = BannedAccountHistory.UserDataSnapshot(
                    firstName: userDataDict["firstName"] as? String ?? "",
                    lastName: userDataDict["lastName"] as? String ?? "",
                    phone: userDataDict["phone"] as? String ?? "",
                    points: userDataDict["points"] as? Int ?? 0,
                    lifetimePoints: userDataDict["lifetimePoints"] as? Int ?? 0,
                    accountCreatedDate: (userDataDict["accountCreatedDate"] as? Timestamp)?.dateValue(),
                    avatarEmoji: userDataDict["avatarEmoji"] as? String ?? "👤",
                    avatarColor: userDataDict["avatarColor"] as? String ?? "gray",
                    isVerified: userDataDict["isVerified"] as? Bool ?? false,
                    hasCompletedPreferences: userDataDict["hasCompletedPreferences"] as? Bool ?? false
                )
                
                let record = BannedAccountHistory(
                    id: doc.documentID,
                    originalUserId: data["originalUserId"] as? String ?? "",
                    archivedAt: (data["archivedAt"] as? Timestamp)?.dateValue() ?? Date(),
                    expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue() ?? Date(),
                    userData: userData,
                    receiptCount: data["receiptCount"] as? Int ?? 0,
                    redeemedRewardsCount: data["redeemedRewardsCount"] as? Int ?? 0,
                    postCount: data["postCount"] as? Int ?? 0,
                    referralCount: data["referralCount"] as? Int ?? 0,
                    banReason: data["banReason"] as? String ?? "Banned",
                    bannedAt: (data["bannedAt"] as? Timestamp)?.dateValue(),
                    bannedBy: data["bannedBy"] as? String
                )
                records.append(record)
            }
            
            historyRecords = records
            isLoading = false
            
            // Auto-cleanup expired records on load
            await cleanupExpiredRecords()
            
        } catch {
            errorMessage = "Failed to load history: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func cleanupExpiredRecords() async {
        guard let user = Auth.auth().currentUser else { return }
        
        do {
            let token = try await user.getIDToken()
            guard let url = URL(string: "\(Config.backendURL)/admin/cleanup-expired-history") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 200 && httpResponse.statusCode < 300,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let deletedCount = json["deletedCount"] as? Int,
               deletedCount > 0 {
                cleanupMessage = "Cleaned up \(deletedCount) expired record(s)"
                // Reload to reflect changes
                await loadHistory()
            }
        } catch {
            print("Cleanup error: \(error.localizedDescription)")
        }
    }
    
    func deleteRecord(_ record: BannedAccountHistory) async -> Bool {
        do {
            try await db.collection("bannedAccountHistory").document(record.id).delete()
            historyRecords.removeAll { $0.id == record.id }
            return true
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Main View

struct AdminBannedHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminBannedHistoryViewModel()
    @State private var selectedRecord: BannedAccountHistory?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        header
                        
                        // Content
                        if viewModel.isLoading && viewModel.historyRecords.isEmpty {
                            loadingView
                        } else if let error = viewModel.errorMessage {
                            errorView(message: error)
                        } else if viewModel.historyRecords.isEmpty {
                            emptyStateView
                        } else {
                            recordsList
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.loadHistory()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await viewModel.loadHistory()
                }
            }
            .sheet(item: $selectedRecord) { record in
                AdminBannedHistoryDetailView(record: record, viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("Banned Account History")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await viewModel.loadHistory()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            // Subtitle
            Text("Archived banned accounts (auto-deleted after 24 hours)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Cleanup message
            if let message = viewModel.cleanupMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Records List
    
    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(viewModel.historyRecords.count) archived account\(viewModel.historyRecords.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            LazyVStack(spacing: 12) {
                ForEach(viewModel.historyRecords) { record in
                    BannedHistoryRow(record: record)
                        .onTapGesture {
                            selectedRecord = record
                        }
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading history...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task {
                    await viewModel.loadHistory()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No Archived Accounts")
                .font(.headline)
            Text("When banned users delete their accounts, they'll appear here for 24 hours.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Row View

struct BannedHistoryRow: View {
    let record: BannedAccountHistory
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.3))
                    .frame(width: 50, height: 50)
                Text(record.userData.avatarEmoji)
                    .font(.system(size: 22))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("\(record.userData.firstName) \(record.userData.lastName)")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(maskedPhone)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text(record.timeRemaining)
                        .font(.caption)
                        .foregroundColor(record.isExpired ? .red : .orange)
                    
                    Text("\(record.userData.points) pts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var maskedPhone: String {
        let phone = record.userData.phone
        if phone.count > 4 {
            let lastFour = String(phone.suffix(4))
            return "***-***-\(lastFour)"
        }
        return phone
    }
    
    private var avatarColor: Color {
        switch record.userData.avatarColor.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "indigo": return .indigo
        case "brown": return .brown
        case "gold": return Color(red: 1.0, green: 0.84, blue: 0.0)
        default: return .gray
        }
    }
}

#Preview {
    AdminBannedHistoryView()
}
