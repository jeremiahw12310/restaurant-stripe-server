import Foundation

enum ReceiptScanOutcome: Equatable {
    case success(points: Int, total: Double)
    case duplicate(orderNumber: String?, date: String?)
    case notFromRestaurant
    case unreadable
    case tooOld(date: String?)
    case mismatch
    case network
    case server
    case suspicious
}

// Combo generation state for success screen
enum ComboGenerationState: Equatable {
    case loading
    case failed
    case ready
}
















