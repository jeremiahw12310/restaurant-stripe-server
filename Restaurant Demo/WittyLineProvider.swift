import Foundation

final class WittyLineProvider {
    static let shared = WittyLineProvider()
    private init() {}

    func headline(for outcome: ReceiptScanOutcome) -> String {
        switch outcome {
        case .success:
            return pick([
                "You just leveled up.",
                "Points unlocked.",
                "Nice catch — rewards incoming.",
                "That scan slaps."
            ])
        case .duplicate:
            return pick([
                "Been there, scanned that.",
                "We've seen this one.",
                "Already cashed this receipt.",
                "Deja scan."
            ])
        case .notFromRestaurant:
            return pick([
                "Wrong house, friend.",
                "Tasty, but not our kitchen.",
                "Not a Dumpling House receipt."
            ])
        case .unreadable:
            return pick([
                "We squinted. Still fuzzy.",
                "Blurry vibes — try again.",
                "Help us help you: brighter shot."
            ])
        case .totalsNotVisible:
            return pick([
                "We need the totals section.",
                "Receipt text not fully visible.",
                "Bottom of the receipt, please."
            ])
        case .tooOld:
            return pick([
                "A little too retro.",
                "Outside the rewards window.",
                "Time-travel not supported (yet)."
            ])
        case .mismatch:
            return pick([
                "Something doesn't add up.",
                "Totals won't reconcile.",
                "Numbers are not vibing."
            ])
        case .network:
            return pick([
                "The line dropped.",
                "Network took a snack break.",
                "No bars for rewards (for now)."
            ])
        case .server:
            return pick([
                "Kitchen's a bit busy.",
                "Server needs a breather.",
                "We're cooking a fix."
            ])
        case .suspicious:
            return pick([
                "This one didn't go through.",
                "We can't process this receipt.",
                "This receipt can't be accepted right now."
            ])
        case .rateLimited:
            return pick([
                "Take a quick break.",
                "Slow down there, speedster.",
                "Hold up — try again in a bit."
            ])
        }
    }

    private func pick(_ options: [String]) -> String { options.randomElement() ?? options.first! }
}
