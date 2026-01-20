import SwiftUI

// MARK: - White Text Shadow Modifier
extension View {
    /// Adds a subtle black shadow behind white or light-colored text so it remains legible against bright backgrounds.
    /// Usage: `Text("Hello") .foregroundColor(.white) .whiteTextShadow()`
    @ViewBuilder
    func whiteTextShadow(opacity: Double = 0.8, radius: CGFloat = 1, x: CGFloat = 0, y: CGFloat = 1) -> some View {
        self.shadow(color: Color.black.opacity(opacity), radius: radius, x: x, y: y)
    }
} 