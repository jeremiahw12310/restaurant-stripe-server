import SwiftUI
import Vision
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit

extension Notification.Name {
    static let didEarnPoints = Notification.Name("didEarnPoints")
}

struct ReceiptScanView: View {
    @StateObject private var userVM = UserViewModel()
    @State private var showCamera = false
    @State private var scannedImage: UIImage?
    @State private var isProcessing = false
    @State private var showCongratulations = false
    @State private var showReceiptUsedScreen = false
    @State private var receiptTotal: Double = 0.0
    @State private var pointsEarned: Int = 0
    @State private var errorMessage = ""
    @State private var showPermissionAlert = false
    @State private var scannedText = ""
    @Environment(\.colorScheme) var colorScheme
    var onPointsEarned: ((Int) -> Void)? = nil
    @State private var showLoadingOverlay = false
    @State private var showDumplingRain = false
    @State private var shouldSwitchToHome = false
    @State private var lastOrderNumber: String? = nil
    @State private var lastOrderDate: String? = nil
    @State private var usedReceipts: Set<String> = [] // Local cache: "orderNumber|orderDate"
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            if showReceiptUsedScreen {
                receiptUsedView
            } else if showCongratulations {
                ZStack {
                    if showDumplingRain {
                        DumplingRainView()
                    }
                    congratulationsView
                }
            } else {
                mainView
            }
            if isProcessing || showLoadingOverlay {
                loadingOverlay
            }
        }
        .onAppear {
            userVM.loadUserData()
            loadUsedReceiptsFromFirestore()
        }
        .onChange(of: shouldSwitchToHome) { newValue in
            if newValue {
                switchToHomeTab()
                // Reset all relevant state
                showReceiptUsedScreen = false
                showCongratulations = false
                errorMessage = ""
                showDumplingRain = false
                shouldSwitchToHome = false
            }
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable camera access in Settings to scan receipts and earn points.")
        }
        .sheet(isPresented: $showCamera) {
            CameraViewWithOverlay(image: $scannedImage) { image in
                showCamera = false
                if let image = image {
                    showLoadingOverlay = true
                    processReceiptImage(image)
                }
            }
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color(.systemBackground).opacity(0.95).ignoresSafeArea()
            VStack(spacing: 32) {
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(radius: 20)
                Text("Scanning your receipt...")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
        .transition(.opacity)
        .zIndex(10)
    }
    
    private var mainView: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                Text("Scan Your Receipt")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Earn 5 points for every dollar spent!")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            VStack(spacing: 20) {
                instructionCard(icon: "camera.fill", title: "Take a Photo", description: "Center your receipt in the camera frame")
                instructionCard(icon: "brain.head.profile", title: "AI Processing", description: "Our AI reads the total amount")
                instructionCard(icon: "star.fill", title: "Earn Points", description: "Get 5 points per dollar spent")
            }
            .padding(.horizontal, 20)
            Spacer()
            VStack(spacing: 16) {
                if isProcessing {
                    EmptyView()
                } else {
                    Button(action: {
                        checkCameraPermission()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Scan Receipt")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 30)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .blue,
                                            .blue.opacity(0.8)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
    
    private var congratulationsView: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 5)
                Text("Congratulations!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("You earned \(pointsEarned) points!")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.blue)
            }
            VStack(spacing: 16) {
                detailRow(title: "Receipt Total", value: String(format: "$%.2f", receiptTotal))
                detailRow(title: "Points Earned", value: "\(pointsEarned) points")
                detailRow(title: "Rate", value: "5 points per dollar")
            }
            .padding(25)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.1), radius: 15, x: 0, y: 8)
            )
            .padding(.horizontal, 20)
            Spacer()
            
            // Auto-dismiss message
            VStack(spacing: 8) {
                Text("Returning to home screen...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.blue)
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            // Auto-dismiss after 2.5 seconds for smoother transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // Trigger home tab switch immediately when starting to fade out
                shouldSwitchToHome = true
                
                // Post notification for HomeView to animate points
                NotificationCenter.default.post(name: .didEarnPoints, object: nil, userInfo: ["points": pointsEarned])
                
                // Call the callback if provided
                onPointsEarned?(pointsEarned)
                
                // Fade out the congratulations screen
                withAnimation(.easeInOut(duration: 0.6)) {
                    showCongratulations = false
                    errorMessage = ""
                    showDumplingRain = false
                }
            }
        }
    }
    
    private var receiptUsedView: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                Text("Receipt Already Used")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("A receipt cannot be used more than once. +0 points")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                if let order = lastOrderNumber, let date = lastOrderDate {
                    Text("Order #: \(order)\nDate: \(date)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            Button("Return to Home") {
                shouldSwitchToHome = true
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.red))
            .padding(.bottom, 60)
        }
        .transition(.opacity)
    }
    
    private func instructionCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
    
    private func switchToHomeTab() {
        // Since this is a tab-based app, we need to use a different approach
        // We'll post a notification that the main app can listen to
        NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
    }
    
    private func processReceiptImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = ""
        scannedText = ""
        let currentPoints = userVM.points
        uploadReceiptImage(image) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                self.showLoadingOverlay = false
                switch result {
                case .success(let json):
                    if let orderNumberRaw = json["orderNumber"] as? String,
                       let orderTotal = json["orderTotal"] as? Double,
                       let orderDateRaw = json["orderDate"] as? String {
                        let orderNumber = orderNumberRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let orderDate = extractMonthDay(from: orderDateRaw)
                        self.scannedText = "Order #: \(orderNumber)\nDate: \(orderDate)\nTotal: $\(orderTotal)"
                        self.receiptTotal = orderTotal
                        self.pointsEarned = Int(orderTotal * 5)
                        self.lastOrderNumber = orderNumber
                        self.lastOrderDate = orderDate
                        let receiptKey = "\(orderNumber)|\(orderDate)"
                        if usedReceipts.contains(receiptKey) {
                            withAnimation { self.showReceiptUsedScreen = true }
                            return
                        }
                        checkReceiptDuplicate(orderNumber: orderNumber, orderDate: orderDate) { isDuplicate in
                            if isDuplicate {
                                withAnimation { self.showReceiptUsedScreen = true }
                            } else {
                                saveUsedReceipt(orderNumber: orderNumber, orderDate: orderDate) {
                                    usedReceipts.insert(receiptKey)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        withAnimation {
                                            self.showCongratulations = true
                                            self.showDumplingRain = true
                                        }
                                        self.updateUserPoints()
                                    }
                                }
                            }
                        }
                    } else {
                        self.errorMessage = "Could not extract all fields from receipt."
                    }
                case .failure(let error):
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Helper to extract MM-DD from a date string (ignoring year)
    private func extractMonthDay(from dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        // Try to match YYYY-MM-DD or MM/DD/YYYY or MM-DD-YYYY
        let patterns = [
            "^(\\d{4})-(\\d{2})-(\\d{2})$", // YYYY-MM-DD
            "^(\\d{2})/(\\d{2})/(\\d{4})$", // MM/DD/YYYY
            "^(\\d{2})-(\\d{2})-(\\d{4})$"  // MM-DD-YYYY
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                if pattern == patterns[0], match.numberOfRanges == 4 {
                    // YYYY-MM-DD
                    let mm = (trimmed as NSString).substring(with: match.range(at: 2))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 3))
                    return "\(mm)-\(dd)"
                } else if pattern == patterns[1], match.numberOfRanges == 4 {
                    // MM/DD/YYYY
                    let mm = (trimmed as NSString).substring(with: match.range(at: 1))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 2))
                    return "\(mm)-\(dd)"
                } else if pattern == patterns[2], match.numberOfRanges == 4 {
                    // MM-DD-YYYY
                    let mm = (trimmed as NSString).substring(with: match.range(at: 1))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 2))
                    return "\(mm)-\(dd)"
                }
            }
        }
        // If no match, return the original string
        return trimmed
    }
    
    private func updateUserPoints() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let newPoints = userVM.points + pointsEarned
        let newLifetimePoints = userVM.lifetimePoints + pointsEarned
        db.collection("users").document(uid).updateData([
            "points": newPoints,
            "lifetimePoints": newLifetimePoints
        ]) { error in
            if let error = error {
                print("Error updating points: \(error.localizedDescription)")
            } else {
                userVM.points = newPoints
                userVM.lifetimePoints = newLifetimePoints
            }
        }
    }
    
    private func checkCameraPermission() {
        errorMessage = ""
        scannedText = ""
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showPermissionAlert = true
        @unknown default:
            showPermissionAlert = true
        }
    }
    
    // Load all used receipts from global Firestore collection into the local set
    private func loadUsedReceiptsFromFirestore() {
        let db = Firestore.firestore()
        db.collection("usedReceipts").getDocuments { snapshot, error in
            if let error = error {
                print("Error loading used receipts: \(error.localizedDescription)")
            } else if let docs = snapshot?.documents {
                let keys = docs.compactMap { doc -> String? in
                    let orderNumber = (doc["orderNumber"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    let orderDateRaw = (doc["orderDate"] as? String) ?? ""
                    let orderDate = extractMonthDay(from: orderDateRaw)
                    if !orderNumber.isEmpty && !orderDate.isEmpty {
                        return "\(orderNumber)|\(orderDate)"
                    }
                    return nil
                }
                usedReceipts = Set(keys)
                print("Loaded used receipts: \(usedReceipts)")
            }
        }
    }
    
    // Check global Firestore collection for duplicate receipt
    private func checkReceiptDuplicate(orderNumber: String, orderDate: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        db.collection("usedReceipts")
            .whereField("orderNumber", isEqualTo: orderNumber)
            .whereField("orderDate", isEqualTo: orderDate)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking duplicate receipt: \(error.localizedDescription)")
                    completion(false)
                } else if let docs = snapshot?.documents, !docs.isEmpty {
                    completion(true)
                } else {
                    completion(false)
                }
            }
    }
    
    // Save used receipt to global Firestore collection and update local set after write
    private func saveUsedReceipt(orderNumber: String, orderDate: String, completion: (() -> Void)? = nil) {
        let db = Firestore.firestore()
        let data: [String: Any] = [
            "orderNumber": orderNumber,
            "orderDate": orderDate,
            "timestamp": FieldValue.serverTimestamp()
        ]
        db.collection("usedReceipts").addDocument(data: data) { error in
            if let error = error {
                print("Error saving used receipt: \(error.localizedDescription)")
            }
            completion?()
        }
    }
}

