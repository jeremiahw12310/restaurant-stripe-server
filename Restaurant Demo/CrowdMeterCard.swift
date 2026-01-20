import SwiftUI
import FirebaseAuth

// MARK: - Crowd Meter Card Component

struct CrowdMeterCard: View {
    @StateObject private var viewModel = CrowdMeterViewModel()
    @State private var showAdminEditor = false
    @State private var selectedDay = 0 // 0-6 (Sunday = 0)
    @State private var pulseAnimation = false
    @State private var selectedHour: Int? = nil
    @State private var showHourDetail = false
    @State private var countdownTimer: Timer?
    @State private var timeUntilOpening: (minutes: Int, message: String) = (0, "")
    
    // Computed property to force view updates when weeklyData changes
    private var crowdLevelsForSelectedDay: [Int] {
        return (0..<24).map { hour in
            viewModel.getCrowdLevelForHour(hour, day: selectedDay)
        }
    }
    
    // MARK: - Crowd Level Colors (Centralized)
    private func getCrowdLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.energyGreen // Not Busy
        case 2: return Theme.energyBlue // Light crowd
        case 3: return Theme.energyOrange // Moderate
        case 4: return Theme.energyRed // Busy
        case 5: return Color(red: 0.8, green: 0.2, blue: 0.2) // Very Busy
        default: return Theme.modernSecondary
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Simplified Header
            HStack {
                HStack(spacing: 8) {
                    Text("CROWD METER")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .tracking(1.2)
                    
                    // Single live indicator
                    if let data = viewModel.currentData, selectedDay == data.currentDay && viewModel.isCurrentlyOpen() {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.energyOrange)
                                .frame(width: 6, height: 6)
                                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                            
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(Theme.energyOrange)
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Theme.energyOrange.opacity(0.1))
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.energyOrange.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                
                Spacer()
                
                // Admin edit button - consistent styling
                if viewModel.isAdmin {
                    Button(action: { showAdminEditor = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.primaryGold)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Theme.primaryGold.opacity(0.1))
                                    .overlay(
                                        Circle()
                                            .stroke(Theme.primaryGold.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
            }
            
            // MARK: - Status Information
            if let data = viewModel.currentData {
                let isCurrentDay = selectedDay == data.currentDay
                let isOpen = viewModel.isCurrentlyOpen()
                
                // Consolidated status bar
                HStack {
                    if isOpen && isCurrentDay {
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(getCrowdLevelColor(data.currentLevel))
                            
                            Text(data.currentLevelDescription)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.modernCardSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(getCrowdLevelColor(data.currentLevel).opacity(0.3), lineWidth: 1)
                                )
                        )
                    } else if !viewModel.isRestaurantOpen(hour: Double(data.currentHour), day: selectedDay) {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.isBeforeOpeningToday() ? "clock" : "door.left.hand.closed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.isBeforeOpeningToday() ? Theme.energyOrange : Theme.modernSecondary)
                            
                            Text(timeUntilOpening.message)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.modernCardSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Theme.modernSecondary.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    
                    Spacer()
                    
                    // Time info
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.modernSecondary)
                        
                        Text("45 min avg visit")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                    }
                }
                
                // MARK: - Enhanced Bar Chart with 3D Effects (Dynamic Spacing)
                VStack(spacing: 6) {
                    // Fixed height container to prevent card resizing
                    ZStack(alignment: .bottom) {
                        // Invisible placeholder to maintain consistent height
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.clear)
                            .frame(width: 28, height: 92) // Maximum possible height (level 5 * 16 + 12)
                        
                        // Calculate dynamic spacing based on number of open hours
                        let openHours = (0..<24).filter { viewModel.isRestaurantOpen(hour: Double($0), day: selectedDay) }
                        let totalBars = openHours.count
                        let availableWidth: CGFloat = 280 // Available width for bars (card width minus padding)
                        let minBarWidth: CGFloat = 20 // Minimum bar width for readability
                        let maxBarWidth: CGFloat = 28 // Maximum bar width
                        let minSpacing: CGFloat = 6 // Minimum spacing between bars
                        let maxSpacing: CGFloat = 12 // Maximum spacing between bars
                        
                        // Calculate optimal bar width and spacing
                        let totalSpacingNeeded = CGFloat(totalBars - 1) * minSpacing
                        let availableForBars = availableWidth - totalSpacingNeeded
                        let calculatedBarWidth = min(max(availableForBars / CGFloat(totalBars), minBarWidth), maxBarWidth)
                        let actualSpacing = totalBars > 1 ? min(max((availableWidth - calculatedBarWidth * CGFloat(totalBars)) / CGFloat(totalBars - 1), minSpacing), maxSpacing) : 0
                        
                        // Bars for open hours only - dynamic spacing and width
                        HStack(alignment: .bottom, spacing: actualSpacing) {
                            ForEach(openHours, id: \.self) { hour in
                                let level = crowdLevelsForSelectedDay[hour]
                                let isCurrentHour = viewModel.isCurrentTimeSlot(hour: hour, day: selectedDay)
                                let barHeight = CGFloat(level) * 16 + 12 // Adjusted height to fit within card
                                
                                VStack(spacing: 4) {
                                    // Enhanced bar with 3D effects and multiple shadow layers
                                    ZStack {
                                        // Main bar with gradient
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        getBarColor(isCurrentHour: isCurrentHour, isOpenHour: true, level: level),
                                                        getBarColor(isCurrentHour: isCurrentHour, isOpenHour: true, level: level).opacity(0.7)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: calculatedBarWidth, height: barHeight) // Dynamic width based on available space
                                        
                                        // 3D shadow layers for depth
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.black.opacity(0.15))
                                            .frame(width: calculatedBarWidth, height: barHeight)
                                            .offset(x: 2, y: 2)
                                            .blendMode(.multiply)
                                        
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.black.opacity(0.08))
                                            .frame(width: calculatedBarWidth, height: barHeight)
                                            .offset(x: 1, y: 1)
                                            .blendMode(.multiply)
                                        
                                        // Current hour glow effect
                                        if isCurrentHour {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(getBarColor(isCurrentHour: isCurrentHour, isOpenHour: true, level: level).opacity(0.3))
                                                .frame(width: calculatedBarWidth + 4, height: barHeight + 4)
                                                .blur(radius: 6)
                                                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                                        }
                                    }
                                    .scaleEffect(isCurrentHour ? (pulseAnimation ? 1.05 : 1.0) : 1.0)
                                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                                    .shadow(color: getBarColor(isCurrentHour: isCurrentHour, isOpenHour: true, level: level).opacity(0.4), radius: isCurrentHour ? 10 : 5, x: 0, y: isCurrentHour ? 4 : 2)
                                    
                                    // Hour label - larger and more readable
                                    Text(formatHour(hour))
                                        .font(.system(size: calculatedBarWidth > 24 ? 11 : 10, weight: .bold, design: .rounded))
                                        .foregroundColor(isCurrentHour ? Theme.modernPrimary : Theme.modernSecondary)
                                        .scaleEffect(isCurrentHour ? 1.05 : 1.0)
                                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                                }
                                .onTapGesture {
                                    selectedHour = hour
                                    DispatchQueue.main.async {
                                        showHourDetail = true
                                    }
                                }
                            }
                        }
                        .frame(height: 92) // Fixed height to prevent card resizing
                        .padding(.horizontal, 4)
                    }
                }
            } else if viewModel.isLoading {
                // MARK: - Loading State
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.primaryGold))
                    
                    Text("Loading crowd data...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .frame(height: 80)
            } else {
                // MARK: - Error State
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.energyOrange)
                    
                    Text("Unable to load crowd data")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        viewModel.loadCurrentData()
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.primaryGold)
                    )
                }
                .frame(height: 80)
            }
            
            // MARK: - Enhanced Day Selector
            HStack(spacing: 16) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDay = (selectedDay - 1 + 7) % 7
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Theme.darkGoldGradient)
                                .shadow(color: Theme.goldShadow, radius: 6, x: 0, y: 3)
                        )
                }
                
                VStack(spacing: 2) {
                    Text(viewModel.getDayName(selectedDay))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .frame(minWidth: 90)
                    
                    // Today indicator
                    if selectedDay == getCurrentDayOfWeek() {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(Theme.energyOrange)
                            .tracking(0.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Theme.energyOrange.opacity(0.1))
                                    .overlay(
                                        Capsule()
                                            .stroke(Theme.energyOrange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                }
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDay = (selectedDay + 1) % 7
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Theme.darkGoldGradient)
                                .shadow(color: Theme.goldShadow, radius: 6, x: 0, y: 3)
                        )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
        .sheet(isPresented: $showAdminEditor) {
            CrowdMeterAdminEditor(viewModel: viewModel, selectedDay: selectedDay)
        }
        .sheet(isPresented: $showHourDetail) {
            if let hour = selectedHour {
                HourDetailSheet(hour: hour, day: selectedDay, viewModel: viewModel)
            }
        }
        .onChange(of: showHourDetail) { newValue in
            if !newValue {
                // Reset selectedHour when sheet is dismissed
                selectedHour = nil
            }
        }
        .onAppear {
            // Set current day
            let calendar = Calendar.current
            let now = Date()
            selectedDay = calendar.component(.weekday, from: now) - 1
            
            // Load weekly data for chart display
            viewModel.getWeeklyData { _ in }
            
            // Initialize countdown
            updateCountdown()
            
            // Start timer to update countdown every minute
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
                updateCountdown()
            }
            
            // Optimized animation - single, simple pulse
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .onDisappear {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }
    
    // MARK: - Helper Functions
    
    private func getCurrentDayOfWeek() -> Int {
        let calendar = Calendar.current
        let now = Date()
        return calendar.component(.weekday, from: now) - 1 // Convert to 0-6 (Sunday = 0)
    }
    
    private func updateCountdown() {
        timeUntilOpening = viewModel.getTimeUntilOpening()
    }
    
    private func getCurrentTimeDisplay() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 {
            return "12a"
        } else if hour < 12 {
            return "\(hour)a"
        } else if hour == 12 {
            return "12p"
        } else {
            return "\(hour - 12)p"
        }
    }
    
    private func getBarColor(isCurrentHour: Bool, isOpenHour: Bool, level: Int) -> Color {
        if !isOpenHour {
            return Theme.modernSecondary.opacity(0.3) // Grey for closed hours
        } else if isCurrentHour {
            return getCrowdLevelColor(level) // Show crowd level color for current hour
        } else {
            return Theme.modernSecondary.opacity(0.6) // Grey for all non-current hours
        }
    }
    
    private var cardBackground: some View {
        ZStack {
            // Dutch Bros style card background
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
        }
    }
}

