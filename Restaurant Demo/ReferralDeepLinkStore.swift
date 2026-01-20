import Foundation

/// Small helper to persist an incoming referral code so it isn't lost during navigation/login.
/// This enables:
/// - Universal Link or URL scheme opens app → code is stored immediately
/// - Signup flow can auto-fill the referral field
/// - Logged-in users can be routed to ReferralView with the code
enum ReferralDeepLinkStore {
    private static let pendingCodeKey = "pending_referral_code"
    
    static func setPending(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: pendingCodeKey)
    }
    
    static func getPending() -> String? {
        let code = (UserDefaults.standard.string(forKey: pendingCodeKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code.uppercased()
    }
    
    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingCodeKey)
    }
}







