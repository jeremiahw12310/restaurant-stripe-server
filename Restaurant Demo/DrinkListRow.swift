import SwiftUI

struct DrinkListRow: View {
    let item: MenuItem
    let isPressed: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Drink name on the left
            Text(item.id)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 16)
            
            // Price on the right
            Text(String(format: "$%.2f", item.price))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .frame(alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.black)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 0) {
            DrinkListRow(
                item: MenuItem(
                    id: "Jasmine Milk Tea",
                    description: "Refreshing jasmine milk tea",
                    price: 6.50,
                    imageURL: "",
                    isAvailable: true,
                    paymentLinkID: ""
                ),
                isPressed: false
            )
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            DrinkListRow(
                item: MenuItem(
                    id: "Thai Milk Tea",
                    description: "Classic Thai milk tea",
                    price: 6.50,
                    imageURL: "",
                    isAvailable: true,
                    paymentLinkID: ""
                ),
                isPressed: false
            )
        }
    }
}