// MARK: - Hour Detail Sheet

struct HourDetailSheet: View {
    let hour: Int
    let day: Int
    @ObservedObject var viewModel: CrowdMeterViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isLoaded = false
    
    private let primaryGold = Theme.primaryGold
    private let deepGold = Theme.deepGold
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if !isLoaded {
                    ProgressView("Loading...")
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isLoaded = true
                            }
                        }
                } else {
                    // Time display
                    VStack(spacing: 8) {
                        Text("\(viewModel.getDayName(day))")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                        
                        Text("\(viewModel.getHourDisplay(hour))")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                    }
                    .padding(.top, 20)
                
                // Crowd level display
                VStack(spacing: 16) {
                    let level = viewModel.getCrowdLevelForHour(hour, day: day)
                    let isOpen = viewModel.isRestaurantOpen(hour: Double(hour), day: day)
                    
                    if isOpen {
                        VStack(spacing: 12) {
                            // Crowd level indicator
                            ZStack {
                                Circle()
                                    .fill(getCrowdLevelColor(level))
                                    .frame(width: 80, height: 80)
                                    .shadow(color: getCrowdLevelColor(level).opacity(0.3), radius: 8, x: 0, y: 4)
                                
                                VStack(spacing: 2) {
                                    Text("\(level)")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Level")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                            
                            Text(getLevelDescription(level))
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                            
                            Text(getLevelDetail(level))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "door.left.hand.closed")
                                .font(.system(size: 48))
                                .foregroundColor(Theme.modernSecondary)
                            
                            Text("Closed")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                            
                            Text("Restaurant is not open during this hour")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                
                Spacer()
                
                // Close button
                Button(action: { dismiss() }) {
                    Text("Close")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Theme.darkGoldGradient
                        )
                        .cornerRadius(25)
                        .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                }
            }
            .navigationTitle("Hour Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func getCrowdLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.energyGreen
        case 2: return Theme.energyBlue
        case 3: return Theme.energyOrange
        case 4: return Theme.energyRed
        case 5: return Color(red: 0.8, green: 0.2, blue: 0.2)
        default: return Theme.modernSecondary
        }
    }
    
    private func getLevelDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Not Busy"
        case 2: return "A Little Busy"
        case 3: return "Moderately Busy"
        case 4: return "Busy"
        case 5: return "Very Busy"
        default: return "Unknown"
        }
    }
    
    private func getLevelDetail(_ level: Int) -> String {
        switch level {
        case 1: return "Perfect time to visit! Minimal wait times and plenty of seating available."
        case 2: return "Light crowd. You might experience short wait times but seating should be readily available."
        case 3: return "Moderate activity. Expect some wait times and limited seating options."
        case 4: return "High traffic. Plan for longer wait times and consider making a reservation."
        case 5: return "Peak hours! Expect significant wait times and limited seating availability."
        default: return "Crowd level information not available."
        }
    }
}

