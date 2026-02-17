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
    @State private var showBannedNumbers = false
    @State private var showSuspiciousFlags = false
    @State private var showBannedHistory = false
    @State private var showSendRewards = false
    @State private var showReservations = false
    @State private var openReservationsWithPendingFilter = false

    // View all analytics sheet
    @State private var showAllAnalytics = false

    // Swipe to dismiss state
    @State private var dragOffset: CGFloat = 0
    @State private var isAtTop: Bool = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            header
                            
                            // Carousel (4 key stats)
                            statsCarousel
                            
                            // View all analytics button
                            Button(action: { showAllAnalytics = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chart.bar.doc.horizontal")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("View all analytics")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.blue)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Gold card: new reservation(s) when pending count > 0
                            if viewModel.pendingReservationsCount > 0 {
                                newReservationGoldCard
                            }

                            // Organized action sections
                            organizedActions
                            
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .id("top")
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                            }
                        )
                    }
                    .coordinateSpace(name: "scroll")
                    .refreshable {
                        await viewModel.loadStats()
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        // Check if we're at the top (with small threshold for floating point precision)
                        isAtTop = value <= 10
                    }
                }
                .offset(y: max(0, dragOffset))
                .opacity(dragOffset > 0 ? max(0.7, 1 - dragOffset / 300) : 1)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // Only allow drag to dismiss when at the top and dragging down
                            if isAtTop && value.translation.height > 0 {
                                dragOffset = value.translation.height
                            } else if dragOffset > 0 && !isAtTop {
                                // Reset if user scrolls away from top while dragging
                                dragOffset = 0
                            }
                        }
                        .onEnded { value in
                            // If dragged down more than 100 points, dismiss
                            if dragOffset > 100 && isAtTop {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    dismiss()
                                }
                            } else {
                                // Spring back to original position
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
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
            .sheet(isPresented: $showBannedNumbers) {
                AdminBannedNumbersView()
            }
            .sheet(isPresented: $showSuspiciousFlags) {
                AdminSuspiciousFlagsView()
            }
            .sheet(isPresented: $showBannedHistory) {
                AdminBannedHistoryView()
            }
            .sheet(isPresented: $showSendRewards) {
                AdminSendRewardsView()
            }
            .sheet(isPresented: $showReservations, onDismiss: {
                openReservationsWithPendingFilter = false
                Task { await viewModel.loadPendingReservationsCount() }
            }) {
                AdminReservationsView(initialFilter: openReservationsWithPendingFilter ? .pending : nil)
            }
            .sheet(isPresented: $showAllAnalytics) {
                AllAnalyticsView(
                    stats: viewModel.stats,
                    isLoading: viewModel.isLoading,
                    errorMessage: viewModel.errorMessage,
                    formatNumber: { formatNumber($0) },
                    onRetry: { viewModel.refresh() },
                    onUsers: {
                        showAllAnalytics = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showUsersSection = true }
                    },
                    onReceipts: {
                        showAllAnalytics = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showReceiptsSection = true }
                    },
                    onRewardHistory: {
                        showAllAnalytics = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showRewardHistory = true }
                    }
                )
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
    
    // MARK: - Stats Carousel (4 key cards at top)
    
    private var statsCarousel: some View {
        Group {
            if viewModel.isLoading && viewModel.stats == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.0)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Button("Retry") { viewModel.refresh() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            } else if let stats = viewModel.stats {
                let cardSize: CGFloat = 110
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        AdminStatCarouselCard(
                            title: "New Users Today",
                            value: "\(stats.newUsersToday)",
                            icon: "person.badge.plus",
                            color: .green,
                            size: cardSize,
                            action: { showUsersSection = true }
                        )
                        AdminStatCarouselCard(
                            title: "Total Users",
                            value: "\(stats.totalUsers)",
                            icon: "person.fill",
                            color: .blue,
                            size: cardSize,
                            action: { showUsersSection = true }
                        )
                        AdminStatCarouselCard(
                            title: "Scanned Today",
                            value: "\(stats.receiptsToday)",
                            icon: "clock.fill",
                            color: .teal,
                            size: cardSize,
                            action: { showReceiptsSection = true }
                        )
                        AdminStatCarouselCard(
                            title: "Redeemed Today",
                            value: "\(stats.rewardsRedeemedToday)",
                            icon: "sparkles",
                            color: .pink,
                            size: cardSize,
                            action: { showRewardHistory = true }
                        )
                    }
                    .padding(.trailing, 20)
                }
                .frame(height: cardSize)
            } else {
                Color.clear.frame(height: 110)
            }
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
    
    // MARK: - New reservation gold card (pending count > 0)

    private var newReservationGoldCard: some View {
        Button {
            openReservationsWithPendingFilter = true
            showReservations = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.pendingReservationsCount == 1 ? "New reservation" : "\(viewModel.pendingReservationsCount) new reservations")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Tap to review")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.darkGoldGradient)
                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Organized Actions (3 grouped sections)
    
    private var organizedActions: some View {
        VStack(spacing: 12) {
            // Reservations (first)
            actionSectionHeader(title: "Reservations", icon: "calendar.badge.clock", color: .teal)
            ActionButton(
                title: "Reservations",
                subtitle: "View and confirm table reservations",
                icon: "calendar.badge.clock",
                gradient: [.teal, .mint]
            ) {
                openReservationsWithPendingFilter = false
                showReservations = true
            }
            
            // Customers & Receipts
            actionSectionHeader(title: "Customers & Receipts", icon: "person.3.fill", color: .blue)
            ActionButton(
                title: "Manage Users",
                subtitle: "View and manage user accounts",
                icon: "person.3.fill",
                gradient: [.blue, .cyan]
            ) { showUsersSection = true }
            ActionButton(
                title: "View Receipts",
                subtitle: "See scanned receipts",
                icon: "doc.text.viewfinder",
                gradient: [.green, .mint]
            ) { showReceiptsSection = true }
            
            // Rewards
            actionSectionHeader(title: "Rewards", icon: "gift.fill", color: .purple)
            ActionButton(
                title: "Scan Rewards",
                subtitle: "Scan customer reward QR codes",
                icon: "qrcode.viewfinder",
                gradient: [.purple, .pink]
            ) { showRewardsScan = true }
            ActionButton(
                title: "Send Rewards",
                subtitle: "Gift rewards to all customers",
                icon: "gift.fill",
                gradient: [Color(red: 1.0, green: 0.3, blue: 0.5), Color(red: 1.0, green: 0.5, blue: 0.7)]
            ) { showSendRewards = true }
            ActionButton(
                title: "Reward Item Config",
                subtitle: "Configure reward tier items",
                icon: "gift.fill",
                gradient: [.orange, .red]
            ) { showRewardTierAdmin = true }
            ActionButton(
                title: "Reward History",
                subtitle: "View monthly redemption activity",
                icon: "clock.arrow.circlepath",
                gradient: [.teal, .cyan]
            ) { showRewardHistory = true }
            
            // Notifications & Safety
            actionSectionHeader(title: "Notifications & Safety", icon: "bell.badge.fill", color: .indigo)
            ActionButton(
                title: "Send Notifications",
                subtitle: "Send push notifications to customers",
                icon: "bell.badge.fill",
                gradient: [.indigo, .purple]
            ) { showNotifications = true }
            ActionButton(
                title: "Banned Numbers",
                subtitle: "Manage banned phone numbers",
                icon: "hand.raised.fill",
                gradient: [.red, .pink]
            ) { showBannedNumbers = true }
            ActionButton(
                title: "Suspicious Activity",
                subtitle: "Review flagged accounts",
                icon: "exclamationmark.shield.fill",
                gradient: [.orange, .red]
            ) { showSuspiciousFlags = true }
            ActionButton(
                title: "Banned Account History",
                subtitle: "View banned account history",
                icon: "clock.badge.xmark",
                gradient: [Color(red: 0.8, green: 0.2, blue: 0.2), Color(red: 0.9, green: 0.3, blue: 0.3)]
            ) { showBannedHistory = true }
        }
    }
    
    private func actionSectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - All Analytics View (full stats grid in sheet)

struct AllAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    let stats: AdminStats?
    let isLoading: Bool
    let errorMessage: String?
    let formatNumber: (Int) -> String
    let onRetry: () -> Void
    let onUsers: () -> Void
    let onReceipts: () -> Void
    let onRewardHistory: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if isLoading && stats == nil {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Loading statistics...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else if let error = errorMessage, stats == nil {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") { onRetry() }
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if let stats = stats {
                            allAnalyticsGrid(stats: stats)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("All Analytics")
                        .font(.headline)
                }
            }
        }
    }
    
    private func allAnalyticsSectionHeader(title: String, icon: String, color: Color) -> some View {
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
    
    private func allAnalyticsGrid(stats: AdminStats) -> some View {
        VStack(spacing: 16) {
            allAnalyticsSectionHeader(title: "Users", icon: "person.3.fill", color: .blue)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(title: "Total Users", value: "\(stats.totalUsers)", icon: "person.fill", color: .blue, action: onUsers)
                AdminStatCard(title: "New Today", value: "\(stats.newUsersToday)", icon: "person.badge.plus", color: .green, action: onUsers)
                AdminStatCard(title: "New This Week", value: "\(stats.newUsersThisWeek)", icon: "calendar", color: .purple, action: onUsers)
                AdminStatCard(title: "Points Given", value: formatNumber(stats.totalPointsDistributed), icon: "star.fill", color: .orange, action: onUsers)
            }
            allAnalyticsSectionHeader(title: "Receipts", icon: "doc.text.viewfinder", color: .green)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(title: "Total Scanned", value: "\(stats.totalReceipts)", icon: "doc.text.fill", color: .green, action: onReceipts)
                AdminStatCard(title: "Scanned Today", value: "\(stats.receiptsToday)", icon: "clock.fill", color: .teal, action: onReceipts)
                AdminStatCard(title: "This Week", value: "\(stats.receiptsThisWeek)", icon: "calendar.badge.clock", color: .mint, action: onReceipts)
            }
            allAnalyticsSectionHeader(title: "Rewards", icon: "gift.fill", color: .purple)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(title: "Redeemed This Month", value: "\(stats.totalRewardsRedeemed)", icon: "gift.fill", color: .purple, action: onRewardHistory)
                AdminStatCard(title: "Redeemed Today", value: "\(stats.rewardsRedeemedToday)", icon: "sparkles", color: .pink, action: onRewardHistory)
            }
        }
    }
}

// MARK: - Square carousel stat card (compact, multiple visible)

struct AdminStatCarouselCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let size: CGFloat
    let action: (() -> Void)?
    
    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: size, height: size, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(StatCardButtonStyle())
        .disabled(action == nil)
    }
}

// MARK: - Stat Card Component

struct AdminStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let action: (() -> Void)?
    
    init(title: String, value: String, icon: String, color: Color, action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                    
                    Spacer()
                    
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
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
        .buttonStyle(StatCardButtonStyle())
        .disabled(action == nil)
    }
}

// MARK: - Custom Button Style for Stat Cards

struct StatCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
