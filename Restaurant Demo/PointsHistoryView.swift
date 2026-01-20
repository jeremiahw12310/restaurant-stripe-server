import SwiftUI

struct PointsHistoryView: View {
    @StateObject private var viewModel = PointsHistoryViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient (Unified with Home/Chatbot)
                LinearGradient(
                    gradient: Gradient(colors: [
                        Theme.modernBackground,
                        Theme.modernCardSecondary,
                        Theme.modernBackground
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Content
                    if viewModel.isLoading {
                        PointsHistoryLoadingState()
                    } else if let errorMessage = viewModel.errorMessage {
                        PointsHistoryErrorState(
                            errorMessage: errorMessage,
                            retryAction: { viewModel.refresh() }
                        )
                    } else if viewModel.transactions.isEmpty {
                        PointsHistoryEmptyState(message: "No Points History")
                    } else {
                        contentView
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.loadTransactions()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 12) {
            // Navigation header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(headerTint)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("Points History")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(headerTitle)
                    
                    Text("Track your points journey")
                        .font(.caption)
                        .foregroundColor(subtitleColor)
                }
                
                Spacer()
                
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(headerTint)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal)
            
            // Filter pills
            if !viewModel.availableFilters.isEmpty {
                PointsHistoryFilterPills(
                    selectedFilter: $viewModel.selectedFilter,
                    availableFilters: viewModel.availableFilters
                )
                .padding(.vertical, 8)
            }
        }
        .padding(.top)
    }
    
    // MARK: - Content View
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(viewModel.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        // Section Header
                        HStack(spacing: 10) {
                            Text(section.title.uppercased())
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.darkGoldGradient)
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                                .cornerRadius(1)
                        }
                        .padding(.horizontal)
                        
                        // Rows
                        VStack(spacing: 12) {
                            ForEach(section.transactions) { transaction in
                                TransactionCard(transaction: transaction)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Load More button at the bottom when more transactions are available
                if viewModel.hasMoreTransactions {
                    Button(action: {
                        viewModel.loadMoreTransactions()
                    }) {
                        HStack(spacing: 8) {
                            Text("Load more")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [Theme.energyBlue, Theme.energyBlue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .shadow(color: Theme.cardShadow, radius: 6, x: 0, y: 3)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            viewModel.refresh()
        }
    }
}

private extension PointsHistoryView {
    var headerTint: Color { colorScheme == .dark ? .white : Theme.modernPrimary }
    var headerTitle: Color { colorScheme == .dark ? .white : Theme.modernPrimary }
    var subtitleColor: Color { colorScheme == .dark ? Color.white.opacity(0.7) : Theme.modernSecondary }
}

// MARK: - Preview
struct PointsHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        PointsHistoryView()
    }
} 