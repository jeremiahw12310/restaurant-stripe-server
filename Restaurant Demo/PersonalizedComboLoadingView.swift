import SwiftUI

struct PersonalizedComboLoadingView: View {
    @State private var animationOffset1: CGFloat = 0
    @State private var animationOffset2: CGFloat = 0
    @State private var animationOffset3: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Hero logo at the top
                Image("newhero")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(color: .white.opacity(0.2), radius: 20, x: 0, y: 10)
                
                // Loading text
                VStack(spacing: 16) {
                    Text("Dumpling Hero is building")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("your personalized combo")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                
                // Dumpling emojis animation
                HStack(spacing: 20) {
                    Text("🥟")
                        .font(.system(size: 40))
                        .offset(y: animationOffset1)
                        .animation(
                            Animation.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                                .delay(0.0),
                            value: animationOffset1
                        )
                    
                    Text("🥟")
                        .font(.system(size: 40))
                        .offset(y: animationOffset2)
                        .animation(
                            Animation.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                                .delay(0.3),
                            value: animationOffset2
                        )
                    
                    Text("🥟")
                        .font(.system(size: 40))
                        .offset(y: animationOffset3)
                        .animation(
                            Animation.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                                .delay(0.6),
                            value: animationOffset3
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            // Start the bobbing animation
            animationOffset1 = -20
            animationOffset2 = -20
            animationOffset3 = -20
        }
    }
}

#Preview {
    PersonalizedComboLoadingView()
} 
