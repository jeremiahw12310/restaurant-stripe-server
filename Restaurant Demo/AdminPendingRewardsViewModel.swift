import Foundation
import FirebaseFirestore

/// Listens for the newest pending (un-used, un-expired) reward redemption so staff can react immediately.
@MainActor
final class AdminPendingRewardsViewModel: ObservableObject {
    @Published var pendingReward: RedeemedReward?
    @Published var lastError: String?

    // Listener can be torn down from `deinit` (which is nonisolated), so store it as nonisolated.
    private nonisolated(unsafe) var listener: ListenerRegistration?
    private var isEnabled: Bool = false

    deinit {
        // `deinit` is nonisolated; don't touch @MainActor state here.
        listener?.remove()
    }

    func setListeningEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
    }

    func start() {
        stop()
        lastError = nil

        let db = Firestore.firestore()
        listener = db.collection("redeemedRewards")
            .whereField("isUsed", isEqualTo: false)
            .whereField("isExpired", isEqualTo: false)
            .order(by: "redeemedAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.pendingReward = nil
                    return
                }

                guard let doc = snapshot?.documents.first,
                      let reward = RedeemedReward(document: doc) else {
                    self.pendingReward = nil
                    return
                }

                // Ignore rewards that are already expired locally (extra safety)
                if reward.expiresAt <= Date() {
                    self.pendingReward = nil
                    return
                }

                self.pendingReward = reward
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        pendingReward = nil
    }
}

