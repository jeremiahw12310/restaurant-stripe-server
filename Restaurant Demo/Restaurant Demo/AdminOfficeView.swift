import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

// MARK: - Admin Office View (Entry Point)
// This view now shows the AdminOverviewView as the landing page

struct AdminOfficeView: View {
    var body: some View {
        AdminOverviewView()
    }
}

struct AdminUserRow: View {
    let user: UserAccount
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(user.avatarColor)
                .frame(width: 48, height: 48)
                .overlay(Text(user.avatarEmoji).font(.title3))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.firstName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if user.isAdmin {
                        Text("Admin")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(user.points) pts")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                    
                    Text("Joined \(formatted(date: user.accountCreatedDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}