struct CameraViewWithOverlay: View {
    @Binding var image: UIImage?
    var onImageCaptured: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var cameraController = CameraController()
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraController: cameraController)
                .ignoresSafeArea()
            
            // Loading overlay
            if !cameraController.isSetup {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            ProgressView()
                                .scaleEffect(1.8)
                                .tint(.white)
                            Text("Setting up camera...")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                    )
            }
            
            // Error overlay
            if let errorMessage = cameraController.errorMessage {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            Text("Camera Error")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            VStack(spacing: 12) {
                                Button("Try Again") {
                                    cameraController.errorMessage = nil
                                    cameraController.checkPermissionAndSetup()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 16, weight: .semibold))
                                
                                Button("Cancel") {
                                    dismiss()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    )
            }
            
            // Receipt guide overlay (only show when camera is ready)
            if cameraController.isSetup && cameraController.errorMessage == nil {
                VStack(spacing: 0) {
                    // Top section with cancel button
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Cancel")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                        }
                        
                        Spacer()
                        
                        // Title
                        Text("Scan Receipt")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Placeholder for balance
                        Color.clear
                            .frame(width: 80)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    
                    Spacer()
                    
                    // Receipt guide area
                    VStack(spacing: 24) {
                        // Receipt guide rectangle - skinnier and taller
                        ZStack {
                            // Semi-transparent overlay with cutout
                            Color.black.opacity(0.5)
                                .ignoresSafeArea()
                                .mask(
                                    Rectangle()
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .frame(width: 240, height: 420)
                                                .blendMode(.destinationOut)
                                        )
                                )
                            
                            // Receipt guide frame
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 240, height: 420)
                                .shadow(color: .white.opacity(0.3), radius: 8, x: 0, y: 0)
                                .overlay(
                                    // Corner indicators
                                    ZStack {
                                        // Top-left corner
                                        VStack {
                                            HStack {
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 20, height: 3)
                                                Spacer()
                                            }
                                            HStack {
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 3, height: 20)
                                                Spacer()
                                            }
                                        }
                                        .frame(width: 240, height: 420)
                                        
                                        // Top-right corner
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 20, height: 3)
                                            }
                                            HStack {
                                                Spacer()
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 3, height: 20)
                                            }
                                        }
                                        .frame(width: 240, height: 420)
                                        
                                        // Bottom-left corner
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 3, height: 20)
                                                Spacer()
                                            }
                                            HStack {
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 20, height: 3)
                                                Spacer()
                                            }
                                        }
                                        .frame(width: 240, height: 420)
                                        
                                        // Bottom-right corner
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 3, height: 20)
                                            }
                                            HStack {
                                                Spacer()
                                                Rectangle()
                                                    .fill(Color.white)
                                                    .frame(width: 20, height: 3)
                                            }
                                        }
                                        .frame(width: 240, height: 420)
                                    }
                                )
                        }
                        .frame(width: 240, height: 420)
                        
                        // Instructions
                        VStack(spacing: 8) {
                            Text("Position your receipt within the frame")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Make sure the entire receipt is visible and well-lit")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                    
                    // Bottom section with capture button
                    VStack(spacing: 20) {
                        // Capture button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isCapturing = true
                            }
                            
                            cameraController.capturePhoto { capturedImage in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    isCapturing = false
                                }
                                
                                if let capturedImage = capturedImage {
                                    image = capturedImage
                                    onImageCaptured(capturedImage)
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                                
                                Circle()
                                    .stroke(Color.black, lineWidth: 4)
                                    .frame(width: 70, height: 70)
                                
                                if isCapturing {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .tint(.black)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .scaleEffect(isCapturing ? 0.9 : 1.0)
                        .disabled(isCapturing)
                        
                        // Help text
                        Text("Tap to capture")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            cameraController.checkPermissionAndSetup()
        }
        .onReceive(cameraController.$errorMessage) { errorMessage in
            if let errorMessage = errorMessage {
                print("📸 Camera error: \(errorMessage)")
            }
        }
    }
}

