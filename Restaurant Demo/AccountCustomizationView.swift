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
    @State private var headerAnimated = false
    @State private var contentAnimated = false

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showPhotoCrop = false
    @State private var showPhotoPicker = false
    @State private var isFromOnboarding = false

    let emojis = ["🥟", "🧋", "🍜", "🍚", "🥢"]
    let colorOptions: [(Color, String)] = [
        (.orange, "orange"), (.red, "red"), (.blue, "blue"), (.green, "green"),
        (.purple, "purple"), (.pink, "pink"), (.indigo, "indigo"), (.brown, "brown"),
        (Color(red: 1.0, green: 0.84, blue: 0.0), "gold")
    ]

    var body: some View {
        ZStack {
            // Themed gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Theme.modernBackground,
                    Theme.modernCardSecondary,
                    Theme.modernBackground
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 10) {
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
                    .scaleEffect(contentAnimated ? 1.0 : 0.95)
                    .opacity(contentAnimated ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: contentAnimated)
                }

                Spacer()

                // Beautiful action buttons
                actionButtonsView
            }


        }

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
                        DebugLogger.debug("📤 Uploading cropped photo immediately", category: "User")
                        userVM.uploadProfilePhoto(croppedImage) { success in
                            DispatchQueue.main.async {
                                if success {
                                    DebugLogger.debug("✅ Photo uploaded successfully after cropping", category: "User")
                                    selectedImage = nil // Clear local image so we use the latest from userVM
                                    // Force refresh the profile image to ensure UI updates
                                    userVM.forceRefreshProfileImage()
                                } else {
                                    DebugLogger.debug("❌ Failed to upload photo after cropping", category: "User")
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
            
            // Initialize selected emoji and color from user's current settings
            selectedEmoji = userVM.avatarEmoji
            selectedColor = userVM.avatarColor
            
            // Trigger animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                headerAnimated = true
                contentAnimated = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Text("Make Your Mark! ✨")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Theme.darkGoldGradient)
            
            Text("Customize your avatar")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
        }
        .padding(.top, 60)
        .scaleEffect(headerAnimated ? 1.0 : 0.9)
        .opacity(headerAnimated ? 1.0 : 0.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: headerAnimated)
    }
    
    private var avatarPreviewView: some View {
        ZStack {
            // Gold outer ring
            Circle()
                .stroke(Theme.darkGoldGradient, lineWidth: 4)
                .frame(width: 134, height: 134)
                .shadow(color: Theme.primaryGold.opacity(0.3), radius: 10, x: 0, y: 5)
            
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
                    .shadow(color: selectedColor.opacity(0.4), radius: 15, x: 0, y: 8)
                
                Text(selectedEmoji)
                    .font(.system(size: 60))
                    .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
            }
        }
        .padding(.vertical, 16)
        .scaleEffect(headerAnimated ? 1.0 : 0.8)
        .opacity(headerAnimated ? 1.0 : 0.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: headerAnimated)
    }
    
    private var photoSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.primaryGold)
                Text("Profile Photo")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }
            
            HStack(spacing: 12) {
                // Add Photo Button
                Button(action: {
                    showPhotoPicker = true
                }) {
                    VStack(spacing: 8) {
                        if userVM.isUploadingPhoto {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Theme.primaryGold)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(Theme.primaryGold)
                        }
                        Text(userVM.isUploadingPhoto ? "Uploading..." : "Add Photo")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                    }
                    .frame(width: 90, height: 90)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.primaryGold, lineWidth: 2)
                            )
                    )
                    .shadow(color: Theme.primaryGold.opacity(0.2), radius: 8, x: 0, y: 4)
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
                                .foregroundColor(Theme.energyRed)
                            Text("Remove")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                        }
                        .frame(width: 90, height: 90)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Theme.energyRed.opacity(0.5), lineWidth: 2)
                                )
                        )
                        .shadow(color: Theme.energyRed.opacity(0.15), radius: 8, x: 0, y: 4)
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
            HStack(spacing: 8) {
                Image(systemName: "face.smiling.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.primaryGold)
                Text("Choose an Avatar")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }
            
            HStack(spacing: 12) {
                ForEach(emojis, id: \.self) { emoji in
                    emojiButton(for: emoji)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func emojiButton(for emoji: String) -> some View {
        Button(action: { 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedEmoji = emoji 
            }
        }) {
            Text(emoji)
                .font(.system(size: 40))
                .padding(16)
                .background(emojiBackground(for: emoji))
                .shadow(color: emojiShadowColor(for: emoji), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(selectedEmoji == emoji ? 1.05 : 1.0)
    }
    
    private func emojiBackground(for emoji: String) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(selectedEmoji == emoji ? AnyShapeStyle(selectedEmojiGradient) : AnyShapeStyle(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedEmoji == emoji ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2), lineWidth: selectedEmoji == emoji ? 3 : 1)
            )
    }
    
    private var selectedEmojiGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Theme.primaryGold.opacity(0.15),
                Theme.deepGold.opacity(0.1)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func emojiShadowColor(for emoji: String) -> Color {
        selectedEmoji == emoji ? Theme.primaryGold.opacity(0.3) : Color.black.opacity(0.05)
    }
    
    private var colorSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.primaryGold)
                Text("Choose a Color")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(colorOptions, id: \.1) { color, _ in
                        colorButton(for: color)
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func colorButton(for color: Color) -> some View {
        Button(action: { 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedColor = color 
            }
        }) {
            ZStack {
                // Outer ring for selected
                if selectedColor == color {
                    Circle()
                        .stroke(Theme.primaryGold, lineWidth: 3)
                        .frame(width: 58, height: 58)
                }
                
                Circle()
                    .fill(colorGradient(for: color))
                    .frame(width: 50, height: 50)
                    .shadow(color: color.opacity(0.4), radius: selectedColor == color ? 10 : 6, x: 0, y: 4)
                
                if selectedColor == color {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(selectedColor == color ? 1.1 : 1.0)
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
            Button(action: { saveCustomization() }) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .black))
                    
                    Text("SAVE & CONTINUE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(0.5)
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .black))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            
            if isFromOnboarding {
                Button(action: { 
                    // Reset current navigation state and set new one
                    authVM.shouldNavigateToCustomization = false
                    authVM.shouldNavigateToPreferences = true
                    DebugLogger.debug("🔵 AccountCustomizationView: Skip button - Navigating to preferences", category: "User")
                }) {
                    Text("Skip For Now")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 20)
    }
    


    func saveCustomization() {
        let db = Firestore.firestore()
        let colorName = colorOptions.first(where: { $0.0 == selectedColor })?.1 ?? "red"
        
        // Update local UserViewModel properties immediately for instant UI feedback
        userVM.avatarEmoji = selectedEmoji
        userVM.avatarColorName = colorName
        
        // Save the avatar customization
        db.collection("users").document(uid).updateData([
            "avatarEmoji": selectedEmoji,
            "avatarColor": colorName
        ]) { _ in
            DispatchQueue.main.async {
                self.handleCompletion()
            }
        }
    }
    


    func handleCompletion() {
        if isFromOnboarding {
            // If from onboarding, navigate directly to preferences
            // Reset current navigation state and set new one
            authVM.shouldNavigateToCustomization = false
            authVM.shouldNavigateToPreferences = true
            DebugLogger.debug("🔵 AccountCustomizationView: Navigating to preferences", category: "User")
        } else {
            // If from within the app, just dismiss
            dismiss()
        }
    }
}
