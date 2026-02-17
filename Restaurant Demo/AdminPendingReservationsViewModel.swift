import SwiftUI
import FirebaseAuth

/// Fetches pending reservations count for staff (admin/employee) so Home and other views can show the "New reservation" card.
@MainActor
final class AdminPendingReservationsViewModel: ObservableObject {
    @Published var pendingReservationsCount: Int = 0

    func load() async {
        guard let user = Auth.auth().currentUser else {
            pendingReservationsCount = 0
            return
        }
        do {
            let token = try await user.getIDTokenResult(forcingRefresh: false).token
            guard let url = URL(string: "\(Config.backendURL)/reservations?status=pending&limit=50") else {
                pendingReservationsCount = 0
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.configured.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["reservations"] as? [[String: Any]] else {
                pendingReservationsCount = 0
                return
            }
            pendingReservationsCount = list.count
        } catch {
            pendingReservationsCount = 0
        }
    }
}
