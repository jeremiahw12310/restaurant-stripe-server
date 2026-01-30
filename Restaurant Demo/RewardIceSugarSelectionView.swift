import SwiftUI

// MARK: - Ice/Sugar Level Selection View
/// Displays vertical sliders for ice and sugar level customization
/// Used after drink selection and before topping selection for Fruit Tea, Milk Tea, and Coffee rewards
struct RewardIceSugarSelectionView: View {
    let reward: RewardOption
    let drinkName: String
    let currentPoints: Int
    let onSelectionComplete: (String, String) -> Void  // (iceLevel, sugarLevel)
    let onCancel: () -> Void
    
    @State private var selectedIceLevel: Int = 0  // 0 = Normal, 1 = 75%, 2 = 50%, 3 = 25%, 4 = No Ice
    @State private var selectedSugarLevel: Int = 0  // 0 = Normal, 1 = 75%, 2 = 50%, 3 = 25%, 4 = No Sugar
    @State private var appearAnimation = false
    
    private let iceLevels = ["Normal", "75%", "50%", "25%", "No Ice"]
    private let sugarLevels = ["Normal", "75%", "50%", "25%", "No Sugar"]
    
    var body: some View {
        ZStack {
            // Background with dark base and subtle reward color accent
            RewardSelectionBackground(rewardColor: reward.color)
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                Spacer()
                
                // Slider Section
                sliderSection
                
                Spacer()
                
                // Footer with button
                footerSection
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.2)))
                }
                
                Spacer()
                
                Text("Customize Your Drink")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Spacer for balance
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Drink name
            VStack(spacing: 6) {
                Text(drinkName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Adjust ice and sugar levels")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 8)
        }
        .offset(y: appearAnimation ? 0 : -20)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Slider Section
    private var sliderSection: some View {
        VStack(spacing: 24) {
            HStack(spacing: 40) {
                // Ice Slider
                VStack(spacing: 16) {
                    // Icon and label
                    HStack(spacing: 8) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(red: 0.6, green: 0.85, blue: 1.0))
                        Text("Ice")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    // Vertical slider
                    VerticalLevelSlider(
                        selectedLevel: $selectedIceLevel,
                        levels: iceLevels,
                        accentColor: Color(red: 0.6, green: 0.85, blue: 1.0)
                    )
                }
                
                // Sugar Slider
                VStack(spacing: 16) {
                    // Icon and label
                    HStack(spacing: 8) {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                        Text("Sugar")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    // Vertical slider
                    VerticalLevelSlider(
                        selectedLevel: $selectedSugarLevel,
                        levels: sugarLevels,
                        accentColor: Color(red: 1.0, green: 0.85, blue: 0.4)
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frostedGlassCard(cornerRadius: 24)
            .padding(.horizontal, 20)
        }
        .offset(y: appearAnimation ? 0 : 30)
        .opacity(appearAnimation ? 1 : 0)
    }
    
    // MARK: - Footer Section
    private var footerSection: some View {
        VStack(spacing: 12) {
            // Selection summary
            HStack(spacing: 16) {
                // Ice selection
                HStack(spacing: 6) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.6, green: 0.85, blue: 1.0))
                    Text(iceLevels[selectedIceLevel])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("•")
                    .foregroundColor(.white.opacity(0.5))
                
                // Sugar selection
                HStack(spacing: 6) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                    Text(sugarLevels[selectedSugarLevel])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.3))
            )
            
            // Continue button
            Button(action: {
                onSelectionComplete(iceLevels[selectedIceLevel], sugarLevels[selectedSugarLevel])
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Continue")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.9, blue: 0.5),
                                    Color(red: 1.0, green: 0.75, blue: 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .offset(y: appearAnimation ? 0 : 40)
        .opacity(appearAnimation ? 1 : 0)
    }
}

// MARK: - Vertical Level Slider Component
/// A custom vertical slider with discrete levels that can be tapped or dragged
struct VerticalLevelSlider: View {
    @Binding var selectedLevel: Int
    let levels: [String]
    let accentColor: Color
    
    @State private var isDragging = false
    
    private let sliderHeight: CGFloat = 280
    private let trackWidth: CGFloat = 60
    private let knobSize: CGFloat = 28
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background track
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                
                // Filled portion (from bottom to selected level)
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.8),
                                accentColor.opacity(0.4)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: fillHeight)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedLevel)
                
                // Level indicators and labels
                VStack(spacing: 0) {
                    ForEach(0..<levels.count, id: \.self) { index in
                        levelRow(index: index, geometry: geometry)
                        if index < levels.count - 1 {
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(width: trackWidth, height: sliderHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let yPosition = value.location.y
                        let levelIndex = calculateLevelFromPosition(yPosition)
                        if levelIndex != selectedLevel {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedLevel = levelIndex
                            }
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: trackWidth, height: sliderHeight)
    }
    
    // Calculate fill height based on selected level (0 = full, 4 = empty)
    private var fillHeight: CGFloat {
        let segmentHeight = sliderHeight / CGFloat(levels.count)
        let filledLevels = CGFloat(levels.count - selectedLevel)
        return segmentHeight * filledLevels
    }
    
    // Calculate which level from drag position
    private func calculateLevelFromPosition(_ yPosition: CGFloat) -> Int {
        let segmentHeight = sliderHeight / CGFloat(levels.count)
        let levelIndex = Int(yPosition / segmentHeight)
        return max(0, min(levels.count - 1, levelIndex))
    }
    
    // Level row with indicator
    @ViewBuilder
    private func levelRow(index: Int, geometry: GeometryProxy) -> some View {
        let isSelected = index == selectedLevel
        
        HStack(spacing: 0) {
            // Level indicator dot
            Circle()
                .fill(isSelected ? accentColor : Color.white.opacity(0.3))
                .frame(width: isSelected ? 14 : 8, height: isSelected ? 14 : 8)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.8 : 0.2), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: isSelected ? accentColor.opacity(0.5) : .clear, radius: 4)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .frame(width: trackWidth, height: knobSize)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                selectedLevel = index
            }
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }
}

// MARK: - Level Label View (displayed beside sliders)
struct LevelLabelsView: View {
    let levels: [String]
    let selectedLevel: Int
    let alignment: HorizontalAlignment
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<levels.count, id: \.self) { index in
                let isSelected = index == selectedLevel
                
                Text(levels[index])
                    .font(.system(size: isSelected ? 15 : 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.5))
                    .frame(height: 56)  // Match slider segment height (280/5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct RewardIceSugarSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        RewardIceSugarSelectionView(
            reward: RewardOption(
                title: "Milk Tea",
                description: "A refreshing milk tea of your choice",
                pointsRequired: 500,
                color: Color(red: 0.6, green: 0.4, blue: 0.2),
                icon: "cup.and.saucer.fill",
                category: "drink"
            ),
            drinkName: "Jasmine Green Milk Tea",
            currentPoints: 750,
            onSelectionComplete: { ice, sugar in
                print("Selected: Ice - \(ice), Sugar - \(sugar)")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
}
#endif
