import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("Coming Soon")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Community")
        }
    }
}
