import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct UserPreferencesView: View {
    let uid: String
    @EnvironmentObject var authVM: AuthenticationViewModel
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var likesSpicyFood: Bool = false
    @State private var dislikesSpicyFood: Bool = false
    @State private var hasPeanutAllergy: Bool = false
    @State private var isVegetarian: Bool = false
    @State private var hasLactoseIntolerance: Bool = false
    @State private var doesntEatPork: Bool = false
    @State private var tastePreferences: String = ""
    @State private var isLoading: Bool = false
    @State private var contentVisible: Bool = true  // Start visible to sync with slide transition
    @State private var headerScale: CGFloat = 0.9
    @State private var cardsOffset: CGFloat = 30
    
    var body: some View {
        ZStack {
            // Background gradient matching auth flow
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
            
            VStack(spacing: 0) {
                // Main content in ScrollView
                ScrollView {
                    VStack(spacing: 14) {
                        Spacer(minLength: 8)
                        
                        // Compact header
                        headerView
                        
                        // Preferences section
                        preferencesSection
                        
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 20)
                }
                
                // Action buttons - fixed at bottom
                actionButtonsView
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationBarHidden(true)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        isTextFieldFocused = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.primaryGold)
                }
            }
        }
        .onAppear {
            // Load current preferences from UserViewModel into local state
            likesSpicyFood = userVM.likesSpicyFood
            dislikesSpicyFood = userVM.dislikesSpicyFood
            hasPeanutAllergy = userVM.hasPeanutAllergy
            isVegetarian = userVM.isVegetarian
            hasLactoseIntolerance = userVM.hasLactoseIntolerance
            doesntEatPork = userVM.doesntEatPork
            tastePreferences = userVM.tastePreferences
            
            // Quick entrance animations that sync with the slide transition
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                headerScale = 1.0
                cardsOffset = 0
            }
        }
    }
    
    // MARK: - Compact Header View
    
    private var headerView: some View {
        VStack(spacing: 8) {
            // Small star icon matching "Almost a VIP" style
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGold.opacity(0.2), Theme.deepGold.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.darkGoldGradient)
            }
            .shadow(color: Theme.primaryGold.opacity(0.3), radius: 10, x: 0, y: 4)
            .scaleEffect(headerScale)
            
            // Title
            VStack(spacing: 4) {
                Text("Personalize Your Experience")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                
                Text("Help us recommend the perfect dishes")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(spacing: 12) {
            // Taste preferences text input card (first card)
            tastePreferencesCard
            
            // Existing preference toggle cards
            ForEach(preferenceOptions, id: \.id) { option in
                preferenceCard(for: option)
            }
        }
        .offset(y: cardsOffset)
    }
    
    // MARK: - Taste Preferences Card
    
    private var tastePreferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icon - smaller circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.primaryGold.opacity(0.2), Theme.deepGold.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.primaryGold)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tell us about your taste")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    Text("Share flavor preferences (optional)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                
                Spacer()
            }
            
            // Text input field
            TextField("e.g. I love savory flavors, not too salty...", text: $tastePreferences, axis: .vertical)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isTextFieldFocused ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2),
                                    lineWidth: isTextFieldFocused ? 2 : 1
                                )
                        )
                )
                .lineLimit(2...4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            !tastePreferences.isEmpty ? Theme.darkGoldGradient : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: !tastePreferences.isEmpty ? 2 : 0
                        )
                )
        )
    }
    
    private func preferenceCard(for option: PreferenceOption) -> some View {
        Button(action: {
            togglePreference(for: option)
        }) {
            HStack(spacing: 12) {
                // Icon - smaller circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.primaryGold.opacity(0.2), Theme.deepGold.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: option.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.primaryGold)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    Text(option.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Toggle
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(getPreferenceValue(for: option) ? Theme.primaryGold : Color(.systemGray5))
                        .frame(width: 48, height: 28)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .offset(x: getPreferenceValue(for: option) ? 10 : -10)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: getPreferenceValue(for: option))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                getPreferenceValue(for: option) ? Theme.darkGoldGradient : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom),
                                lineWidth: getPreferenceValue(for: option) ? 2 : 0
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            if isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.0)
                        .tint(Theme.primaryGold)
                    Text("Saving preferences...")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .padding()
            } else {
                Button(action: {
                    savePreferences()
                }) {
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
            }
            
            Button(action: {
                showWelcomeAndLogin()
            }) {
                Text("Skip for Now")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }
            .padding(.bottom, 8)
        }
        .padding(.bottom, 30)
        .background(Theme.modernBackground)
    }
    

    
    // MARK: - Helper Methods
    
    private func togglePreference(for option: PreferenceOption) {
        switch option.id {
        case "spicy":
            likesSpicyFood.toggle()
        case "notSpicy":
            dislikesSpicyFood.toggle()
        case "peanut":
            hasPeanutAllergy.toggle()
        case "vegetarian":
            isVegetarian.toggle()
        case "lactose":
            hasLactoseIntolerance.toggle()
        case "pork":
            doesntEatPork.toggle()
        default:
            break
        }
    }
    
    private func getPreferenceValue(for option: PreferenceOption) -> Bool {
        switch option.id {
        case "spicy":
            return likesSpicyFood
        case "notSpicy":
            return dislikesSpicyFood
        case "peanut":
            return hasPeanutAllergy
        case "vegetarian":
            return isVegetarian
        case "lactose":
            return hasLactoseIntolerance
        case "pork":
            return doesntEatPork
        default:
            return false
        }
    }
    
    private func savePreferences() {
        isLoading = true
        
        // Update local UserViewModel properties
        userVM.likesSpicyFood = likesSpicyFood
        userVM.dislikesSpicyFood = dislikesSpicyFood
        userVM.hasPeanutAllergy = hasPeanutAllergy
        userVM.isVegetarian = isVegetarian
        userVM.hasLactoseIntolerance = hasLactoseIntolerance
        userVM.doesntEatPork = doesntEatPork
        userVM.tastePreferences = tastePreferences
        
        // Save to Firestore
        userVM.saveUserPreferences { success in
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.showWelcomeAndLogin()
                }
            }
        }
    }
    
    private func showWelcomeAndLogin() {
        DebugLogger.debug("🔵 UserPreferencesView: showWelcomeAndLogin() called", category: "User")
        DebugLogger.debug("🔵 UserPreferencesView: userVM.isNewUser = \(userVM.isNewUser)", category: "User")
        
        // Note: Welcome display is now handled by HomeView's integrated welcome state.
        // HomeView will detect if user is new and show the welcome celebration immediately.
        // We don't set isNewUser = false here - HomeView will do that after showing welcome.
        
        // Complete the authentication flow directly by setting didAuthenticate to true
        // Reset all navigation states and set final state
        authVM.shouldNavigateToCustomization = false
        authVM.shouldNavigateToPreferences = false
        authVM.shouldNavigateToUserDetails = false
        authVM.didAuthenticate = true
        DebugLogger.debug("🔵 UserPreferencesView: Completing authentication flow - HomeView will handle welcome", category: "User")

        // Return to Home immediately after saving preferences
        // HomeView will detect new user state and show integrated welcome
        dismiss()
    }
}

