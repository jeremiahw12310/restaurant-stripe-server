import SwiftUI

struct DrinkTypeSelectionView: View {
    @ObservedObject var menuVM: MenuViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: DrinkType = .lemonade
    
    enum DrinkType {
        case lemonade
        case soda
        
        var title: String {
            switch self {
            case .lemonade:
                return "Lemonade"
            case .soda:
                return "Soda"
            }
        }
        
        var icon: String {
            switch self {
            case .lemonade:
                return "drop.fill"
            case .soda:
                return "bubble.left.and.bubble.right.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .lemonade:
                return .yellow
            case .soda:
                return .blue
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("Choose Your Drink Type")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.top, 40)
                
                Text("Select whether you'd like a refreshing lemonade or a bubbly soda")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                VStack(spacing: 20) {
                    Button(action: {
                        selectedType = .lemonade
                    }) {
                        HStack(spacing: 15) {
                            Image(systemName: DrinkType.lemonade.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(DrinkType.lemonade.color)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DrinkType.lemonade.title)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text("Refreshing citrus flavors")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedType == .lemonade {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(DrinkType.lemonade.color)
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedType == .lemonade ? DrinkType.lemonade.color.opacity(0.1) : Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(selectedType == .lemonade ? DrinkType.lemonade.color : Color.clear, lineWidth: 2)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        selectedType = .soda
                    }) {
                        HStack(spacing: 15) {
                            Image(systemName: DrinkType.soda.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(DrinkType.soda.color)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DrinkType.soda.title)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text("Bubbly carbonated drinks")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedType == .soda {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(DrinkType.soda.color)
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedType == .soda ? DrinkType.soda.color.opacity(0.1) : Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(selectedType == .soda ? DrinkType.soda.color : Color.clear, lineWidth: 2)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                NavigationLink(destination: DrinkFlavorSelectionView(menuVM: menuVM, isLemonade: selectedType == .lemonade)) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Continue to Flavors")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        selectedType.color,
                                        selectedType.color.opacity(0.8)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: selectedType.color.opacity(0.3), radius: 10, x: 0, y: 5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Drink Type")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
} 