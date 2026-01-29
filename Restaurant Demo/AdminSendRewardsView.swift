import SwiftUI
import FirebaseAuth
import Foundation

struct AdminSendRewardsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AdminSendRewardsViewModel()
    
    @State private var selectedTab: RewardType = .existing
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showConfirmation = false
    
    enum RewardType {
        case existing
        case custom
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.95, green: 0.95, blue: 0.97)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Card
                        headerCard
                        
                        // Tab Selector
                        tabSelector
                        
                        // Content based on selected tab
                        if selectedTab == .existing {
                            existingRewardSection
                        } else {
                            customRewardSection
                        }
                        
                        // Recipient Selection
                        recipientSelectionSection
                        
                        // Preview
                        if viewModel.canShowPreview {
                            previewSection
                        }
                        
                        // Send Button
                        sendButton
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Reward Sent", isPresented: $viewModel.showSuccessAlert) {
                Button("OK") {
                    viewModel.clearForm()
                    dismiss()
                }
            } message: {
                Text(viewModel.successMessage)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                viewModel.selectedImage = newImage
            }
            .onAppear {
                viewModel.loadRewardOptions()
            }
        }
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "gift.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send Rewards")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    
                    Text("Gift rewards to all or specific customers")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 12) {
            tabButton(title: "Existing Reward", icon: "star.fill", tab: .existing)
            tabButton(title: "Custom Reward", icon: "photo.fill", tab: .custom)
        }
    }
    
    private func tabButton(title: String, icon: String, tab: RewardType) -> some View {
        Button {
            selectedTab = tab
            viewModel.clearForm()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(selectedTab == tab ? .white : .purple)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedTab == tab ? Color.purple : Color.purple.opacity(0.1))
            )
        }
    }
    
    // MARK: - Existing Reward Section
    private var existingRewardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Reward")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.rewardOptions, id: \.title) { reward in
                        Button {
                            viewModel.selectedReward = reward
                        } label: {
                            HStack(spacing: 12) {
                                if let imageName = reward.imageName {
                                    Image(imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 50, height: 50)
                                } else {
                                    Text(reward.icon)
                                        .font(.system(size: 30))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reward.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                    Text(reward.description)
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                if viewModel.selectedReward?.title == reward.title {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 24))
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.selectedReward?.title == reward.title ? Color.purple.opacity(0.1) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(viewModel.selectedReward?.title == reward.title ? Color.purple : Color.gray.opacity(0.2), lineWidth: viewModel.selectedReward?.title == reward.title ? 2 : 1)
                                    )
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Custom Reward Section
    private var customRewardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Custom Reward")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            // Image Upload
            VStack(alignment: .leading, spacing: 8) {
                Text("Reward Image (Optional)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                Button {
                    showImagePicker = true
                } label: {
                    if let image = viewModel.selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Tap to add image")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                                )
                        )
                    }
                }
            }
            
            // Title Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                TextField("Enter reward title", text: $viewModel.customTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 16))
            }
            
            // Description Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                TextEditor(text: $viewModel.customDescription)
                    .frame(minHeight: 100, maxHeight: 150)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .font(.system(size: 16))
            }
            
            // Category Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                
                Picker("Category", selection: $viewModel.customCategory) {
                    ForEach(["Food", "Drinks", "Condiments", "Special"], id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Recipient Selection Section
    private var recipientSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipients")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            HStack(spacing: 12) {
                Button {
                    viewModel.targetType = .all
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 16))
                        Text("All Customers")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(viewModel.targetType == .all ? .white : .blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.targetType == .all ? Color.blue : Color.blue.opacity(0.1))
                    )
                }
                
                Button {
                    viewModel.targetType = .individual
                    if viewModel.users.isEmpty {
                        viewModel.loadUsers()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                        Text("Individual")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(viewModel.targetType == .individual ? .white : .purple)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.targetType == .individual ? Color.purple : Color.purple.opacity(0.1))
                    )
                }
                
                Spacer()
            }
            
            if viewModel.targetType == .individual {
                // User selection list (similar to AdminNotificationsView)
                if !viewModel.users.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.filteredUsers, id: \.id) { user in
                                UserSelectionRow(
                                    user: user,
                                    isSelected: viewModel.selectedUserIds.contains(user.id),
                                    onToggle: {
                                        viewModel.toggleUserSelection(user.id)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                } else if viewModel.isLoadingUsers {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Preview Section
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            
            VStack(alignment: .leading, spacing: 8) {
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let imageName = viewModel.selectedReward?.imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 150)
                }
                
                Text(viewModel.previewTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                
                Text(viewModel.previewDescription)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(3)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Send Button
    private var sendButton: some View {
        Button {
            viewModel.sendReward()
        } label: {
            HStack(spacing: 12) {
                if viewModel.isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                }
                
                Text(viewModel.isSending ? "Sending..." : "Send Reward")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        viewModel.canSend
                            ? LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: viewModel.canSend ? .purple.opacity(0.4) : .clear, radius: 12, x: 0, y: 6)
            )
        }
        .disabled(!viewModel.canSend || viewModel.isSending)
    }
}

