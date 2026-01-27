import SwiftUI
import AVFoundation
import Vision

// MARK: - Camera Controller

/// Manages camera session and photo capture for the employee reward scanner
class RewardCameraController: NSObject, ObservableObject {
    @Published var isSetup = false
    
    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    
    override init() {
        super.init()
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
                        self?.isSetup = false
                    }
                }
            }
        default:
            isSetup = false
        }
    }
    
    private func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                DispatchQueue.main.async {
                    self.isSetup = false
                }
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureSession.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }
            
            self.captureSession.commitConfiguration()
            
            DispatchQueue.main.async {
                self.captureSession.startRunning()
                self.isSetup = true
            }
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: RewardCameraPhotoCaptureDelegate(completion: completion))
    }
    
    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    var session: AVCaptureSession {
        return captureSession
    }
}

// MARK: - Photo Capture Delegate

private class RewardCameraPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    
    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completion(nil)
            return
        }
        completion(image)
    }
}

// MARK: - Camera Preview View

/// SwiftUI wrapper for camera preview layer used in the rewards scanner
struct RewardScannerCameraPreviewView: UIViewControllerRepresentable {
    let cameraController: RewardCameraController
    
    func makeUIViewController(context: Context) -> RewardScannerCameraPreviewViewController {
        let controller = RewardScannerCameraPreviewViewController()
        controller.cameraController = cameraController
        return controller
    }
    
    func updateUIViewController(_ uiViewController: RewardScannerCameraPreviewViewController, context: Context) {
        // No updates needed
    }
}

/// UIKit view controller that manages the camera preview layer for the rewards scanner
class RewardScannerCameraPreviewViewController: UIViewController {
    var cameraController: RewardCameraController?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupPreviewLayer()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func setupPreviewLayer() {
        guard previewLayer == nil, let cameraController = cameraController else { return }
        
        let layer = AVCaptureVideoPreviewLayer(session: cameraController.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }
}

// MARK: - Entry screen for employee-only features.
/// Currently offers a single action: launch the Rewards Scanner.
struct EmployeesOnlyHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                HStack(spacing: 8) {
                    Text("Employees Only!")
                        .font(.largeTitle.bold())
                    Image("dumpemp")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                }
                .padding(.top, 40)

                NavigationLink(destination: AdminRewardsScanView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                        Text("Rewards Scanner")
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Theme.primaryGold)
                            .shadow(color: Theme.primaryGold.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Reward scanner captures a photo and sends it to the backend to extract the 8-digit reward code.
struct RewardScannerView: View {
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var cameraController = RewardCameraController()
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var extractedCode: String = ""
    @State private var navigateToDetails = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        ZStack {
            // Live camera preview (always present — shows black background until setup completes)
            RewardScannerCameraPreviewView(cameraController: cameraController)
                .ignoresSafeArea()

            // Loading overlay when camera is still configuring
            if !cameraController.isSetup {
                Color.black.opacity(0.9).ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.6)
                                .tint(.white)
                            Text("Setting up camera…")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    )
            }
            
            // Viewfinder overlay (only after the camera is ready)
            if cameraController.isSetup {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 300, height: 140)
            }
            
            VStack(spacing: 24) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .cornerRadius(12)
            }
            
            if isProcessing {
                ProgressView("Extracting code…")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            if !extractedCode.isEmpty {
                Text("Extracted Code: \(extractedCode)")
                    .font(.title2.bold())
                    .foregroundColor(.green)
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Button(action: {
                cameraController.capturePhoto { image in
                    if let img = image {
                        capturedImage = img
                        processImage(img)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Scan Reward Code")
                }
                .font(.title3.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Theme.primaryGold)
                        .shadow(color: Theme.primaryGold.opacity(0.3), radius: 8, x: 0, y: 4)
                )
            }
            .disabled(isProcessing)
            
            NavigationLink(destination: RewardVerificationView(code: extractedCode), isActive: $navigateToDetails) { EmptyView() }
        }
        .padding()
        .overlay(alignment: .top) { header }
    }
    .onAppear { cameraController.checkPermissionAndSetup() }
    .onDisappear {
        // Stop the camera as soon as the scanner view is dismissed
        cameraController.stopSession()
    }
    .navigationBarHidden(true)
    }
    
    private var header: some View {
        VStack {
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        extractedCode = ""
        errorMessage = ""
        extractCodeFromImage(image) { result in
            isProcessing = false
            switch result {
            case .success(let code):
                extractedCode = code
                navigateToDetails = true
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}

func uploadRewardImage(_ image: UIImage, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    let urlString = "\(Config.backendURL)/extract-reward-code"
    DebugLogger.debug("📤 Uploading reward scan to: \(urlString)", category: "Admin")
    guard let url = URL(string: urlString) else {
        completion(.failure(NSError(domain: "Invalid URL", code: 0)))
        return
    }
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        completion(.failure(NSError(domain: "Image conversion failed", code: 0)))
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"reward.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
    URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
        if let error = error {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        guard let data = data else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "No data", code: 0))) }
            return
        }
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async { completion(.success(json)) }
            } else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "Invalid JSON", code: 0))) }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }.resume()
}




/// OCR helper that uses Vision to find the first 8-digit numeric string in the image.
func extractCodeFromImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
    guard let cgImage = image.cgImage else {
        completion(.failure(NSError(domain: "InvalidImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to process image."])))
        return
    }
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let candidates = observations.compactMap { $0.topCandidates(1).first?.string }
        if let match = candidates.first(where: { $0.range(of: #"^\d{8}$"#, options: .regularExpression) != nil }) {
            completion(.success(match))
        } else {
            completion(.failure(NSError(domain: "CodeNotFound", code: -2, userInfo: [NSLocalizedDescriptionKey: "No 8-digit code found."])))
        }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
        } catch {
            completion(.failure(error))
        }
    }
}

#Preview {
    EmployeesOnlyHomeView()
}