// Camera preview view
struct CameraPreviewView: UIViewRepresentable {
    let cameraController: CameraController
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black // Set background to black instead of white
        
        // Add preview layer
        cameraController.previewLayer.frame = view.bounds
        cameraController.previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(cameraController.previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            cameraController.previewLayer.frame = uiView.bounds
        }
    }
}

// Camera controller
class CameraController: NSObject, ObservableObject {
    @Published var isSetup = false
    @Published var errorMessage: String?
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    var previewLayer: AVCaptureVideoPreviewLayer!
    var completionHandler: ((UIImage?) -> Void)?
    
    override init() {
        super.init()
        setupPreviewLayer()
    }
    
    func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = UIColor.black.cgColor
    }
    
    func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.errorMessage = "Camera access denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access denied. Please enable in Settings."
            }
        @unknown default:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access not available"
            }
        }
    }
    
    func setupCamera() {
        // Stop any existing session
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        
        // Remove existing inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async {
                self.errorMessage = "Camera not available"
            }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add camera input"
                }
                return
            }
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add photo output"
                }
                return
            }
            
            // Start the session on a background queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                DispatchQueue.main.async {
                    self?.isSetup = true
                    print("📸 Camera setup completed successfully")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Camera setup error: \(error.localizedDescription)"
            }
            print("📸 Camera setup error: \(error)")
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard captureSession.isRunning else {
            print("📸 Camera session not running")
            completion(nil)
            return
        }
        
        completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        DispatchQueue.main.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            completionHandler?(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completionHandler?(nil)
            return
        }
        
        completionHandler?(image)
    }
}

