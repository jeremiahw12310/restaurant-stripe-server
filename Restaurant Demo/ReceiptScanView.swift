import SwiftUI
import Vision
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit

struct ReceiptScanView: View {
    @StateObject private var userVM = UserViewModel()
    @State private var showCamera = false
    @State private var scannedImage: UIImage?
    @State private var isProcessing = false
    @State private var showCongratulations = false
    @State private var receiptTotal: Double = 0.0
    @State private var pointsEarned: Int = 0
    @State private var errorMessage = ""
    @State private var showPermissionAlert = false
    @State private var scannedText = ""
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 1.0, green: 0.98, blue: 0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if showCongratulations {
                congratulationsView
            } else {
                mainView
            }
        }
        .onAppear {
            userVM.loadUserData()
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
                    processReceiptImage(image)
                }
            }
        }
    }
    
    private var mainView: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
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
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Processing receipt...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        if !scannedText.isEmpty {
                            Text("Found text: \(scannedText.prefix(100))...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
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
                                            Color(red: 0.2, green: 0.6, blue: 0.9),
                                            Color(red: 0.3, green: 0.7, blue: 1.0)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 15, x: 0, y: 8)
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
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
            }
            VStack(spacing: 16) {
                detailRow(title: "Receipt Total", value: String(format: "$%.2f", receiptTotal))
                detailRow(title: "Points Earned", value: "\(pointsEarned) points")
                detailRow(title: "Rate", value: "5 points per dollar")
            }
            .padding(25)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
            )
            .padding(.horizontal, 20)
            Spacer()
            Button(action: {
                showCongratulations = false
                errorMessage = ""
            }) {
                Text("Scan Another Receipt")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.6, blue: 0.9),
                                        Color(red: 0.3, green: 0.7, blue: 1.0)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), radius: 10, x: 0, y: 5)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
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
    
    private func processReceiptImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = ""
        scannedText = ""
        uploadReceiptImage(image) { result in
            isProcessing = false
            switch result {
            case .success(let json):
                // Example: ["orderNumber": ..., "orderTotal": ..., "orderDate": ...]
                if let orderNumber = json["orderNumber"] as? String,
                   let orderTotal = json["orderTotal"] as? Double,
                   let orderDate = json["orderDate"] as? String {
                    self.scannedText = "Order #: \(orderNumber)\nDate: \(orderDate)\nTotal: $\(orderTotal)"
                    self.receiptTotal = orderTotal
                    self.pointsEarned = Int(orderTotal * 5)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.showCongratulations = true
                        self.updateUserPoints()
                    }
                } else {
                    self.errorMessage = "Could not extract all fields from receipt."
                }
            case .failure(let error):
                self.errorMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
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
}

struct CameraViewWithOverlay: View {
    @Binding var image: UIImage?
    var onImageCaptured: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var cameraController = CameraController()

    var body: some View {
            ZStack {
            // Camera preview
            CameraPreviewView(cameraController: cameraController)
                .ignoresSafeArea()
            
            // Loading overlay
            if !cameraController.isSetup {
                Color.black.ignoresSafeArea()
                        .overlay(
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Setting up camera...")
                                .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                    )
            }
            
            // Error overlay
            if let errorMessage = cameraController.errorMessage {
                Color.black.ignoresSafeArea()
            .overlay(
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            Text("Camera Error")
                                .font(.title2)
                                .foregroundColor(.white)
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            Button("Try Again") {
                                cameraController.errorMessage = nil
                                cameraController.checkPermissionAndSetup()
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            Button("Cancel") {
                                dismiss()
                            }
                            .padding()
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    )
            }
            
            // Receipt guide overlay (only show when camera is ready)
            if cameraController.isSetup && cameraController.errorMessage == nil {
                VStack {
                    Spacer()
                    
                    // Receipt guide rectangle - taller for vertical receipts
                    ZStack {
                        // Semi-transparent overlay
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        // Clear rectangle for receipt - taller for vertical receipts
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 280, height: 350) // Made taller for vertical receipts
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.clear)
                            )
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text.viewfinder")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                    Text("Center your receipt here")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                }
                            )
                    }
                    .frame(width: 280, height: 350) // Made taller for vertical receipts
                    
                    Spacer()
                    
                    // Instructions
                    VStack(spacing: 12) {
                        Text("Position your receipt within the frame")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Make sure the entire receipt is visible")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                
                // Camera controls
                VStack {
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Capture button
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            cameraController.capturePhoto { capturedImage in
                                if let capturedImage = capturedImage {
                                    image = capturedImage
                                    onImageCaptured(capturedImage)
                                }
                            }
                        }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black, lineWidth: 4)
                                        .frame(width: 70, height: 70)
                                )
                        }
                        
                        Spacer()
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
    let urlString = Config.analyzeReceiptURL
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