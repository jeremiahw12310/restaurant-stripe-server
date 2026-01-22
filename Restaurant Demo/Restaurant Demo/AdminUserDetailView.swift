import SwiftUI

/// Read‑only admin view for inspecting a single user's profile and loyalty data.
struct AdminUserDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AdminUserDetailViewModel
    @State private var showAllTransactions: Bool = false
    @State private var isEditing: Bool = false

    init(user: UserAccount) {
        _viewModel = StateObject(wrappedValue: AdminUserDetailViewModel(user: user))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Loading user details…")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                } else if !viewModel.errorMessage.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text("Couldn’t load user")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(viewModel.errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection
                            pointsSection
                            if isEditing {
                                accountFlagsSection
                            }
                            rewardsHistorySection
                            dietarySection
                            referralSection
                            banSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
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
                    Text("User Details")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            viewModel.syncEditableFieldsFromSummary()
                        }
                        .tint(.white)

                        Button("Save") {
                            viewModel.saveAdminEdits { success, message in
                                if success {
                                    isEditing = false
                                }
                            }
                        }
                        .tint(.white)
                    } else {
                        Button("Edit") {
                            viewModel.syncEditableFieldsFromSummary()
                            isEditing = true
                        }
                        .tint(.white)
                    }
                }
            }
        }
        .onAppear {
            showAllTransactions = false
            viewModel.loadAll()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        let user = viewModel.userSummary

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(user.avatarColor.opacity(0.3))
                    .frame(width: 64, height: 64)
                Text(user.avatarEmoji)
                    .font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(user.firstName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }

                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }

                if isEditing {
                    TextField("Phone number", text: $viewModel.editablePhoneNumber)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.phonePad)
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                } else if !user.phoneNumber.isEmpty {
                    Text(user.phoneNumber)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }

                HStack(spacing: 8) {
                    if user.isAdmin {
                        pill(text: "Admin", color: .yellow)
                    }
                    if user.isEmployee {
                        pill(text: "Employee", color: .blue)
                    }
                    if user.isVerified {
                        pill(text: "Verified", color: .green)
                    }
                    if user.isBanned {
                        pill(text: "Banned", color: .red)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }

    private var pointsSection: some View {
        let user = viewModel.userSummary

        return VStack(alignment: .leading, spacing: 12) {
            Text("Points")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    if isEditing {
                        TextField("Points", text: $viewModel.editablePoints)
                            .keyboardType(.numberPad)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                    } else {
                        Text("\(user.points)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Lifetime")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(user.lifetimePoints)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()
            }

            if let summary = viewModel.summary {
                PointsHistorySummaryCard(summary: summary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }

    private var accountFlagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account Flags")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Toggle(isOn: $viewModel.editableIsAdmin) {
                Text("Admin")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(.yellow)

            Toggle(isOn: $viewModel.editableIsVerified) {
                Text("Verified")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }

    private var rewardsHistorySection: some View {
        // Decide how many transactions to show by default
        let displayedTransactions: [PointsTransaction] = {
            if showAllTransactions {
                return viewModel.transactions
            } else {
                return Array(viewModel.transactions.prefix(5))
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rewards History")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(viewModel.transactions.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }

            if viewModel.transactions.isEmpty {
                Text("No points transactions recorded yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                VStack(spacing: 10) {
                    ForEach(displayedTransactions) { tx in
                        TransactionCard(transaction: tx)
                    }

                    if viewModel.transactions.count > 5 && !showAllTransactions {
                        Button(action: {
                            showAllTransactions = true
                        }) {
                            HStack {
                                Text("See full history")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }

    private var dietarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dietary Preferences")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            if !viewModel.hasCompletedPreferences &&
                !viewModel.likesSpicyFood &&
                !viewModel.dislikesSpicyFood &&
                !viewModel.hasPeanutAllergy &&
                !viewModel.isVegetarian &&
                !viewModel.hasLactoseIntolerance &&
                !viewModel.doesntEatPork &&
                viewModel.tastePreferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No dietary preferences set.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    preferenceRow("Likes spicy food", isOn: viewModel.likesSpicyFood)
                    preferenceRow("Dislikes spicy food", isOn: viewModel.dislikesSpicyFood)
                    preferenceRow("Peanut allergy", isOn: viewModel.hasPeanutAllergy)
                    preferenceRow("Vegetarian", isOn: viewModel.isVegetarian)
                    preferenceRow("Lactose intolerance", isOn: viewModel.hasLactoseIntolerance)
                    preferenceRow("Doesn't eat pork", isOn: viewModel.doesntEatPork)

                    if !viewModel.tastePreferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text(viewModel.tastePreferences)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }

    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Referrals")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            if let code = viewModel.referralCode, !code.isEmpty {
                HStack(spacing: 8) {
                    Text("Referral Code:")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Text(code)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            } else {
                Text("No referral code generated yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }

            if viewModel.inboundReferral == nil && viewModel.outboundReferrals.isEmpty {
                Text("No referral connections yet.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let inbound = viewModel.inboundReferral {
                        referralRow(inbound)
                    }
                    ForEach(viewModel.outboundReferrals) { ref in
                        referralRow(ref)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
    }

    // MARK: - Small helpers

    private func pill(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func preferenceRow(_ label: String, isOn: Bool) -> some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isOn ? .green : .gray)
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
    }

    private func referralRow(_ connection: AdminUserDetailViewModel.ReferralConnection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(String(connection.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.relation)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Text(connection.name)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }

                HStack(spacing: 8) {
                    statusBadge(connection.status)
                    if connection.pointsTowards50 > 0 {
                        Text("\(connection.pointsTowards50)/50 pts")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(status == "Awarded" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            )
            .foregroundColor(status == "Awarded" ? .green : .orange)
    }

    // MARK: - Ban Section

    @State private var showBanConfirmation = false
    @State private var showUnbanConfirmation = false
    @State private var banReason: String = ""

    private var banSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account Status")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            if viewModel.userSummary.isBanned {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("This user is banned")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }

                Button(action: {
                    showUnbanConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Unban User")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isBanning)
            } else {
                Button(action: {
                    showBanConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Ban User")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isBanning)
            }

            if viewModel.isBanning {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Processing...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            if let banError = viewModel.banError {
                Text(banError)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.15))
        )
        .alert("Ban User", isPresented: $showBanConfirmation) {
            TextField("Reason (optional)", text: $banReason)
            Button("Cancel", role: .cancel) {
                banReason = ""
            }
            Button("Ban", role: .destructive) {
                viewModel.banUser(reason: banReason.isEmpty ? nil : banReason) { success, error in
                    if success {
                        banReason = ""
                    }
                }
            }
        } message: {
            Text("Are you sure you want to ban this user? They will not be able to sign in or create a new account with this phone number.")
        }
        .alert("Unban User", isPresented: $showUnbanConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unban", role: .destructive) {
                viewModel.unbanUser { success, error in
                    // Handled in viewModel
                }
            }
        } message: {
            Text("Are you sure you want to unban this user? They will be able to sign in again.")
        }
    }
}


