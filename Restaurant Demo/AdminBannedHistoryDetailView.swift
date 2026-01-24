//
//  AdminBannedHistoryDetailView.swift
//  Restaurant Demo
//
//  Detail view for viewing archived banned account data
//

import SwiftUI

struct AdminBannedHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: BannedAccountHistory
    @ObservedObject var viewModel: AdminBannedHistoryViewModel
    @State private var showDeleteConfirmation: Bool = false
    @State private var isDeleting: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        expirationSection
                        userInfoSection
                        activitySummarySection
                        banInfoSection
                        deleteSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("Archived Account")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .alert("Delete Archive", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteRecord()
                    }
                }
            } message: {
                Text("This will permanently delete this archived record. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.3))
                    .frame(width: 64, height: 64)
                Text(record.userData.avatarEmoji)
                    .font(.system(size: 28))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("\(record.userData.firstName) \(record.userData.lastName)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(record.userData.phone)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                
                HStack(spacing: 8) {
                    pill(text: "Banned", color: .red)
                    if record.userData.isVerified {
                        pill(text: "Was Verified", color: .green)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }
    
    // MARK: - Expiration Section
    
    private var expirationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archive Status")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Archived At")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(formatDate(record.archivedAt))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Auto-Delete In")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(record.timeRemaining)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(record.isExpired ? .red : .orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.12, blue: 0.08))
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }
    
    // MARK: - User Info Section
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account Details")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                infoRow(label: "Points at Deletion", value: "\(record.userData.points)")
                infoRow(label: "Lifetime Points", value: "\(record.userData.lifetimePoints)")
                if let createdDate = record.userData.accountCreatedDate {
                    infoRow(label: "Account Created", value: formatDate(createdDate))
                }
                infoRow(label: "Completed Preferences", value: record.userData.hasCompletedPreferences ? "Yes" : "No")
                infoRow(label: "Original User ID", value: String(record.originalUserId.prefix(12)) + "...")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }
    
    // MARK: - Activity Summary Section
    
    private var activitySummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Summary")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                statCard(icon: "doc.text", value: record.receiptCount, label: "Receipts")
                statCard(icon: "gift", value: record.redeemedRewardsCount, label: "Rewards")
                statCard(icon: "bubble.left", value: record.postCount, label: "Posts")
                statCard(icon: "person.2", value: record.referralCount, label: "Referrals")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }
    
    // MARK: - Ban Info Section
    
    private var banInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ban Information")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            VStack(spacing: 8) {
                infoRow(label: "Ban Reason", value: record.banReason)
                if let bannedAt = record.bannedAt {
                    infoRow(label: "Banned At", value: formatDate(bannedAt))
                }
                if let bannedBy = record.bannedBy {
                    infoRow(label: "Banned By", value: String(bannedBy.prefix(12)) + "...")
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }
    
    // MARK: - Delete Section
    
    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Button(action: {
                showDeleteConfirmation = true
            }) {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "trash")
                        Text("Delete Archive Now")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isDeleting)
            
            Text("This archive will be automatically deleted when the 24-hour period expires.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }
    
    // MARK: - Helper Views
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }
    
    private func statCard(icon: String, value: Int, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .cornerRadius(6)
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Actions
    
    private func deleteRecord() async {
        isDeleting = true
        let success = await viewModel.deleteRecord(record)
        isDeleting = false
        if success {
            dismiss()
        }
    }
}

#Preview {
    let mockRecord = BannedAccountHistory(
        id: "test_123",
        originalUserId: "user123abc",
        archivedAt: Date(),
        expiresAt: Date().addingTimeInterval(23 * 3600),
        userData: BannedAccountHistory.UserDataSnapshot(
            firstName: "John",
            lastName: "Doe",
            phone: "+15551234567",
            points: 150,
            lifetimePoints: 500,
            accountCreatedDate: Date().addingTimeInterval(-30 * 24 * 3600),
            avatarEmoji: "😀",
            avatarColor: "blue",
            isVerified: true,
            hasCompletedPreferences: true
        ),
        receiptCount: 15,
        redeemedRewardsCount: 8,
        postCount: 3,
        referralCount: 2,
        banReason: "Suspicious activity",
        bannedAt: Date().addingTimeInterval(-24 * 3600),
        bannedBy: "admin123"
    )
    
    return AdminBannedHistoryDetailView(
        record: mockRecord,
        viewModel: AdminBannedHistoryViewModel()
    )
}
