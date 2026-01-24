import SwiftUI

struct AdminSuspiciousFlagsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminSuspiciousFlagsViewModel()
    @State private var selectedFlag: SuspiciousFlag?
    @State private var showFlagDetail: Bool = false
    
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
                        
                        // Filters
                        filtersSection
                        
                        // Content
                        if viewModel.isLoading && viewModel.flags.isEmpty {
                            loadingView
                        } else if let error = viewModel.errorMessage {
                            errorView(message: error)
                        } else if viewModel.flags.isEmpty {
                            emptyStateView
                        } else {
                            flagsList
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.loadFlags()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                Task {
                    await viewModel.loadFlags()
                }
            }
            .sheet(item: $selectedFlag) { flag in
                SuspiciousFlagDetailView(flag: flag, viewModel: viewModel)
            }
            .alert("Success", isPresented: $viewModel.showReviewSuccess) {
                Button("OK") {
                    selectedFlag = nil
                }
            } message: {
                Text("Flag reviewed successfully")
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
                
                Text("Suspicious Activity")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await viewModel.loadFlags()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            // Subtitle
            Text("Review flagged accounts for suspicious behavior")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Filters
    
    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            HStack(spacing: 12) {
                // Status filter
                Menu {
                    Button("All") {
                        viewModel.selectedStatus = nil
                        Task { await viewModel.loadFlags() }
                    }
                    Button("Pending") {
                        viewModel.selectedStatus = "pending"
                        Task { await viewModel.loadFlags() }
                    }
                    Button("Reviewed") {
                        viewModel.selectedStatus = "reviewed"
                        Task { await viewModel.loadFlags() }
                    }
                    Button("Dismissed") {
                        viewModel.selectedStatus = "dismissed"
                        Task { await viewModel.loadFlags() }
                    }
                } label: {
                    HStack {
                        Text(viewModel.selectedStatus?.capitalized ?? "All Status")
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(8)
                }
                
                // Severity filter
                Menu {
                    Button("All") {
                        viewModel.selectedSeverity = nil
                        Task { await viewModel.loadFlags() }
                    }
                    Button("Critical") {
                        viewModel.selectedSeverity = "critical"
                        Task { await viewModel.loadFlags() }
                    }
                    Button("High") {
                        viewModel.selectedSeverity = "high"
                        Task { await viewModel.loadFlags() }
                    }
                    Button("Medium") {
                        viewModel.selectedSeverity = "medium"
                        Task { await viewModel.loadFlags() }
                    }
                    Button("Low") {
                        viewModel.selectedSeverity = "low"
                        Task { await viewModel.loadFlags() }
                    }
                } label: {
                    HStack {
                        Text(viewModel.selectedSeverity?.capitalized ?? "All Severity")
                            .font(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Flags List
    
    private var flagsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(viewModel.flags.count) flag\(viewModel.flags.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.flags.enumerated()), id: \.element.id) { index, flag in
                    SuspiciousFlagRow(flag: flag)
                        .onTapGesture {
                            selectedFlag = flag
                        }
                        .onAppear {
                            // Load more when approaching the end
                            if index == viewModel.flags.count - 3 {
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
            Text("Loading suspicious flags...")
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
                    await viewModel.loadFlags()
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
            
            Text("No suspicious flags")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("All accounts are currently clean")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Flag Row

struct SuspiciousFlagRow: View {
    let flag: SuspiciousFlag
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Severity badge
                severityBadge
                
                Spacer()
                
                // Status badge
                statusBadge
            }
            
            // Description
            Text(flag.description)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            // User info
            if let userInfo = flag.userInfo {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(userInfo.phone)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(userInfo.firstName) \(userInfo.lastName)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("\(userInfo.points) pts")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            // Metadata
            HStack {
                Text(flag.flagType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                
                Spacer()
                
                if let createdAt = flag.createdAt {
                    Text(formatDateShort(createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    private var severityBadge: some View {
        let (color, text) = severityColor(flag.severity)
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }
    
    private var statusBadge: some View {
        let (color, text) = statusColor(flag.status)
        return Text(text.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .cornerRadius(4)
    }
    
    private func severityColor(_ severity: String) -> (Color, String) {
        switch severity.lowercased() {
        case "critical": return (.red, "CRITICAL")
        case "high": return (.orange, "HIGH")
        case "medium": return (.yellow, "MEDIUM")
        case "low": return (.blue, "LOW")
        default: return (.gray, severity.uppercased())
        }
    }
    
    private func statusColor(_ status: String) -> (Color, String) {
        switch status.lowercased() {
        case "pending": return (.orange, status)
        case "reviewed": return (.blue, status)
        case "dismissed": return (.green, status)
        case "action_taken": return (.red, "Action Taken")
        default: return (.gray, status)
        }
    }
    
    private func formatDateShort(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        
        return dateString
    }
}

// MARK: - Flag Detail View

struct SuspiciousFlagDetailView: View {
    let flag: SuspiciousFlag
    @ObservedObject var viewModel: AdminSuspiciousFlagsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAction: String?
    @State private var reviewNotes: String = ""
    @State private var showActionConfirmation: Bool = false
    
    // Helper to convert evidence to JSON string
    private var evidenceJSONString: String? {
        let evidenceDict = flag.evidence.mapValues { $0.value }
        guard let evidenceData = try? JSONSerialization.data(withJSONObject: evidenceDict, options: .prettyPrinted),
              let evidenceString = String(data: evidenceData, encoding: .utf8) else {
            return nil
        }
        return evidenceString
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header info
                    headerSection
                    
                    // User info
                    if let userInfo = flag.userInfo {
                        userInfoSection(userInfo)
                    }
                    
                    // Evidence
                    evidenceSection
                    
                    // Review actions
                    if flag.status == "pending" {
                        reviewSection
                    } else {
                        reviewHistorySection
                    }
                }
                .padding(20)
            }
            .navigationTitle("Flag Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Confirm Action", isPresented: $showActionConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm", role: .destructive) {
                    if let action = selectedAction {
                        Task {
                            await viewModel.reviewFlag(
                                flagId: flag.id,
                                action: action,
                                notes: reviewNotes.isEmpty ? nil : reviewNotes
                            )
                            dismiss()
                        }
                    }
                }
            } message: {
                if let action = selectedAction {
                    Text("Are you sure you want to \(action) this flag?")
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                severityBadge
                Spacer()
                statusBadge
            }
            
            Text(flag.description)
                .font(.title3)
                .fontWeight(.bold)
            
            HStack {
                Text("Type: \(flag.flagType.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Risk Score: \(flag.riskScore)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(riskScoreColor(flag.riskScore))
            }
            
            if let createdAt = flag.createdAt {
                Text("Flagged: \(viewModel.formatDate(createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private func userInfoSection(_ userInfo: SuspiciousFlag.UserInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("User Information")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(userInfo.firstName) \(userInfo.lastName)")
                        .font(.subheadline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Points")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(userInfo.points)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Phone")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(userInfo.phone)
                    .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Email")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(userInfo.email)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evidence")
                .font(.headline)
            
            // Display evidence as JSON string
            if let evidenceString = evidenceJSONString {
                ScrollView {
                    Text(evidenceString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("No evidence data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Action")
                .font(.headline)
            
            TextField("Review notes (optional)", text: $reviewNotes, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            VStack(spacing: 12) {
                actionButton(title: "Dismiss", color: .green, action: "dismiss")
                actionButton(title: "Watch", color: .blue, action: "watch")
                actionButton(title: "Restrict", color: .orange, action: "restrict")
                actionButton(title: "Ban", color: .red, action: "ban")
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private func actionButton(title: String, color: Color, action: String) -> some View {
        Button {
            selectedAction = action
            showActionConfirmation = true
        } label: {
            HStack {
                Spacer()
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .foregroundColor(.white)
            .padding()
            .background(color)
            .cornerRadius(8)
        }
        .disabled(viewModel.isReviewing)
    }
    
    private var reviewHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review History")
                .font(.headline)
            
            if let reviewedAt = flag.reviewedAt {
                Text("Reviewed: \(viewModel.formatDate(reviewedAt))")
                    .font(.subheadline)
            }
            
            if let actionTaken = flag.actionTaken {
                Text("Action: \(actionTaken.capitalized)")
                    .font(.subheadline)
            }
            
            if let notes = flag.reviewNotes {
                Text("Notes: \(notes)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private var severityBadge: some View {
        let (color, text) = severityColor(flag.severity)
        return Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color)
            .cornerRadius(6)
    }
    
    private var statusBadge: some View {
        let (color, text) = statusColor(flag.status)
        return Text(text.capitalized)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1))
            .cornerRadius(6)
    }
    
    private func severityColor(_ severity: String) -> (Color, String) {
        switch severity.lowercased() {
        case "critical": return (.red, "CRITICAL")
        case "high": return (.orange, "HIGH")
        case "medium": return (.yellow, "MEDIUM")
        case "low": return (.blue, "LOW")
        default: return (.gray, severity.uppercased())
        }
    }
    
    private func statusColor(_ status: String) -> (Color, String) {
        switch status.lowercased() {
        case "pending": return (.orange, status)
        case "reviewed": return (.blue, status)
        case "dismissed": return (.green, status)
        case "action_taken": return (.red, "Action Taken")
        default: return (.gray, status)
        }
    }
    
    private func riskScoreColor(_ score: Int) -> Color {
        if score >= 81 { return .red }
        if score >= 61 { return .orange }
        if score >= 31 { return .yellow }
        return .green
    }
}
