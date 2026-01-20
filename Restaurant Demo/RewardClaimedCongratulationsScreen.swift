import SwiftUI

// MARK: - Reward Claimed Congratulations Screen
struct RewardClaimedCongratulationsScreen: View {
    let onDone: () -> Void
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.0, green: 0.6, blue: 0.3),
                    Color(red: 0.0, green: 0.5, blue: 0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                
                Text("Congratulations!")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .whiteTextShadow()
                
                Text("Your reward has been successfully claimed.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal)
                
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .whiteTextShadow()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .padding(.horizontal, 40)
            }
        }
    }
}

#Preview {
    RewardClaimedCongratulationsScreen(onDone: {})
}