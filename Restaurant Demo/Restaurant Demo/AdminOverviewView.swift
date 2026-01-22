import SwiftUI

struct AdminOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminOverviewViewModel()
    
    // Navigation state
    @State private var showUsersSection = false
    @State private var showReceiptsSection = false
    @State private var showRewardsScan = false
    @State private var showRewardTierAdmin = false
    @State private var showNotifications = false
    @State private var showRewardHistory = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        header
                        
                        // Stats Grid
                        if viewModel.isLoading && viewModel.stats == nil {
                            loadingView
                        } else if let stats = viewModel.stats {
                            statsGrid(stats: stats)
                        } else if let error = viewModel.errorMessage {
                            errorView(message: error)
                        }
                        
                        // Quick Actions
                        quickActions
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.loadStats()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await viewModel.loadStats()
                }
            }
            .sheet(isPresented: $showUsersSection) {
                AdminDetailView(initialTab: 0)
            }
            .sheet(isPresented: $showReceiptsSection) {
                AdminDetailView(initialTab: 1)
            }
            .sheet(isPresented: $showRewardsScan) {
                AdminRewardsScanView()
            }
            .sheet(isPresented: $showRewardTierAdmin) {
                RewardTierAdminView()
            }
            .sheet(isPresented: $showNotifications) {
                AdminNotificationsView()
            }
            .sheet(isPresented: $showRewardHistory) {
                AdminRewardHistoryView()
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
                
                Text("Admin Overview")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    viewModel.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            // Subtitle
            Text("Business metrics at a glance")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading statistics...")
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
                viewModel.refresh()
            }
            .font(.headline)
            .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Stats Grid
    
    private func statsGrid(stats: AdminStats) -> some View {
        VStack(spacing: 16) {
            // Users Section
            sectionHeader(title: "Users", icon: "person.3.fill", color: .blue)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(
                    title: "Total Users",
                    value: "\(stats.totalUsers)",
                    icon: "person.fill",
                    color: .blue
                )
                
                AdminStatCard(
                    title: "New Today",
                    value: "\(stats.newUsersToday)",
                    icon: "person.badge.plus",
                    color: .green
                )
                
                AdminStatCard(
                    title: "New This Week",
                    value: "\(stats.newUsersThisWeek)",
                    icon: "calendar",
                    color: .purple
                )
                
                AdminStatCard(
                    title: "Points Given",
                    value: formatNumber(stats.totalPointsDistributed),
                    icon: "star.fill",
                    color: .orange
                )
            }
            
            // Receipts Section
            sectionHeader(title: "Receipts", icon: "doc.text.viewfinder", color: .green)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(
                    title: "Total Scanned",
                    value: "\(stats.totalReceipts)",
                    icon: "doc.text.fill",
                    color: .green
                )
                
                AdminStatCard(
                    title: "Scanned Today",
                    value: "\(stats.receiptsToday)",
                    icon: "clock.fill",
                    color: .teal
                )
                
                AdminStatCard(
                    title: "This Week",
                    value: "\(stats.receiptsThisWeek)",
                    icon: "calendar.badge.clock",
                    color: .mint
                )
            }
            
            // Rewards Section
            sectionHeader(title: "Rewards", icon: "gift.fill", color: .purple)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(
                    title: "Total Redeemed",
                    value: "\(stats.totalRewardsRedeemed)",
                    icon: "gift.fill",
                    color: .purple
                )
                
                AdminStatCard(
                    title: "Redeemed Today",
                    value: "\(stats.rewardsRedeemedToday)",
                    icon: "sparkles",
                    color: .pink
                )
            }
        }
    }
    
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
    
    // MARK: - Quick Actions
    
    private var quickActions: some View {
        VStack(spacing: 12) {
            sectionHeader(title: "Quick Actions", icon: "bolt.fill", color: .orange)
            
            // Manage Users
            ActionButton(
                title: "Manage Users",
                subtitle: "View and manage user accounts",
                icon: "person.3.fill",
                gradient: [.blue, .cyan]
            ) {
                showUsersSection = true
            }
            
            // View Receipts
            ActionButton(
                title: "View Receipts",
                subtitle: "See scanned receipts",
                icon: "doc.text.viewfinder",
                gradient: [.green, .mint]
            ) {
                showReceiptsSection = true
            }
            
            // Scan Rewards
            ActionButton(
                title: "Scan Rewards",
                subtitle: "Scan customer reward QR codes",
                icon: "qrcode.viewfinder",
                gradient: [.purple, .pink]
            ) {
                showRewardsScan = true
            }
            
            // Reward Config
            ActionButton(
                title: "Reward Item Config",
                subtitle: "Configure reward tier items",
                icon: "gift.fill",
                gradient: [.orange, .red]
            ) {
                showRewardTierAdmin = true
            }
            
            // Send Notifications
            ActionButton(
                title: "Send Notifications",
                subtitle: "Send push notifications to customers",
                icon: "bell.badge.fill",
                gradient: [.indigo, .purple]
            ) {
                showNotifications = true
            }
            
            // Reward History
            ActionButton(
                title: "Reward History",
                subtitle: "View monthly redemption activity",
                icon: "clock.arrow.circlepath",
                gradient: [.teal, .cyan]
            ) {
                showRewardHistory = true
            }
        }
    }
}

