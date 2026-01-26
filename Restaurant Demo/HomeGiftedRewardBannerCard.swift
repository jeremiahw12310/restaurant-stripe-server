import SwiftUI

// MARK: - Home Gifted Reward Banner Card
/// Compact banner card shown in HomeView above the carousel when user has active gifted rewards
struct HomeGiftedRewardBannerCard: View {
    let gift: GiftedReward
    let additionalCount: Int
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                onTap()
            }
        }) {
            HStack(spacing: 12) {
                // Small icon/image on the left
                Group {
                    if let imageURL = gift.imageURL, !imageURL.isEmpty {
                        AsyncImage(url: URL(string: imageURL)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 50, height: 50)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            case .failure:
                                Image(systemName: "gift.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 50, height: 50)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if let imageName = gift.imageName, !imageName.isEmpty {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    } else {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 50, height: 50)
                    }
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    // "YOU HAVE A REWARD" header
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("YOU HAVE A REWARD")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white)
                    
                    // Gift title
                    Text(gift.rewardTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Count badge or chevron
                HStack(spacing: 8) {
                    if additionalCount > 0 {
                        Text("+\(additionalCount)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.3, blue: 0.5))
                            )
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.7, blue: 0.3),
                                Color(red: 1.0, green: 0.85, blue: 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color(red: 0.9, green: 0.7, blue: 0.3).opacity(0.4), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isPressed)
    }
}
