//
//  UserViewModel.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/25/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine

class UserViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var firstName: String = ""
    @Published var points: Int = 0
    @Published var lifetimePoints: Int = 0 // Total points earned (not spent)
    // ✅ NEW: Added properties to hold the user's avatar customization.
    @Published var avatarEmoji: String = "👤" // Default emoji
    @Published var avatarColorName: String = "gray" // Default color
    @Published var profilePhotoURL: String? = nil // Profile photo URL
    @Published var profileImage: UIImage? = nil // Local profile image
    
    @Published var isLoading: Bool = true
    @Published var isUploadingPhoto: Bool = false

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
            self.profilePhotoURL = data["profilePhotoURL"] as? String
            
            // Load profile image if URL exists
            if let photoURL = self.profilePhotoURL {
                print("🖼️ Loading profile image from URL: \(photoURL)")
                self.loadProfileImage(from: photoURL)
            } else {
                print("🖼️ No profile photo URL found")
                self.profileImage = nil
            }
            
            self.isLoading = false
        }
    }
    
    // MARK: - Photo Management
    
    func uploadProfilePhoto(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ No user ID for photo upload")
            completion(false)
            return
        }
        
        print("📤 Starting photo upload for user: \(uid)")
        isUploadingPhoto = true
        
        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to compress image")
            isUploadingPhoto = false
            completion(false)
            return
        }
        
        print("📦 Image compressed, size: \(imageData.count) bytes")
        
        let storage = Storage.storage()
        let storageRef = storage.reference()
        let photoRef = storageRef.child("profile_photos/\(uid).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        photoRef.putData(imageData, metadata: metadata) { metadata, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error uploading photo: \(error.localizedDescription)")
                    self.isUploadingPhoto = false
                    completion(false)
                    return
                }
                
                print("📤 Photo uploaded to Storage successfully")
                
                // Get download URL
                photoRef.downloadURL { url, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error getting download URL: \(error.localizedDescription)")
                            self.isUploadingPhoto = false
                            completion(false)
                            return
                        }
                        
                        if let downloadURL = url {
                            print("🔗 Got download URL: \(downloadURL.absoluteString)")
                            // Save URL to Firestore
                            self.saveProfilePhotoURL(downloadURL.absoluteString) { success in
                                self.isUploadingPhoto = false
                                if success {
                                    print("✅ Profile photo URL saved to Firestore")
                                    self.profilePhotoURL = downloadURL.absoluteString
                                    self.profileImage = image
                                    print("🖼️ Profile image updated locally: \(self.profileImage != nil)")
                                }
                                completion(success)
                            }
                        } else {
                            print("❌ Failed to get download URL")
                            self.isUploadingPhoto = false
                            completion(false)
                        }
                    }
                }
            }
        }
    }
    
    private func saveProfilePhotoURL(_ url: String, completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData([
            "profilePhotoURL": url
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error saving photo URL: \(error.localizedDescription)")
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }
    
    private func loadProfileImage(from urlString: String) {
        guard let url = URL(string: urlString) else { 
            print("❌ Invalid URL: \(urlString)")
            return 
        }
        
        print("🖼️ Loading image from URL: \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let data = data, let image = UIImage(data: data) {
                    print("✅ Image loaded successfully, size: \(data.count) bytes")
                    self.profileImage = image
                    print("🖼️ Profile image set: \(self.profileImage != nil)")
                } else {
                    print("❌ Failed to create image from data")
                }
            }
        }.resume()
    }
    
    func removeProfilePhoto(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        // Delete from Storage
        if let photoURL = profilePhotoURL {
            let storage = Storage.storage()
            let storageRef = storage.reference()
            let photoRef = storageRef.child("profile_photos/\(uid).jpg")
            
            photoRef.delete { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Error deleting photo: \(error.localizedDescription)")
                    }
                    
                    // Remove from Firestore
                    let db = Firestore.firestore()
                    db.collection("users").document(uid).updateData([
                        "profilePhotoURL": FieldValue.delete()
                    ]) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("Error removing photo URL: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                self.profilePhotoURL = nil
                                self.profileImage = nil
                                completion(true)
                            }
                        }
                    }
                }
            }
        } else {
            completion(true)
        }
    }
    
    // MARK: - Force Refresh Methods
    
    func forceRefreshProfileImage() {
        print("🔄 Force refreshing profile image")
        if let photoURL = profilePhotoURL {
            loadProfileImage(from: photoURL)
        } else {
            profileImage = nil
        }
    }
    
    func clearProfileImageCache() {
        print("🗑️ Clearing profile image cache")
        profileImage = nil
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