// MARK: - Admin Editor Sheet

struct CrowdMeterAdminEditor: View {
    @ObservedObject var viewModel: CrowdMeterViewModel
    let selectedDay: Int
    @Environment(\.dismiss) var dismiss
    @State private var selectedLevel = 3
    @State private var isUpdating = false
    @State private var selectedHour: Int? = nil
    
    private let primaryGold = Theme.primaryGold
    private let deepGold = Theme.deepGold
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Edit \(viewModel.getDayName(selectedDay))")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    Text("Tap any hour to set crowd level")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .padding(.top, 20)
                
                // Hourly grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                    ForEach(0..<24, id: \.self) { hour in
                        let isOpenHour = viewModel.isRestaurantOpen(hour: Double(hour), day: selectedDay)
                        let currentLevel = viewModel.getCrowdLevelForHour(hour, day: selectedDay)
                        
                        Button(action: {
                            selectedHour = hour
                            selectedLevel = currentLevel
                        }) {
                            VStack(spacing: 4) {
                                Text(viewModel.getHourDisplay(hour))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.modernPrimary)
                                
                                if isOpenHour {
                                    Circle()
                                        .fill(getCrowdLevelColor(currentLevel))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text("\(currentLevel)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(selectedHour == hour ? primaryGold : Color.clear, lineWidth: 2)
                                        )
                                } else {
                                    Image(systemName: "door.left.hand.closed")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedHour == hour ? primaryGold.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                
                // Level selector for selected hour
                if let hour = selectedHour {
                    VStack(spacing: 16) {
                        Text("\(viewModel.getDayName(selectedDay)) at \(viewModel.getHourDisplay(hour))")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                        
                        HStack(spacing: 12) {
                            ForEach(1...5, id: \.self) { level in
                                Button(action: { selectedLevel = level }) {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(getCrowdLevelColor(level))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle()
                                                    .stroke(selectedLevel == level ? primaryGold : Color.clear, lineWidth: 2)
                                            )
                                        
                                        Text("\(level)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .scaleEffect(selectedLevel == level ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedLevel)
                            }
                        }
                        
                        Text(getLevelDescription(selectedLevel))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                            .multilineTextAlignment(.center)
                        
                        // Update button
                        Button(action: updateCrowdLevel) {
                            HStack(spacing: 8) {
                                if isUpdating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                
                                Text(isUpdating ? "Updating..." : "Update Level")
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Theme.darkGoldGradient
                            )
                            .cornerRadius(20)
                            .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                        }
                        .disabled(isUpdating)
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(primaryGold)
                }
            }
        }
    }
    
    private func updateCrowdLevel() {
        guard let hour = selectedHour else { return }
        
        isUpdating = true
        viewModel.updateCrowdLevel(hour: hour, dayOfWeek: selectedDay, level: selectedLevel) { success in
            isUpdating = false
            if success {
                // Don't dismiss, let user continue editing
            }
        }
    }
    
    private func getCrowdLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.energyGreen
        case 2: return Theme.energyBlue
        case 3: return Theme.energyOrange
        case 4: return Theme.energyRed
        case 5: return Color(red: 0.8, green: 0.2, blue: 0.2)
        default: return Theme.modernSecondary
        }
    }
    
    private func getLevelDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Not Busy"
        case 2: return "A Little Busy"
        case 3: return "Moderately Busy"
        case 4: return "Busy"
        case 5: return "Very Busy"
        default: return "Unknown"
        }
    }
}

