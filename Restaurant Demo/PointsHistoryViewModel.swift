import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

class PointsHistoryViewModel: ObservableObject {
    @Published var transactions: [PointsTransaction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: PointsTransactionType? = nil
    @Published var summary: PointsHistorySummary?
    @Published var visibleLimit: Int = 25
    
    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 25
    
    // MARK: - Computed Properties
    private var allFilteredSortedTransactions: [PointsTransaction] {
        if let filter = selectedFilter {
            return transactions
                .filter { $0.effectiveType == filter }
                .sorted { $0.timestamp > $1.timestamp }
        } else {
            return transactions.sorted { $0.timestamp > $1.timestamp }
        }
    }

    var filteredTransactions: [PointsTransaction] {
        Array(allFilteredSortedTransactions.prefix(visibleLimit))
    }
    
    var availableFilters: [PointsTransactionType] {
        let types = Set(transactions.map { $0.effectiveType })
        return Array(types).sorted { $0.displayName < $1.displayName }
    }

    var hasMoreTransactions: Bool {
        allFilteredSortedTransactions.count > visibleLimit
    }
    
    // MARK: - Grouped Sections (Today / This Week / Earlier)
    struct TransactionSection: Identifiable {
        let id: String
        let title: String
        let transactions: [PointsTransaction]
    }
    
    var sections: [TransactionSection] {
        let calendar = Calendar.current
        let now = Date()
        var today: [PointsTransaction] = []
        var thisWeek: [PointsTransaction] = []
        var earlier: [PointsTransaction] = []
        
        for tx in filteredTransactions {
            if calendar.isDate(tx.timestamp, inSameDayAs: now) {
                today.append(tx)
            } else if calendar.isDate(tx.timestamp, equalTo: now, toGranularity: .weekOfYear) {
                thisWeek.append(tx)
            } else {
                earlier.append(tx)
            }
        }
        var result: [TransactionSection] = []
        if !today.isEmpty {
            result.append(TransactionSection(id: "today", title: "Today", transactions: today))
        }
        if !thisWeek.isEmpty {
            result.append(TransactionSection(id: "thisWeek", title: "This Week", transactions: thisWeek))
        }
        if !earlier.isEmpty {
            result.append(TransactionSection(id: "earlier", title: "Earlier", transactions: earlier))
        }
        return result
    }
    
    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    deinit {
        removeListener()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Update summary when transactions change
        $transactions
            .sink { [weak self] transactions in
                self?.updateSummary(from: transactions)
                self?.resetPagination()
            }
            .store(in: &cancellables)

        // Reset pagination when filter changes
        $selectedFilter
            .sink { [weak self] _ in
                self?.resetPagination()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func loadTransactions() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        removeListener()
        
        // Query without orderBy to avoid composite index requirement
        // We'll sort the results in memory instead
        listenerRegistration = db.collection("pointsTransactions")
            .whereField("userId", isEqualTo: userId)
            .limit(to: 100) // Limit to last 100 transactions for performance
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = "Error loading transactions: \(error.localizedDescription)"
                        print("❌ Error loading points transactions: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self?.transactions = []
                        return
                    }
                    
                    let newTransactions = documents.compactMap { document -> PointsTransaction? in
                        let data = document.data()
                        return PointsTransaction.fromFirestore(document)
                    }
                    
                    // Sort transactions by timestamp in descending order (most recent first)
                    let sortedTransactions = newTransactions.sorted { $0.timestamp > $1.timestamp }
                    self?.transactions = sortedTransactions
                    print("✅ Loaded \(newTransactions.count) points transactions")
                }
            }
    }
    
    func clearFilter() {
        selectedFilter = nil
    }
    
    func setFilter(_ filter: PointsTransactionType?) {
        selectedFilter = filter
    }
    
    func refresh() {
        loadTransactions()
    }
    
    // MARK: - Private Methods
    private func resetPagination() {
        visibleLimit = pageSize
    }

    private func updateSummary(from transactions: [PointsTransaction]) {
        let totalEarned = transactions.filter { $0.isEarned }.reduce(0) { $0 + $1.amount }
        let totalSpent = abs(transactions.filter { $0.isSpent }.reduce(0) { $0 + $1.amount })
        let currentBalance = totalEarned - totalSpent
        let transactionCount = transactions.count
        let lastTransactionDate = transactions.first?.timestamp
        
        summary = PointsHistorySummary(
            totalEarned: totalEarned,
            totalSpent: totalSpent,
            currentBalance: currentBalance,
            transactionCount: transactionCount,
            lastTransactionDate: lastTransactionDate
        )
    }
    
    private func removeListener() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    func loadMoreTransactions() {
        let total = allFilteredSortedTransactions.count
        guard visibleLimit < total else { return }
        visibleLimit = min(visibleLimit + pageSize, total)
    }
} 