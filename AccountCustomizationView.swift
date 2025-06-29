import SwiftUI
import FirebaseFirestore
import PhotosUI

struct AccountCustomizationView: View {
    let uid: String
    @EnvironmentObject var authVM: AuthenticationViewModel
    @StateObject private var userVM = UserViewModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedEmoji: String = "🥟"
    @State private var selectedColor: Color = .red
    @State private var showWelcomeScreen = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showPhotoCrop = false
    @State private var showPhotoPicker = false
    @State private var isFromOnboarding = false

    let emojis = ["🥟", "🧋", "🍜", "🍣", "🍰"]
    let colorOptions: [(Color, String)] = [
        (.red, "red"), (.blue, "blue"), (.green, "green"),
        (.purple, "purple"), (.pink, "pink"), (.orange, "orange")
    ]

    var body: some View {
        ZStack {
            // Adaptive background that works in both light and dark mode
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Beautiful header
                headerView
                
                // The beautiful avatar preview
                avatarPreviewView
                
                // ScrollView contains the customization options.
                ScrollView {
                    VStack(spacing: 20) {
                        // Photo selection option
                        photoSelectionView
                        
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
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    showPhotoCrop = true
                }
            }
        }
        .sheet(isPresented: $showPhotoCrop) {
            if let image = selectedImage {
                PhotoCropView(selectedImage: $selectedImage, onCropComplete: { croppedImage in
                    selectedImage = croppedImage
                    showPhotoCrop = false
                    
                    // Immediately upload the cropped photo
                    if let croppedImage = croppedImage {
                        print("📤 Uploading cropped photo immediately")
                        userVM.uploadProfilePhoto(croppedImage) { success in
                            DispatchQueue.main.async {
                                if success {
                                    print("✅ Photo uploaded successfully after cropping")
                                    selectedImage = nil // Clear local image so we use the latest from userVM
                                    // Force refresh the profile image to ensure UI updates
                                    userVM.forceRefreshProfileImage()
                                } else {
                                    print("❌ Failed to upload photo after cropping")
                                }
                            }
                        }
                    }
                })
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            // Always reload user data and image on appear
            isFromOnboarding = authVM.shouldNavigateToCustomization
            userVM.loadUserData()
            selectedImage = nil // Always clear local image so we use the latest from userVM
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            
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
            if let profileImage = selectedImage ?? userVM.profileImage {
                // Show profile photo
                Image(uiImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
            } else {
                // Show emoji avatar
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
        }
        .padding(.vertical, 10)
    }
    
    private var photoSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile Photo")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                // Add Photo Button
                Button(action: {
                    showPhotoPicker = true
                }) {
                    VStack(spacing: 8) {
                        if userVM.isUploadingPhoto {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.blue)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        Text(userVM.isUploadingPhoto ? "Uploading..." : "Add Photo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(.blue, lineWidth: 2)
                            )
                    )
                    .shadow(color: .blue.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(userVM.isUploadingPhoto)
                
                // Remove Photo Button (only show if photo exists)
                if selectedImage != nil || userVM.profileImage != nil {
                    Button(action: {
                        selectedImage = nil
                        userVM.removeProfilePhoto { _ in }
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.red)
                            Text("Remove")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 80, height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(.red, lineWidth: 2)
                                )
                        )
                        .shadow(color: .red.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(userVM.isUploadingPhoto)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
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
                    .stroke(selectedEmoji == emoji ? .blue : .clear, lineWidth: 2)
            )
    }
    
    private var selectedEmojiGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                .blue,
                .blue.opacity(0.8)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func emojiShadowColor(for emoji: String) -> Color {
        selectedEmoji == emoji ? .blue.opacity(0.3) : .black.opacity(0.05)
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
            
            if isFromOnboarding {
                Button("Skip For Now") { 
                    showWelcomeAndLogin() 
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 20)
            }
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
        
        // Save the avatar customization
        db.collection("users").document(uid).updateData([
            "avatarEmoji": selectedEmoji,
            "avatarColor": colorName
        ]) { _ in
            // Photo is already uploaded after cropping, so just continue
            self.handleCompletion()
        }
    }

    func handleCompletion() {
        if isFromOnboarding {
            // If from onboarding, show welcome screen and then authenticate
            showWelcomeAndLogin()
        } else {
            // If from within the app, just dismiss
            dismiss()
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