// MARK: - Weekly View Sheet

struct CrowdMeterWeeklyView: View {
    @ObservedObject var viewModel: CrowdMeterViewModel
    @Environment(\.dismiss) var dismiss
    @State private var weeklyData: [CrowdLevel] = []
    @State private var isLoading = false
    
    private let primaryGold = Theme.primaryGold
    private let deepGold = Theme.deepGold
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .progressViewStyle(CircularProgressViewStyle(tint: primaryGold))
                        
                        Text("Loading weekly data...")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(0..<7, id: \.self) { day in
                                WeeklyDayView(
                                    day: day,
                                    dayName: viewModel.getDayName(day),
                                    weeklyData: weeklyData,
                                    viewModel: viewModel
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Weekly Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(primaryGold)
                }
            }
        }
        .onAppear {
            loadWeeklyData()
        }
    }
    
    private func loadWeeklyData() {
        isLoading = true
        viewModel.getWeeklyData { data in
            weeklyData = data
            isLoading = false
        }
    }
}

// MARK: - Weekly Day View

struct WeeklyDayView: View {
    let day: Int
    let dayName: String
    let weeklyData: [CrowdLevel]
    @ObservedObject var viewModel: CrowdMeterViewModel
    
    private let primaryGold = Theme.primaryGold
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header
            Text(dayName)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
            
