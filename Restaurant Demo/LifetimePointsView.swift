import SwiftUI

struct LifetimePointsView: View {
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Lifetime points levels with Theme colors
    private let levels = [
        LifetimeLevel(name: "STARTER", minPoints: 0, maxPoints: 499, color: Theme.modernSecondary, icon: "🥉", description: "New to The Dumps"),
        LifetimeLevel(name: "REGULAR", minPoints: 500, maxPoints: 1499, color: Theme.energyBlue, icon: "🥈", description: "Regular customer"),
        LifetimeLevel(name: "VIP", minPoints: 1500, maxPoints: 3999, color: Theme.energyGreen, icon: "🥇", description: "Loyal customer"),
        LifetimeLevel(name: "LEGEND", minPoints: 4000, maxPoints: 9999, color: Theme.primaryGold, icon: "💎", description: "VIP customer"),
        LifetimeLevel(name: "CHAMPION", minPoints: 10000, maxPoints: 24999, color: Theme.energyOrange, icon: "💎", description: "Elite customer"),
        LifetimeLevel(name: "ICON", minPoints: 25000, maxPoints: 999999, color: Theme.energyRed, icon: "👑", description: "Legendary status")
    ]
    
    private var currentLevel: LifetimeLevel {
        levels.first { level in
            userVM.lifetimePoints >= level.minPoints && userVM.lifetimePoints <= level.maxPoints
        } ?? levels.last ?? LifetimeLevel(name: "ICON", minPoints: 25000, maxPoints: 999999, color: Theme.energyRed, icon: "👑", description: "Legendary status")
    }
    
    private var nextLevel: LifetimeLevel? {
        guard let currentIndex = levels.firstIndex(where: { $0.name == currentLevel.name }) else { return nil }
        return currentIndex + 1 < levels.count ? levels[currentIndex + 1] : nil
    }
    
    private var progressToNextLevel: Double {
        guard let next = nextLevel else { return 1.0 }
        let currentRange = next.minPoints - currentLevel.minPoints
        let userProgress = userVM.lifetimePoints - currentLevel.minPoints
        return min(Double(userProgress) / Double(currentRange), 1.0)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Premium style background
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
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Header section
                        headerSection
                        
                        // Current level card
                        currentLevelCard
                        
                        // Progress to next level
                        if let nextLevel = nextLevel {
                            nextLevelProgressCard(nextLevel: nextLevel)
                        }
                        
                        // All levels overview
                        allLevelsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("LIFETIME POINTS")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.energyOrange)
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 20) {
            // Total lifetime points with energy
            VStack(spacing: 12) {
                Text("\(userVM.lifetimePoints)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Text("LIFETIME POINTS")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .tracking(1.5)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Theme.darkGoldGradient, lineWidth: 3)
                    )
                    .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                    .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
            )
        }
    }
    
    private var currentLevelCard: some View {
        VStack(spacing: 20) {
            HStack {
                Text(currentLevel.icon)
                    .font(.system(size: 36))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentLevel.name)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [currentLevel.color, currentLevel.color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .tracking(0.5)
                    
                    Text(currentLevel.description)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                
                Spacer()
            }
            
            // Progress within current level
            VStack(spacing: 12) {
                HStack {
                    Text("\(userVM.lifetimePoints - currentLevel.minPoints)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Spacer()
                    
                    Text("\(currentLevel.maxPoints - currentLevel.minPoints)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                
                // Enhanced progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.modernCardSecondary)
                            .frame(height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.darkGoldGradient, lineWidth: 2)
                            )
                        
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        currentLevel.color,
                                        currentLevel.color.opacity(0.8),
                                        currentLevel.color
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progressToNextLevel, height: 16)
                            .shadow(color: currentLevel.color.opacity(0.4), radius: 8, x: 0, y: 4)
                            .animation(.easeInOut(duration: 0.5), value: progressToNextLevel)
                    }
                }
                .frame(height: 16)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.darkGoldGradient, lineWidth: 3)
                )
                .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)
                .shadow(color: Theme.cardShadow, radius: 16, x: 0, y: 8)
        )
    }
    
    private func nextLevelProgressCard(nextLevel: LifetimeLevel) -> some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT LEVEL")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .tracking(1.0)
                    
                    Text(nextLevel.name)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [nextLevel.color, nextLevel.color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .tracking(0.5)
                }
                
                Spacer()
                
                Text(nextLevel.icon)
                    .font(.system(size: 32))
            }
            
            HStack {
                Text("\(nextLevel.minPoints - userVM.lifetimePoints) points needed")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Spacer()
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.energyGradient, lineWidth: 2)
                )
                .shadow(color: Theme.energyOrange.opacity(0.2), radius: 12, x: 0, y: 6)
        )
    }
    
    private var allLevelsSection: some View {
        VStack(spacing: 20) {
            Text("ALL LEVELS")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .tracking(1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVStack(spacing: 16) {
                ForEach(levels, id: \.name) { level in
                    levelRow(level: level)
                }
            }
        }
    }
    
    private func levelRow(level: LifetimeLevel) -> some View {
        let isCurrentLevel = level.name == currentLevel.name
        let isUnlocked = userVM.lifetimePoints >= level.minPoints
        
        return HStack(spacing: 16) {
            // Level icon
            Text(level.icon)
                .font(.system(size: 28))
                .opacity(isUnlocked ? 1.0 : 0.3)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(level.name)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(
                            isUnlocked ? 
                            LinearGradient(
                                colors: [level.color, level.color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Theme.modernSecondary, Theme.modernSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .tracking(0.5)
                    
                    if isCurrentLevel {
                        Text("• CURRENT")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Theme.energyGradient)
                                    .shadow(color: Theme.energyOrange.opacity(0.3), radius: 4, x: 0, y: 2)
                            )
                    }
                }
                
                Text(level.description)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                
                Text("\(level.minPoints) - \(level.maxPoints) points")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }
            
            Spacer()
            
            // Status indicator
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.energyGreen)
                    .font(.system(size: 24))
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(Theme.modernSecondary)
                    .font(.system(size: 18))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isCurrentLevel ? level.color.opacity(0.1) : Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isCurrentLevel ? 
                            LinearGradient(
                                colors: [level.color, level.color.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [Theme.modernSecondary.opacity(0.3), Theme.modernSecondary.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(
                    color: isCurrentLevel ? level.color.opacity(0.2) : Theme.cardShadow,
                    radius: isCurrentLevel ? 12 : 8,
                    x: 0,
                    y: isCurrentLevel ? 6 : 4
                )
        )
    }
}

struct LifetimeLevel {
    let name: String
    let minPoints: Int
    let maxPoints: Int
    let color: Color
    let icon: String
    let description: String
}

#Preview {
    LifetimePointsView()
        .environmentObject(UserViewModel())
} 