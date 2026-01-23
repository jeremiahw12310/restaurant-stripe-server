import SwiftUI
import Firebase
import FirebaseFirestore

/// Shows reward details after scanning a redemption code and lets an employee confirm usage.
struct RewardVerificationView: View {
    let code: String
    
    @State private var isLoading = true
    @State private var errorMessage: String = ""
    @State private var redeemedReward: RedeemedReward?
    @State private var userName: String = ""
    @State private var isConfirming = false
    @State private var confirmed = false
    
    var body: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView("Loading reward details…")
            } else if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else if confirmed {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.green)
                    Text("Reward confirmed!")
                        .font(.title2.bold())
                }
            } else if let reward = redeemedReward {
                VStack(spacing: 16) {
                    Text("Reward for \(userName)")
                        .font(.title3.bold())
                    Text(reward.rewardTitle)
                        .font(.title2)
                    Text("Expires in: \(timeRemaining(until: reward.expiresAt))")
                        .foregroundColor(.secondary)
                    
                    Button(action: confirmReward) {
                        if isConfirming {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                        } else {
                            Text("Confirm Reward")
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(Theme.primaryGold)
                                        .shadow(color: Theme.primaryGold.opacity(0.3), radius: 8, x: 0, y: 4)
                                )
                        }
                    }
                    .disabled(isConfirming)
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Verify Reward")
        .task {
            await loadRewardDetails()
        }
    }
    
    // MARK: - Helper
    private func timeRemaining(until date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "Expired" }
        let minutes = Int(remaining / 60)
        let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
        return String(format: "%02dm %02ds", minutes, seconds)
    }
    
    // MARK: - Firestore
    @MainActor
    private func loadRewardDetails() async {
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("redeemedRewards")
                .whereField("redemptionCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()
            guard let document = snapshot.documents.first, let reward = RedeemedReward(document: document) else {
                errorMessage = "No active reward found for code."
                isLoading = false
                return
            }
            // Check if already used
            if reward.isUsed {
                errorMessage = "Reward has already been used.";
                isLoading = false; return
            }
            redeemedReward = reward
            // Fetch user name
            let userDoc = try await db.collection("users").document(reward.userId).getDocument()
            if let data = userDoc.data(), let firstName = data["firstName"] as? String {
                userName = firstName
            } else {
                userName = "User"
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func confirmReward() {
        guard let reward = redeemedReward else { return }
        isConfirming = true
        let db = Firestore.firestore()
        // Set both isUsed and usedAt to ensure data consistency
        // usedAt is required for accurate admin stats and history queries
        db.collection("redeemedRewards").document(reward.id).updateData([
            "isUsed": true,
            "usedAt": FieldValue.serverTimestamp()
        ]) { error in
            DispatchQueue.main.async {
                isConfirming = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    confirmed = true
                }
            }
        }
    }
}

#Preview {
    RewardVerificationView(code: "ABCDEFGH")
}
