import SwiftUI

struct AdminRewardHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminRewardHistoryViewModel()
    
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
                        
                        // All-Time Summary Card (always visible at top)
                        if let allTimeSummary = viewModel.allTimeSummary {
                            allTimeSummaryCard(summary: allTimeSummary)
                        }
                        
                        // Time Period Selector
                        timePeriodSelector
                        
                        // Month Picker (only shown when This Month is selected)
                        if viewModel.selectedTimePeriod == .thisMonth && !viewModel.availableMonths.isEmpty {
                            monthPicker
                        }
                        
                        // Content
                        if viewModel.isLoadingRewards && viewModel.currentRewards.isEmpty {
                            loadingView
                        } else if let summary = viewModel.summary {
                            // Summary Card
                            summaryCard(summary: summary)
                            
                            // Rewards List
                            if viewModel.currentRewards.isEmpty {
                                emptyStateView
                            } else {
                                rewardsList
                            }
                        } else if let error = viewModel.errorMessage {
                            errorView(message: error)
                        }
                        
                        // Deleted Reward History section (shown when trash icon tapped)
                        if viewModel.showDeletedSection {
                            deletedSection
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await viewModel.loadAllTimeSummary()
                    if viewModel.selectedTimePeriod == .thisMonth {
                        await viewModel.loadAvailableMonths()
                    } else {
                        // Load data for selected time period
                        await viewModel.loadRewardsForPeriod(viewModel.selectedTimePeriod)
                    }
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
                
                Text("Reward History")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        viewModel.showDeletedSection.toggle()
                        if viewModel.showDeletedSection {
                            Task { await viewModel.loadDeletedRewards() }
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(viewModel.showDeletedSection ? .blue : .secondary)
                    }
                    
                Button(action: {
                    Task { await viewModel.refresh() }
                }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            // Subtitle
            Text(viewModel.selectedTimePeriod == .thisMonth ? 
                 "Monthly redemption activity overview" : 
                 "\(viewModel.selectedTimePeriod.displayName) redemption activity")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - All-Time Summary Card
    
    private func allTimeSummaryCard(summary: RewardHistorySummary) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline)
                    .foregroundColor(.purple)
                
                Text("All-Time Summary")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(
                    title: "Total Rewards",
                    value: "\(summary.totalRewards)",
                    icon: "gift.fill",
                    color: .purple
                )
                
                AdminStatCard(
                    title: "Points Redeemed",
                    value: formatNumber(summary.totalPointsRedeemed),
                    icon: "star.fill",
                    color: .orange
                )
                
                AdminStatCard(
                    title: "Unique Users",
                    value: "\(summary.uniqueUsers)",
                    icon: "person.2.fill",
                    color: .blue
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Time Period Selector
    
    private var timePeriodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time Period")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Button(action: {
                        viewModel.selectedTimePeriod = period
                        Task {
                            await viewModel.loadRewardsForPeriod(period)
                        }
                    }) {
                        Text(period.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(viewModel.selectedTimePeriod == period ? .white : .primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.selectedTimePeriod == period ? Color.blue : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
    
    // MARK: - Month Picker
    
    private var monthPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Month")
                .font(.headline)
                .foregroundColor(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.availableMonths) { month in
                        Button(action: {
                            viewModel.selectedTimePeriod = .thisMonth
                            viewModel.selectedMonth = month.month
                            Task {
                                await viewModel.loadRewardsForMonth(month.month)
                            }
                        }) {
                            VStack(spacing: 4) {
                                Text(viewModel.formatMonth(month.month))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(viewModel.selectedMonth == month.month ? .white : .primary)
                                
                                Text("\(month.count) rewards")
                                    .font(.caption)
                                    .foregroundColor(viewModel.selectedMonth == month.month ? .white.opacity(0.9) : .secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.selectedMonth == month.month ? Color.blue : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Summary Card
    
    private func summaryCard(summary: RewardHistorySummary) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline)
                    .foregroundColor(.purple)
                
                Text("Summary")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AdminStatCard(
                    title: "Total Rewards",
                    value: "\(summary.totalRewards)",
                    icon: "gift.fill",
                    color: .purple
                )
                
                AdminStatCard(
                    title: "Points Redeemed",
                    value: formatNumber(summary.totalPointsRedeemed),
                    icon: "star.fill",
                    color: .orange
                )
                
                AdminStatCard(
                    title: "Unique Users",
                    value: "\(summary.uniqueUsers)",
                    icon: "person.2.fill",
                    color: .blue
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Rewards List
    
    private var rewardsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.subheadline)
                    .foregroundColor(.purple)
                
                Text("Rewards")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.currentRewards.enumerated()), id: \.element.id) { index, reward in
                    RewardHistoryRow(
                        reward: reward,
                        onDelete: {
                            Task { await viewModel.softDeleteReward(id: reward.id) }
                        }
                    )
                    .onAppear {
                        // Load more when approaching the end (3 items before the end)
                        if index == viewModel.currentRewards.count - 3 {
                            Task {
                                await viewModel.loadMoreRewards()
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
    
    // MARK: - Deleted Section
    
    @State private var showDeletePermanentConfirmation = false
    
    private var deletedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Deleted Reward History")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            if viewModel.isLoadingDeleted && viewModel.deletedRewards.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding()
                    Spacer()
                }
            } else if viewModel.deletedRewards.isEmpty {
                Text("No deleted rewards")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                HStack(spacing: 12) {
                    Button(action: {
                        if viewModel.selectedDeletedIds.count == viewModel.deletedRewards.count {
                            viewModel.deselectAllDeleted()
                        } else {
                            viewModel.selectAllDeleted()
                        }
                    }) {
                        Text(viewModel.selectedDeletedIds.count == viewModel.deletedRewards.count ? "Deselect All" : "Select All")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    
                    if !viewModel.selectedDeletedIds.isEmpty {
                        Button(action: { showDeletePermanentConfirmation = true }) {
                            HStack(spacing: 4) {
                                if viewModel.isPermanentlyDeleting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "trash.fill")
                                        .font(.subheadline)
                                }
                                Text("Delete \(viewModel.selectedDeletedIds.count) Permanently")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.isPermanentlyDeleting)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.deletedRewards) { reward in
                        RewardHistoryRow(
                            reward: reward,
                            isSelectable: true,
                            isSelected: viewModel.selectedDeletedIds.contains(reward.id),
                            onToggleSelection: { viewModel.toggleDeletedSelection(id: reward.id) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .alert("Delete Permanently?", isPresented: $showDeletePermanentConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await viewModel.permanentlyDeleteSelected() }
            }
        } message: {
            Text("This will permanently remove \(viewModel.selectedDeletedIds.count) reward(s) from history. This cannot be undone.")
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading rewards...")
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
                Task { await viewModel.refresh() }
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
            Image(systemName: "gift")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(emptyStateMessage)
                .font(.headline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var emptyStateMessage: String {
        switch viewModel.selectedTimePeriod {
        case .thisMonth:
            return "No rewards redeemed this month"
        case .thisYear:
            return "No rewards redeemed this year"
        case .allTime:
            return "No rewards redeemed"
        }
    }
    
    // MARK: - Helper
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

// MARK: - Reward History Row

struct RewardHistoryRow: View {
    let reward: RewardHistoryItem
    var onDelete: (() -> Void)? = nil
    var isSelectable: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelectable {
                Button(action: { onToggleSelection?() }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // User info
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                        
                        Text(reward.userFirstName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Points
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("\(reward.pointsRequired)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    // Delete button (main list only)
                    if onDelete != nil {
                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            
            // Reward details
            VStack(alignment: .leading, spacing: 6) {
                Text(reward.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                if reward.displayName != reward.rewardTitle {
                    Text(reward.rewardTitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
                // Date
                if let usedAt = reward.usedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(formatDate(usedAt))
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
        .alert("Remove from Overview?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("This reward will be moved to Deleted Reward History. You can permanently delete it from there.")
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        return dateString
    }
}