func uploadReceiptImage(_ image: UIImage, completion: @escaping (Result<[String: Any], Error>) -> Void) {
            let urlString = "\(Config.receiptBackendURL)/analyze-receipt"
    print("📤 Uploading receipt to: \(urlString)")
    
    guard let url = URL(string: urlString) else {
        print("❌ Invalid URL: \(urlString)")
        completion(.failure(NSError(domain: "Invalid URL", code: 0)))
        return
    }
    
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        print("❌ Failed to convert image to JPEG data")
        completion(.failure(NSError(domain: "Image conversion failed", code: 0)))
        return
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    var body = Data()
    
    // Add the image part
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n".data(using: .utf8)!)
    
    // Add the closing boundary
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    
    // Set the content length
    request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
    
    print("📤 Request body size: \(body.count) bytes")
    
    URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
        if let error = error {
            print("❌ Network error: \(error.localizedDescription)")
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 HTTP Status: \(httpResponse.statusCode)")
        }
        
        guard let data = data else {
            print("❌ No response data received")
            DispatchQueue.main.async { completion(.failure(NSError(domain: "No data", code: 0))) }
            return
        }
        
        // Print response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 Response: \(responseString)")
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ Successfully parsed JSON response")
                DispatchQueue.main.async { completion(.success(json)) }
            } else {
                print("❌ Failed to parse JSON response")
                DispatchQueue.main.async { completion(.failure(NSError(domain: "Invalid JSON", code: 0))) }
            }
        } catch {
            print("❌ JSON parsing error: \(error.localizedDescription)")
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }.resume()
}

// Animated dumpling rain view
struct DumplingRainView: View {
    @State private var animating = false
    let dumplingCount = 16
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<dumplingCount, id: \ .self) { i in
                    DumplingEmojiView(index: i, width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct DumplingEmojiView: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    @State private var y: CGFloat = -100
    var body: some View {
        let x = CGFloat.random(in: 0...(width-40))
        let delay = Double.random(in: 0...(index.isMultiple(of: 2) ? 0.5 : 1.0))
        Text("🥟")
            .font(.system(size: 40))
            .position(x: x, y: y)
            .onAppear {
                withAnimation(.easeIn(duration: 2.0).delay(delay)) {
                    y = height + 40
                }
            }
    }
}

// Animated boba rain view
struct BobaRainView: View {
    @State private var animating = false
    let bobaCount = 16
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<bobaCount, id: \.self) { i in
                    BobaEmojiView(index: i, width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct BobaEmojiView: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    @State private var y: CGFloat = -100
    var body: some View {
        let x = CGFloat.random(in: 0...(width-40))
        let delay = Double.random(in: 0...(index.isMultiple(of: 2) ? 0.5 : 1.0))
        Text("🧋")
            .font(.system(size: 40))
            .position(x: x, y: y)
            .onAppear {
                withAnimation(.easeIn(duration: 2.0).delay(delay)) {
                    y = height + 40
                }
            }
    }
} 