// MARK: - Stat Card Component

struct AdminStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Admin Detail View (Users & Receipts Tabs)

struct AdminDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userViewModel = AdminOfficeViewModel()
    @State private var searchText = ""
    @State private var selectedTab: Int
    @State private var selectedUser: UserAccount?
    
    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header
                    tabSelector
                    Divider()
                        .padding(.bottom, 4)
                    tabContent
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            userViewModel.loadUsers()
        }
        .alert("Cleanup Complete", isPresented: .constant(userViewModel.cleanupResult != nil), presenting: userViewModel.cleanupResult) { result in
            Button("OK") {
                userViewModel.cleanupResult = nil
            }
        } message: { result in
            Text("Checked \(result.checkedCount) accounts\nDeleted \(result.deletedCount) orphaned accounts\n\n\(result.message)")
        }
        .alert("Error", isPresented: .constant(userViewModel.errorMessage != nil && !userViewModel.isCleaningUp), presenting: userViewModel.errorMessage) { message in
            Button("OK") {
                userViewModel.errorMessage = nil
            }
        } message: { message in
            Text(message)
        }
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text(selectedTab == 0 ? "Users" : "Receipts")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    if selectedTab == 0 {
                        Button(action: {
                            userViewModel.cleanupOrphanedAccounts()
                        }) {
                            if userViewModel.isCleaningUp {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                            }
                        }
                        .disabled(userViewModel.isCleaningUp)
                    }
                    
                    Button(action: {
                        if selectedTab == 0 {
                            userViewModel.refreshUsers()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            if selectedTab == 0 {
                // Search + sort only apply to Users tab
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search by name, email, or phone...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onChange(of: searchText) { _, newValue in
                                userViewModel.searchUsers(query: newValue)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    )
                    
                    // Sort Controls
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(AdminOfficeViewModel.SortOption.allCases, id: \.self) { option in
                                Button(option.rawValue) {
                                    userViewModel.sortOption = option
                                    userViewModel.sortUsers()
                                }
                            }
                        } label: {
                            HStack {
                                Text("Sort by: \(userViewModel.sortOption.rawValue)")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        
                        Button(action: {
                            userViewModel.sortOrder = userViewModel.sortOrder == .ascending ? .descending : .ascending
                            userViewModel.sortUsers()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: userViewModel.sortOrder == .ascending ? "arrow.up" : "arrow.down")
                                    .font(.caption)
                                Text(userViewModel.sortOrder.rawValue)
                                    .font(.subheadline)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 10)
    }
    
    private var tabSelector: some View {
        HStack(spacing: 12) {
            tabButton(title: "Users", icon: "person.3", index: 0)
            tabButton(title: "Receipts", icon: "doc.text.viewfinder", index: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedTab == index ? Color.white : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(selectedTab == index ? 0.08 : 0.04), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var tabContent: some View {
        Group {
            if selectedTab == 0 {
                usersTab
            } else {
                AdminReceiptsView()
            }
        }
    }
    
    private var usersTab: some View {
        Group {
            if userViewModel.isLoading {
                Spacer()
                ProgressView("Loading users...")
                    .scaleEffect(1.2)
                Spacer()
            } else if userViewModel.filteredUsers.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "person.3")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text(searchText.isEmpty ? "No users found" : "No users match your search")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .foregroundColor(.blue)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(userViewModel.filteredUsers) { user in
                            Button(action: {
                                selectedUser = user
                            }) {
                                AdminUserRow(user: user)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if userViewModel.hasMore {
                            ProgressView()
                                .onAppear { userViewModel.fetchNextPage() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .sheet(item: $selectedUser) { user in
            AdminUserDetailView(user: user)
        }
    }
}
