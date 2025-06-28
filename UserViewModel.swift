//
//  UserViewModel.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/25/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

class UserViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var firstName: String = ""
    @Published var points: Int = 0
    @Published var lifetimePoints: Int = 0 // Total points earned (not spent)
    // ✅ NEW: Added properties to hold the user's avatar customization.
    @Published var avatarEmoji: String = "👤" // Default emoji
    @Published var avatarColorName: String = "gray" // Default color
    
    @Published var isLoading: Bool = true

    // ✅ NEW: A computed property to safely convert the color name string into a usable SwiftUI Color.
    var avatarColor: Color {
        switch avatarColorName.lowercased() {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        default: return .gray // A safe default if the color name is unknown.
        }
    }
    
    // MARK: - Methods
    
    // Updated to load the new avatar fields from Firestore.
    func loadUserData() {
        guard let uid = Auth.auth().currentUser?.uid else {
            self.isLoading = false
            return
        }

        let db = Firestore.firestore()
        db.collection("users").document(uid).addSnapshotListener { snapshot, error in
            // Using a snapshot listener will update the UI in real-time if the data changes.
            if let error = error {
                print("Error loading user data: \(error.localizedDescription)")
                self.isLoading = false
                return
            }
            
            guard let data = snapshot?.data() else {
                print("No user data found.")
                self.isLoading = false
                return
            }
            
            // Assign fetched data to our properties.
            self.firstName = data["firstName"] as? String ?? "User"
            self.points = data["points"] as? Int ?? 0
            self.lifetimePoints = data["lifetimePoints"] as? Int ?? self.points // Initialize with current points if not set
            self.avatarEmoji = data["avatarEmoji"] as? String ?? "👤"
            self.avatarColorName = data["avatarColor"] as? String ?? "gray"
            self.isLoading = false
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