// MARK: - View Model
@MainActor
class AdminSendRewardsViewModel: ObservableObject {
    @Published var rewardOptions: [RewardOption] = []
    @Published var selectedReward: RewardOption?
    @Published var selectedImage: UIImage?
    @Published var customTitle: String = ""
    @Published var customDescription: String = ""
    @Published var customCategory: String = "Food"
    @Published var targetType: TargetType = .all
    @Published var selectedUserIds: Set<String> = []
    @Published var users: [NotificationUser] = []
    @Published var isLoadingUsers: Bool = false
    @Published var isSending: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var successMessage: String = ""
    @Published var errorMessage: String = ""
    
    enum TargetType {
        case all
        case individual
    }
    
    var filteredUsers: [NotificationUser] {
        return users
    }
    
    var canSend: Bool {
        if targetType == .individual && selectedUserIds.isEmpty {
            return false
        }
        
        if selectedReward != nil {
            return true // Existing reward selected
        } else {
            // Custom reward - image is optional
            return !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    var canShowPreview: Bool {
        if selectedReward != nil {
            return true
        } else {
            return !customTitle.isEmpty || !customDescription.isEmpty || selectedImage != nil
        }
    }
    
    var previewTitle: String {
        selectedReward?.title ?? customTitle
    }
    
    var previewDescription: String {
        selectedReward?.description ?? customDescription
    }
    
    func loadRewardOptions() {
        let rewardsVM = RewardsViewModel()
        rewardOptions = rewardsVM.rewardOptions
    }
    
    func loadUsers() {
        // Similar to AdminNotificationsViewModel
        isLoadingUsers = true
        
        guard let currentUser = Auth.auth().currentUser else {
            isLoadingUsers = false
            return
        }
        
        currentUser.getIDToken { [weak self] token, error in
            guard let self = self, let token = token else {
                DispatchQueue.main.async {
                    self?.isLoadingUsers = false
                }
                return
            }
            
            guard let url = URL(string: "\(Config.backendURL)/admin/users?limit=100") else {
                DispatchQueue.main.async {
                    self.isLoadingUsers = false
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.configured.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isLoadingUsers = false
                    
                    guard let data = data,
                          let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let rawUsers = json["users"] as? [[String: Any]] else {
                        return
                    }
                    
                    self.users = rawUsers.compactMap { u in
                        if (u["isEmployee"] as? Bool) == true { return nil }
                        let id = u["id"] as? String ?? ""
                        if id.isEmpty { return nil }
                        return NotificationUser(
                            id: id,
                            firstName: u["firstName"] as? String ?? "Unknown",
                            phone: u["phone"] as? String ?? "",
                            avatarEmoji: u["avatarEmoji"] as? String ?? "👤",
                            hasFcmToken: u["hasFcmToken"] as? Bool ?? false,
                            isAdmin: (u["isAdmin"] as? Bool) == true
                        )
                    }
                    .sorted { $0.firstName < $1.firstName }
                }
            }.resume()
        }
    }
    
    func toggleUserSelection(_ userId: String) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }
    
    func sendReward() {
        guard canSend else { return }
        
        isSending = true
        
        Auth.auth().currentUser?.getIDToken { [weak self] idToken, error in
            guard let self = self, let idToken = idToken else {
                DispatchQueue.main.async {
                    self?.isSending = false
                    self?.errorMessage = "Failed to get authentication token"
                    self?.showErrorAlert = true
                }
                return
            }
            
            if self.selectedReward != nil {
                // Send existing reward
                self.sendExistingReward(idToken: idToken)
            } else {
                // Send custom reward
                self.sendCustomReward(idToken: idToken)
            }
        }
    }
    
    private func sendExistingReward(idToken: String) {
        guard let reward = selectedReward else { return }
        
        var requestBody: [String: Any] = [
            "rewardTitle": reward.title,
            "rewardDescription": reward.description,
            "rewardCategory": reward.category,
            "targetType": targetType == .all ? "all" : "individual",
            "userIds": targetType == .individual ? Array(selectedUserIds) : []
        ]
        
        // Only include imageName if it exists
        if let imageName = reward.imageName {
            requestBody["imageName"] = imageName
        }
        
        guard let url = URL(string: "\(Config.backendURL)/admin/rewards/gift") else {
            DispatchQueue.main.async {
                self.isSending = false
                self.errorMessage = "Invalid server URL"
                self.showErrorAlert = true
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.configured.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSending = false
                
                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    self?.showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Invalid response"
                    self?.showErrorAlert = true
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let notificationCount = json["notificationCount"] as? Int ?? 0
                        self?.successMessage = "Reward sent successfully!\n\(notificationCount) customers notified"
                    } else {
                        self?.successMessage = "Reward sent successfully!"
                    }
                    self?.showSuccessAlert = true
                } else {
                    if let data = data {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMsg = json["error"] as? String {
                            self?.errorMessage = errorMsg
                        } else if let responseString = String(data: data, encoding: .utf8) {
                            self?.errorMessage = "Failed to send reward (status: \(httpResponse.statusCode))\n\(responseString)"
                        } else {
                            self?.errorMessage = "Failed to send reward (status: \(httpResponse.statusCode))"
                        }
                    } else {
                        self?.errorMessage = "Failed to send reward (status: \(httpResponse.statusCode))"
                    }
                    self?.showErrorAlert = true
                }
            }
        }.resume()
    }
    
    private func sendCustomReward(idToken: String) {
        guard let url = URL(string: "\(Config.backendURL)/admin/rewards/gift/custom") else {
            DispatchQueue.main.async {
                self.isSending = false
                self.errorMessage = "Invalid server URL"
                self.showErrorAlert = true
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add image if provided
        if let image = selectedImage {
            // Convert image to JPEG data
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                DispatchQueue.main.async {
                    self.isSending = false
                    self.errorMessage = "Failed to process image"
                    self.showErrorAlert = true
                }
                return
            }
            
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"reward.jpg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            body.appendString("\r\n")
        }
        
        // Add other fields
        var userIdsString = ""
        if targetType == .individual {
            if let userIdsData = try? JSONSerialization.data(withJSONObject: Array(selectedUserIds)),
               let userIdsJson = String(data: userIdsData, encoding: .utf8) {
                userIdsString = userIdsJson
            }
        }
        
        let fields: [String: String] = [
            "rewardTitle": customTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "rewardDescription": customDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            "rewardCategory": customCategory,
            "targetType": targetType == .all ? "all" : "individual",
            "userIds": userIdsString
        ]
        
        for (key, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString(value)
            body.appendString("\r\n")
        }
        
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body
        
        URLSession.configured.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSending = false
                
                if let error = error {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    self?.showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Invalid response"
                    self?.showErrorAlert = true
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let notificationCount = json["notificationCount"] as? Int ?? 0
                        self?.successMessage = "Custom reward sent successfully!\n\(notificationCount) customers notified"
                    } else {
                        self?.successMessage = "Custom reward sent successfully!"
                    }
                    self?.showSuccessAlert = true
                } else {
                    if let data = data {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMsg = json["error"] as? String {
                            self?.errorMessage = errorMsg
                        } else if let responseString = String(data: data, encoding: .utf8) {
                            self?.errorMessage = "Failed to send custom reward (status: \(httpResponse.statusCode))\n\(responseString)"
                        } else {
                            self?.errorMessage = "Failed to send custom reward (status: \(httpResponse.statusCode))"
                        }
                    } else {
                        self?.errorMessage = "Failed to send custom reward (status: \(httpResponse.statusCode))"
                    }
                    self?.showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func clearForm() {
        selectedReward = nil
        selectedImage = nil
        customTitle = ""
        customDescription = ""
        customCategory = "Food"
        targetType = .all
        selectedUserIds.removeAll()
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

