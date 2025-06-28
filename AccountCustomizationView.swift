import SwiftUI
import FirebaseFirestore

struct AccountCustomizationView: View {
    let uid: String
    // We use @EnvironmentObject to receive the ViewModel from the parent view.
    // This is more stable than creating a new instance here.
    @EnvironmentObject var authVM: AuthenticationViewModel
    
    @State private var selectedEmoji: String = "🥟"
    @State private var selectedColor: Color = .red
    @State private var showWelcomeScreen = false

    let emojis = ["🥟", "🧋", "🍜", "🍣", "🍰"]
    let colorOptions: [(Color, String)] = [
        (.red, "red"), (.blue, "blue"), (.green, "green"),
        (.purple, "purple"), (.pink, "pink"), (.orange, "orange")
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Text("Customize Your Avatar")
                    .font(.largeTitle).bold()
                    .padding(.top)

                // The avatar preview
                ZStack {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 150, height: 150)
                        .shadow(radius: 5)
                    Text(selectedEmoji)
                        .font(.system(size: 80)) // Sized to fit nicely in the circle.
                }
                .padding(.vertical, 20)

                // ScrollView contains the customization options.
                ScrollView {
                    VStack(spacing: 24) {
                        // Emoji selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose an Avatar:").bold()
                            HStack(spacing: 15) {
                                ForEach(emojis, id: \.self) { emoji in
                                    Text(emoji)
                                        .font(.largeTitle)
                                        .padding(10)
                                        .background(selectedEmoji == emoji ? Color.gray.opacity(0.3) : Color.clear)
                                        .cornerRadius(8)
                                        .onTapGesture { selectedEmoji = emoji }
                                }
                            }
                        }

                        // Color selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose a Color:").bold()
                            HStack(spacing: 15) {
                                ForEach(colorOptions, id: \.1) { color, _ in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle().stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                                        )
                                        .onTapGesture { selectedColor = color }
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Action buttons are outside the ScrollView so they are always visible.
                VStack(spacing: 15) {
                    Button("Finish") { saveCustomization() }
                        .buttonStyle(PrimaryButtonStyle(backgroundColor: .green))
                    
                    Button("Skip For Now") { showWelcomeAndLogin() }
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // The welcome overlay that appears after finishing.
            if showWelcomeScreen {
                Color.black.opacity(0.85).ignoresSafeArea().transition(.opacity)
                VStack {
                    Text("Welcome to\nDumpling House Rewards!")
                        .foregroundColor(.white).font(.largeTitle).bold()
                        .multilineTextAlignment(.center)
                        .scaleEffect(showWelcomeScreen ? 1 : 0.8)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut, value: showWelcomeScreen)
    }

    func saveCustomization() {
        let db = Firestore.firestore()
        let colorName = colorOptions.first(where: { $0.0 == selectedColor })?.1 ?? "red"
        
        db.collection("users").document(uid).updateData([
            "avatarEmoji": selectedEmoji,
            "avatarColor": colorName
        ]) { _ in
            // After saving, trigger the welcome animation and log in.
            showWelcomeAndLogin()
        }
    }

    func showWelcomeAndLogin() {
        showWelcomeScreen = true
        // After showing the welcome message for a moment, we trigger the final login state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            authVM.didAuthenticate = true
        }
    }
}