// MARK: - Preference Option Model

struct PreferenceOption {
    let id: String
    let title: String
    let description: String
    let icon: String
}

extension UserPreferencesView {
    var preferenceOptions: [PreferenceOption] {
        [
            PreferenceOption(
                id: "spicy",
                title: "I like spicy food",
                description: "We'll recommend dishes with extra heat and spice levels",
                icon: "flame.fill"
            ),
            PreferenceOption(
                id: "notSpicy",
                title: "I don't like spicy food",
                description: "We'll recommend milder dishes and avoid spicy options",
                icon: "snowflake"
            ),
            PreferenceOption(
                id: "peanut",
                title: "I have peanut allergies",
                description: "We'll avoid recommending dishes with peanuts",
                icon: "exclamationmark.triangle.fill"
            ),
            PreferenceOption(
                id: "vegetarian",
                title: "I'm vegetarian",
                description: "We'll focus on plant-based and vegetarian options",
                icon: "leaf.fill"
            ),
            PreferenceOption(
                id: "lactose",
                title: "I'm lactose intolerant",
                description: "We'll avoid dairy-heavy recommendations",
                icon: "drop.fill"
            ),
            PreferenceOption(
                id: "pork",
                title: "I don't eat pork",
                description: "We'll exclude pork-based dishes from recommendations",
                icon: "xmark.circle.fill"
            )
        ]
    }
} 

#if DEBUG
struct UserPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        UserPreferencesView(uid: "preview-uid")
            .environmentObject(AuthenticationViewModel())
            .environmentObject(UserViewModel())
            .previewDevice("iPhone 16")
    }
}
#endif 
