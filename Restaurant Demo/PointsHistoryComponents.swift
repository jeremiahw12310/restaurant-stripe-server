import SwiftUI

// MARK: - Points History Summary Card
struct PointsHistorySummaryCard: View {
    let summary: PointsHistorySummary
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("Points Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Stats Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // Total Earned
                VStack(spacing: 4) {
                    Text(summary.formattedTotalEarned)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("Earned")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
                
                // Total Spent
                VStack(spacing: 4) {
                    Text(summary.formattedTotalSpent)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Spent")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                )
                
                // Net Points
                VStack(spacing: 4) {
                    Text(summary.formattedNetPoints)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(summary.netPoints >= 0 ? .blue : .orange)
                    
                    Text("Net")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((summary.netPoints >= 0 ? Color.blue : Color.orange).opacity(0.1))
                )
            }
            
            // Transaction Count
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.white.opacity(0.7))
                
                Text("\(summary.transactionCount) transactions")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                if let lastDate = summary.lastTransactionDate {
                    Text("Last: \(lastDate, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.2, blue: 0.25),
                            Color(red: 0.15, green: 0.15, blue: 0.2)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Timeline Transaction Row (Modern)
struct TransactionCard: View {
    let transaction: PointsTransaction
    @Environment(\..colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 44, height: 44)
                
                Image(systemName: transaction.effectiveType.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(iconForeground)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(transaction.effectiveType.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Spacer()
                    AmountPill(text: transaction.formattedAmount, isEarned: transaction.isEarned)
                }
                
                if !transaction.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(transaction.description)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(secondaryText)
                        .lineLimit(2)
                }
                
                // Meta row
                HStack(spacing: 8) {
                    MetadataChip(icon: "clock.fill", text: transaction.relativeDate)
                    if let chips = metadataChips(prefix: 2), !chips.isEmpty {
                        ForEach(chips, id: \.self) { chip in
                            MetadataChip(icon: chip.icon, text: chip.text)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor, lineWidth: 1.2)
                )
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
        )
    }
    
    private var iconForeground: Color {
        switch transaction.effectiveType.color {
        case "green": return .green
        case "blue": return .blue
        case "red": return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "orange": return .orange
        default: return .white
        }
    }
    
    private var iconBackground: LinearGradient {
        let base: Color = iconForeground
        return LinearGradient(
            gradient: Gradient(colors: [base.opacity(0.22), base.opacity(0.08)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var primaryText: Color {
        colorScheme == .dark ? Color.white : Theme.modernPrimary
    }
    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.75) : Theme.modernSecondary
    }
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.06)
    }

    private struct Chip: Hashable {
        let icon: String
        let text: String
    }

    private func metadataChips(prefix: Int) -> [Chip]? {
        guard let metadata = transaction.metadata else { return nil }
        var result: [Chip] = []
        
        // Backend fields to exclude from user-facing display
        let backendFields: Set<String> = [
            "referralId",
            "role",
            "orderNumber",
            "orderDate",
            "orderTime",
            "referredUserId",
            "giftedRewardId",
            "adminId",
            "redemptionCode"
        ]
        
        // Admin adjustment: previousPoints → newPoints
        var previousPointsValue: Int?
        var newPointsValue: Int?
        if let prev = metadata["previousPoints"] as? Int { previousPointsValue = prev }
        else if let prevD = metadata["previousPoints"] as? Double { previousPointsValue = Int(prevD) }
        if let newp = metadata["newPoints"] as? Int { newPointsValue = newp }
        else if let newD = metadata["newPoints"] as? Double { newPointsValue = Int(newD) }
        if let prev = previousPointsValue, let new = newPointsValue {
            result.append(Chip(icon: "arrow.left.arrow.right", text: "\(prev) → \(new)"))
        }
        // Known user-facing keys first
        if let total = metadata["receiptTotal"] as? Double {
            result.append(Chip(icon: "dollarsign", text: String(format: "$%.2f", total)))
        }
        if let rewardTitle = metadata["rewardTitle"] as? String {
            result.append(Chip(icon: "gift.fill", text: rewardTitle))
        }
        // Fallback to any other keys (stringifiable), excluding backend fields
        if result.count < prefix {
            for key in metadata.keys.sorted() where !backendFields.contains(key) && key != "receiptTotal" && key != "rewardTitle" && key != "previousPoints" && key != "newPoints" {
                if let value = metadata[key] {
                    let text = "\(key): \(String(describing: value))"
                    result.append(Chip(icon: "info.circle", text: text))
                }
                if result.count >= prefix { break }
            }
        }
        return Array(result.prefix(prefix))
    }
}

// MARK: - Amount Pill
private struct AmountPill: View {
    let text: String
    let isEarned: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isEarned ? Theme.energyGreen : Color.red)
            )
            .shadow(color: (isEarned ? Theme.energyGreen : Color.red).opacity(0.3), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Metadata Chip
private struct MetadataChip: View {
    let icon: String
    let text: String
    @Environment(\..colorScheme) var colorScheme
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Theme.modernPrimary.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Filter Pills
struct PointsHistoryFilterPills: View {
    @Binding var selectedFilter: PointsTransactionType?
    let availableFilters: [PointsTransactionType]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All transactions filter
                FilterPill(
                    title: "All",
                    isSelected: selectedFilter == nil,
                    color: .blue
                ) {
                    selectedFilter = nil
                }
                
                // Type-specific filters
                ForEach(availableFilters, id: \.self) { filter in
                    FilterPill(
                        title: filter.displayName,
                        isSelected: selectedFilter == filter,
                        color: filterColor(for: filter)
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func filterColor(for filter: PointsTransactionType) -> Color {
        switch filter.color {
        case "green": return .green
        case "blue": return .blue
        case "red": return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    @Environment(\..colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : (colorScheme == .dark ? Color.white.opacity(0.7) : Theme.modernPrimary))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? color : (colorScheme == .dark ? Color.clear : Color.black.opacity(0.03)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? color : (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.08)), lineWidth: 1)
                )
        }
    }
}

// MARK: - Empty State
struct PointsHistoryEmptyState: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.5))
            
            Text(message)
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Text("Your points history will appear here once you earn or spend points.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Loading State
struct PointsHistoryLoadingState: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            
            Text("Loading points history...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State
struct PointsHistoryErrorState: View {
    let errorMessage: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Error Loading History")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            Button(action: retryAction) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue)
                )
            }
        }
        .padding()
    }
} 