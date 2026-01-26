import Foundation

enum ReceiptScanOutcome: Equatable {
    case success(points: Int, total: Double)
    case duplicate(orderNumber: String?, date: String?)
    /// User hit the daily cap on point-earning receipt scans.
    case dailyLimitReached
    case notFromRestaurant
    case unreadable
    /// The subtotal/tax/total section is missing or not clearly visible.
    /// We fail closed to avoid hallucinated totals.
    case totalsNotVisible
    case tooOld(date: String?)
    case mismatch
    case network
    case server
    case suspicious
    case rateLimited
}

// Combo generation state for success screen
enum ComboGenerationState: Equatable {
    case loading
    case failed
    case ready
}
















