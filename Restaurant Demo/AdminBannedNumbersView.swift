import SwiftUI

struct AdminBannedNumbersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminBannedNumbersViewModel()
    @State private var showUnbanConfirmation: BannedNumber?
    
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
                        if viewModel.isLoading && viewModel.bannedNumbers.isEmpty {
                            loadingView
                        } else if let error = viewModel.errorMessage {
                            errorView(message: error)
                        } else if viewModel.bannedNumbers.isEmpty {
                            emptyStateView
                        } else {
                            bannedNumbersList
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.loadBannedNumbers()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await viewModel.loadBannedNumbers()
                }
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
                
                Text("Banned Numbers")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await viewModel.loadBannedNumbers()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            // Subtitle
            Text("Phone numbers that cannot be used to create accounts")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Banned Numbers List
    
    private var bannedNumbersList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(viewModel.bannedNumbers.count) banned number\(viewModel.bannedNumbers.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.bannedNumbers.enumerated()), id: \.element.id) { index, bannedNumber in
                    BannedNumberRow(bannedNumber: bannedNumber, viewModel: viewModel)
                        .onAppear {
                            // Load more when approaching the end
                            if index == viewModel.bannedNumbers.count - 3 {
                                Task {
                                    await viewModel.loadMore()
                                }
                            }
                        }
                }
                
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
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
            Text("Loading banned numbers...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task {
                    await viewModel.loadBannedNumbers()
                }
            }
            .font(.headline)
            .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("No banned numbers")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("All phone numbers are currently allowed")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Banned Number Row

struct BannedNumberRow: View {
    let bannedNumber: BannedNumber
    @ObservedObject var viewModel: AdminBannedNumbersViewModel
    @State private var showUnbanConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Phone number
                VStack(alignment: .leading, spacing: 4) {
                    Text(bannedNumber.phone)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if let userName = bannedNumber.originalUserName {
                        Text("User: \(userName)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Unban button
                Button(action: {
                    showUnbanConfirmation = true
                }) {
                    Text("Unban")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .disabled(viewModel.isUnbanning)
            }
            
            // Metadata
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Banned by: \(bannedNumber.bannedByEmail)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                if let bannedAt = bannedNumber.bannedAt {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Banned: \(viewModel.formatDate(bannedAt))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let reason = bannedNumber.reason, !reason.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Reason: \(reason)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .alert("Unban Number", isPresented: $showUnbanConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unban", role: .destructive) {
                viewModel.unbanNumber(bannedNumber.phone) { success, error in
                    // Handled in viewModel
                }
            }
        } message: {
            Text("Are you sure you want to unban \(bannedNumber.phone)? The user will be able to sign in again.")
        }
    }
}
