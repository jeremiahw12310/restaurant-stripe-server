import SwiftUI

// MARK: - Reward Expired Screen
struct RewardExpiredScreen: View {
    let onDone: () -> Void
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.5, green: 0.0, blue: 0.0),
                    Color(red: 0.3, green: 0.0, blue: 0.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "xmark.octagon.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                
                Text("Time Expired")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .whiteTextShadow()
                
                Text("You exceeded the 15-minute limit to claim this reward.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal)
                
                Button(action: onDone) {
                    Text("Back to Rewards")
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
    RewardExpiredScreen(onDone: {})
}