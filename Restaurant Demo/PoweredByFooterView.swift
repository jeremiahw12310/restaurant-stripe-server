import SwiftUI

struct PoweredByFooterView: View {
    var body: some View {
        Image("poweredby")
            .resizable()
            .scaledToFit()
            // "Medium" size: tweak if you want bigger/smaller.
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .accessibilityLabel("Powered by")
    }
}

#if DEBUG
struct PoweredByFooterView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(0..<10) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 80)
                }
                PoweredByFooterView()
            }
            .padding()
        }
    }
}
#endif
