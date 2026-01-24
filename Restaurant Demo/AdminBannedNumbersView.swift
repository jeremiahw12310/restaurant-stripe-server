import SwiftUI

struct AdminBannedNumbersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminBannedNumbersViewModel()
    @State private var showUnbanConfirmation: BannedNumber?
    @State private var showBanPhoneSheet: Bool = false
    @State private var phoneNumberInput: String = ""
    @State private var banReasonInput: String = ""
    @State private var showBanConfirmation: Bool = false
    
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
            .sheet(isPresented: $showBanPhoneSheet) {
                banPhoneSheet
            }
            .alert("Success", isPresented: $viewModel.showBanSuccess) {
                Button("OK") {
                    showBanPhoneSheet = false
                    phoneNumberInput = ""
                    banReasonInput = ""
                }
            } message: {
                Text(viewModel.banSuccessMessage)
            }
            .alert("Ban Phone Number", isPresented: $showBanConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Ban", role: .destructive) {
                    Task {
                        await viewModel.banPhoneNumber(
                            phone: phoneNumberInput,
                            reason: banReasonInput.isEmpty ? nil : banReasonInput
                        )
                    }
                }
            } message: {
                Text("Are you sure you want to ban \(phoneNumberInput)? This will prevent signups and ban any existing account with this number.")
            }
        }
    }
    
    // MARK: - Ban Phone Sheet
    
    private var banPhoneSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header info
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill.badge.xmark")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            
                            Text("Ban Phone Number")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Enter a phone number to ban. Any existing account with this number will be banned, and future signups will be blocked.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)
                        
                        // Phone input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone Number")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("+1 (555) 123-4567", text: $phoneNumberInput)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(phoneNumberInput.isEmpty ? Color.clear : (isValidPhone(phoneNumberInput) ? Color.green : Color.red), lineWidth: 2)
                                )
                            
                            if !phoneNumberInput.isEmpty && !isValidPhone(phoneNumberInput) {
                                Text("Please enter a valid 10-digit phone number")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        // Reason input (optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reason (Optional)")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Enter reason for banning...", text: $banReasonInput, axis: .vertical)
                                .lineLimit(3...6)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                        }
                        
                        // Error message
                        if let error = viewModel.banPhoneError {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                        }
                        
                        // Ban button
                        Button(action: {
                            if isValidPhone(phoneNumberInput) {
                                showBanConfirmation = true
                            }
                        }) {
                            HStack {
                                if viewModel.isBanningPhone {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Ban Phone Number")
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValidPhone(phoneNumberInput) && !viewModel.isBanningPhone ? Color.red : Color.gray)
                            .cornerRadius(10)
                        }
                        .disabled(!isValidPhone(phoneNumberInput) || viewModel.isBanningPhone)
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showBanPhoneSheet = false
                        phoneNumberInput = ""
                        banReasonInput = ""
                        viewModel.banPhoneError = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Phone Validation
    
    private func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        // Accept 10 or 11 digits (10 digits or 1 + 10 digits)
        return digits.count == 10 || (digits.count == 11 && digits.hasPrefix("1"))
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
                
                HStack(spacing: 16) {
                    Button(action: {
                        showBanPhoneSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    
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
