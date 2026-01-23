import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

class UserDetailViewModel: ObservableObject {
    @Published var firstName: String = ""
    @Published var phoneNumber: String = ""
    @Published var points: String = ""
    @Published var isVerified: Bool = false
    @Published var isAdmin: Bool = false
    @Published var isEmployee: Bool = false
    @Published var profileImage: UIImage?
    @Published var selectedImage: UIImage? {
        didSet {
            if let image = selectedImage {
                profileImage = image
            }
        }
    }
    @Published var showImagePicker = false
    @Published var showDeleteConfirmation = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    private var currentUser: UserAccount?
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    func loadUserData(user: UserAccount) {
        currentUser = user
        firstName = user.firstName
        phoneNumber = user.phoneNumber
        points = String(user.points)
        isVerified = user.isVerified
        isAdmin = user.isAdmin
        isEmployee = user.isEmployee
        
        // Load profile image if exists
        if let photoURL = user.profilePhotoURL {
            loadProfileImage(from: photoURL)
        }
    }
    
    private func loadProfileImage(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let data = data, let image = UIImage(data: data) {
                    self?.profileImage = image
                }
            }
        }.resume()
    }
    
    func saveChanges(completion: @escaping () -> Void) {
        guard let user = currentUser else {
            showError(message: "No user data available")
            return
        }
        
        isLoading = true
        
        // Validate points input
        guard let pointsInt = Int(points), pointsInt >= 0 else {
            showError(message: "Points must be a valid non-negative number")
            return
        }
        
        var updateData: [String: Any] = [
            "firstName": firstName,
            "phone": phoneNumber,
            "points": pointsInt,
            "isVerified": isVerified,
            "isAdmin": isAdmin,
            "isEmployee": isEmployee
        ]
        
        // If there's a new image selected, upload it first
        if let newImage = selectedImage {
            uploadProfilePhoto(newImage, for: user.id) { [weak self] success, photoURL in
                if success, let photoURL = photoURL {
                    updateData["profilePhotoURL"] = photoURL
                    self?.updateUserDataTransactional(userId: user.id, data: updateData, requestedPoints: pointsInt) { prevPoints, delta, success in
                        if success {
                            self?.maybeLogAdminAdjustment(userId: user.id, previousPoints: prevPoints, newPoints: pointsInt, delta: delta)
                            completion()
                        } else {
                            self?.showError(message: "Failed to update user")
                        }
                    }
                } else {
                    self?.isLoading = false
                    self?.showError(message: "Failed to upload profile photo")
                }
            }
        } else {
            updateUserDataTransactional(userId: user.id, data: updateData, requestedPoints: pointsInt) { [weak self] prevPoints, delta, success in
                if success {
                    self?.maybeLogAdminAdjustment(userId: user.id, previousPoints: prevPoints, newPoints: pointsInt, delta: delta)
                    completion()
                } else {
                    self?.showError(message: "Failed to update user")
                }
            }
        }
    }
    
    private func uploadProfilePhoto(_ image: UIImage, for userId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(false, nil)
            return
        }
        
        let storageRef = storage.reference()
        let photoRef = storageRef.child("profile_photos/\(userId).jpg")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        photoRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                print("Error uploading photo: \(error.localizedDescription)")
                completion(false, nil)
                return
            }
            
            photoRef.downloadURL { url, error in
                if let downloadURL = url {
                    completion(true, downloadURL.absoluteString)
                } else {
                    completion(false, nil)
                }
            }
        }
    }
    
    private func updateUserDataTransactional(userId: String, data: [String: Any], requestedPoints: Int, completion: @escaping (_ previousPoints: Int, _ delta: Int, _ success: Bool) -> Void) {
        let userRef = db.collection("users").document(userId)
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            do {
                let snapshot = try transaction.getDocument(userRef)
                let currentPoints = (snapshot.data()? ["points"] as? Int) ?? 0
                let delta = requestedPoints - currentPoints
                transaction.updateData(data, forDocument: userRef)
                return ["prev": currentPoints, "delta": delta]
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }, completion: { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.showError(message: "Failed to update user: \(error.localizedDescription)")
                    completion(0, 0, false)
                    return
                }
                if let dict = result as? [String: Int] {
                    let prev = dict["prev"] ?? 0
                    let delta = dict["delta"] ?? 0
                    completion(prev, delta, true)
                } else {
                    completion(0, 0, true)
                }
            }
        })
    }

    private func maybeLogAdminAdjustment(userId: String, previousPoints: Int, newPoints: Int, delta: Int) {
        guard delta != 0 else { return }
        let transaction = PointsTransaction(
            userId: userId,
            type: .adminAdjustment,
            amount: delta,
            description: "Points adjusted by admin",
            metadata: [
                "previousPoints": previousPoints,
                "newPoints": newPoints
            ]
        )
        db.collection("pointsTransactions").document(transaction.id).setData(transaction.toFirestore()) { error in
            if let error = error {
                print("❌ Error logging admin adjustment: \(error.localizedDescription)")
            } else {
                print("✅ Admin points adjustment logged (delta: \(delta))")
            }
        }
    }
    
    func removeProfilePhoto() {
        guard let user = currentUser else { return }
        
        isLoading = true
        
        // Remove from Firestore
        db.collection("users").document(user.id).updateData([
            "profilePhotoURL": FieldValue.delete()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.showError(message: "Failed to remove profile photo: \(error.localizedDescription)")
                } else {
                    // Remove from Storage if URL exists
                    if let photoURL = user.profilePhotoURL {
                        self?.removePhotoFromStorage(photoURL)
                    }
                    
                    self?.profileImage = nil
                    self?.selectedImage = nil
                }
            }
        }
    }
    
    private func removePhotoFromStorage(_ photoURL: String) {
        guard let url = URL(string: photoURL) else { return }
        
        let storageRef = storage.reference(forURL: photoURL)
        storageRef.delete { error in
            if let error = error {
                print("Error deleting photo from storage: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteAccount(completion: @escaping () -> Void) {
        guard let user = currentUser else {
            showError(message: "No user data available")
            return
        }
        
        isLoading = true
        
        // Use centralized deletion service for comprehensive cleanup
        AccountDeletionService.shared.deleteAccount(
            uid: user.id,
            profilePhotoURL: user.profilePhotoURL
        ) { [weak self] success in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if !success {
                    self?.showError(message: "Account deletion completed with some errors. Some data may remain.")
                }
                
                // Note: We don't delete the Firebase Auth user here as that requires admin privileges
                // The user will need to be deleted manually from the Firebase Console
                
                completion()
            }
        }
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
} 