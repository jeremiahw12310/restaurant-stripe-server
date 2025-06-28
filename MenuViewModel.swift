import Foundation
import FirebaseFirestore
import Combine

class MenuViewModel: ObservableObject {
    @Published var menuCategories = [MenuCategory]()
    @Published var isLoading = true
    @Published var errorMessage = ""

    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    init() {
        fetchMenu()
    }
    
    deinit {
        // Stop listening for changes when the view model is deallocated.
        listenerRegistration?.remove()
    }

    func fetchMenu() {
        isLoading = true
        // ✅ CHANGE: Using an addSnapshotListener to get real-time menu updates.
        // If you change a price in Firestore, the app will update automatically.
        listenerRegistration = db.collection("menu").addSnapshotListener { [weak self] (querySnapshot, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Failed to fetch menu: \(error.localizedDescription)"
                self.isLoading = false
                return
            }

            guard let documents = querySnapshot?.documents else {
                self.errorMessage = "No menu found."
                self.isLoading = false
                return
            }

            self.menuCategories = documents.compactMap { document in
                try? document.data(as: MenuCategory.self)
            }
            
            self.isLoading = false
        }
    }
}