            // Hours grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(0..<24, id: \.self) { hour in
                    HourCell(
                        hour: hour,
                        day: day,
                        weeklyData: weeklyData,
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.energyGradient, lineWidth: 2)
                )
                .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Hour Cell

struct HourCell: View {
    let hour: Int
    let day: Int
    let weeklyData: [CrowdLevel]
    @ObservedObject var viewModel: CrowdMeterViewModel
    @State private var showHourEditor = false
    
    private let primaryGold = Theme.primaryGold
    
    var currentLevel: Int {
        weeklyData.first { $0.hour == hour && $0.dayOfWeek == day }?.level ?? 3
    }
    
    var isCurrentHour: Bool {
        viewModel.isCurrentHour(hour, day)
    }
    
    var body: some View {
        Button(action: { showHourEditor = true }) {
            VStack(spacing: 2) {
                Text(viewModel.getHourDisplay(hour))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                
                Circle()
                    .fill(getCrowdLevelColor(currentLevel))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(isCurrentHour ? primaryGold : Color.clear, lineWidth: 2)
                    )
                    .scaleEffect(isCurrentHour ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCurrentHour)
            }
        }
        .sheet(isPresented: $showHourEditor) {
            HourEditorSheet(
                hour: hour,
                day: day,
                currentLevel: currentLevel,
                viewModel: viewModel
            )
        }
    }
    
    private func getCrowdLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.energyGreen
        case 2: return Theme.energyBlue
        case 3: return Theme.energyOrange
        case 4: return Theme.energyRed
        case 5: return Color(red: 0.8, green: 0.2, blue: 0.2)
        default: return Theme.modernSecondary
        }
    }
}

// MARK: - Hour Editor Sheet

struct HourEditorSheet: View {
    let hour: Int
    let day: Int
    let currentLevel: Int
    @ObservedObject var viewModel: CrowdMeterViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedLevel: Int
    @State private var isUpdating = false
    
    private let primaryGold = Theme.primaryGold
    private let deepGold = Theme.deepGold
    
    init(hour: Int, day: Int, currentLevel: Int, viewModel: CrowdMeterViewModel) {
        self.hour = hour
        self.day = day
        self.currentLevel = currentLevel
        self.viewModel = viewModel
        self._selectedLevel = State(initialValue: currentLevel)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Time display
                VStack(spacing: 8) {
                    Text("\(viewModel.getDayName(day))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                    
                    Text(viewModel.getHourDisplay(hour))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }
                .padding(.top, 20)
                
                // Level selector
                VStack(spacing: 16) {
                    Text("Set Crowd Level")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                    
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { level in
                            Button(action: { selectedLevel = level }) {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(getCrowdLevelColor(level))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedLevel == level ? primaryGold : Color.clear, lineWidth: 3)
                                        )
                                    
                                    Text("\(level)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .scaleEffect(selectedLevel == level ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedLevel)
                        }
                    }
                    
                    Text(getLevelDescription(selectedLevel))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Update button
                Button(action: updateCrowdLevel) {
                    HStack(spacing: 8) {
                        if isUpdating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
                        Text(isUpdating ? "Updating..." : "Update")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Theme.darkGoldGradient
                    )
                    .cornerRadius(25)
                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                }
                .disabled(isUpdating)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Edit Hour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(primaryGold)
                }
            }
        }
    }
    
    private func updateCrowdLevel() {
        isUpdating = true
        viewModel.updateCrowdLevel(hour: hour, dayOfWeek: day, level: selectedLevel) { success in
            isUpdating = false
            if success {
                dismiss()
            }
        }
    }
    
    private func getCrowdLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.energyGreen
        case 2: return Theme.energyBlue
        case 3: return Theme.energyOrange
        case 4: return Theme.energyRed
        case 5: return Color(red: 0.8, green: 0.2, blue: 0.2)
        default: return Theme.modernSecondary
        }
    }
    
    private func getLevelDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Not Busy"
        case 2: return "A Little Busy"
        case 3: return "Moderately Busy"
        case 4: return "Busy"
        case 5: return "Very Busy"
        default: return "Unknown"
        }
    }
} 