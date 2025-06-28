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
            // Beautiful gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 1.0, green: 0.98, blue: 0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Beautiful header
                headerView
                
                // The beautiful avatar preview
                avatarPreviewView
                
                // ScrollView contains the customization options.
                ScrollView {
                    VStack(spacing: 20) {
                        // Emoji selection with beautiful cards
                        emojiSelectionView
                        
                        // Color selection with beautiful circles
                        colorSelectionView
                    }
                }

                Spacer()

                // Beautiful action buttons
                actionButtonsView
            }

            // The beautiful welcome overlay that appears after finishing.
            if showWelcomeScreen {
                welcomeOverlayView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showWelcomeScreen)
        .animation(.easeInOut(duration: 0.2), value: selectedEmoji)
        .animation(.easeInOut(duration: 0.2), value: selectedColor)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
            
            Text("Customize Your Avatar")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Make it uniquely yours")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.top, 10)
    }
    
    private var avatarPreviewView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [selectedColor, selectedColor.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: selectedColor.opacity(0.3), radius: 15, x: 0, y: 8)
            
            Text(selectedEmoji)
                .font(.system(size: 60))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
        .padding(.vertical, 10)
    }
    
    private var emojiSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose an Avatar")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                ForEach(emojis, id: \.self) { emoji in
                    emojiButton(for: emoji)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func emojiButton(for emoji: String) -> some View {
        Button(action: { selectedEmoji = emoji }) {
            Text(emoji)
                .font(.system(size: 40))
                .padding(16)
                .background(emojiBackground(for: emoji))
                .shadow(color: emojiShadowColor(for: emoji), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func emojiBackground(for emoji: String) -> some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(selectedEmoji == emoji ? AnyShapeStyle(selectedEmojiGradient) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selectedEmoji == emoji ? Color(red: 0.2, green: 0.6, blue: 0.9) : .clear, lineWidth: 2)
            )
    }
    
    private var selectedEmojiGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.2, green: 0.6, blue: 0.9),
                Color(red: 0.3, green: 0.7, blue: 1.0)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func emojiShadowColor(for emoji: String) -> Color {
        selectedEmoji == emoji ? Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3) : .black.opacity(0.05)
    }
    
    private var colorSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a Color")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            HStack(spacing: 15) {
                ForEach(colorOptions, id: \.1) { color, _ in
                    colorButton(for: color)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func colorButton(for color: Color) -> some View {
        Button(action: { selectedColor = color }) {
            ZStack {
                Circle()
                    .fill(colorGradient(for: color))
                    .frame(width: 50, height: 50)
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
                
                if selectedColor == color {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func colorGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [color, color.opacity(0.8)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            Button("Finish & Continue") { 
                saveCustomization() 
            }
            .buttonStyle(PrimaryButtonStyle(backgroundColor: .green))
            .padding(.horizontal, 20)
            
            Button("Skip For Now") { 
                showWelcomeAndLogin() 
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
    
    private var welcomeOverlayView: some View {
        ZStack {
            // Beautiful blur background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .transition(.opacity)
            
            VStack(spacing: 30) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text("Welcome to\nDumpling House Rewards!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Text("Your account is ready!")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .scaleEffect(showWelcomeScreen ? 1 : 0.8)
            .transition(.opacity.combined(with: .scale))
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            authVM.didAuthenticate = true
        }
    }
}
