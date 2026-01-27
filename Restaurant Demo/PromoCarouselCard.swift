import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher
import PhotosUI

// MARK: - Models
enum PromoDestinationType: String, CaseIterable, Identifiable, Codable, Equatable {
    case order
    case personalizedCombo
    case scanReceipt
    case rewards
    case community
    case url

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .order: return "Order Online"
        case .personalizedCombo: return "Personalized Combo"
        case .scanReceipt: return "Scan Receipt"
        case .rewards: return "Rewards"
        case .community: return "Community"
        case .url: return "Open URL"
        }
    }
}

struct PromoSlide: Identifiable, Codable, Equatable {
    let id: String
    var imageURL: String
    var destinationType: PromoDestinationType
    var destinationValue: String? // used for .url, optional for others
    var durationSec: Double
    var orderIndex: Int
    var isActive: Bool

    init(
        id: String = UUID().uuidString,
        imageURL: String,
        destinationType: PromoDestinationType,
        destinationValue: String? = nil,
        durationSec: Double = 3.0,
        orderIndex: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.imageURL = imageURL
        self.destinationType = destinationType
        self.destinationValue = destinationValue
        self.durationSec = durationSec
        self.orderIndex = orderIndex
        self.isActive = isActive
    }

    init?(from dict: [String: Any], id: String) {
        guard
            let imageURL = dict["imageURL"] as? String,
            let destinationTypeRaw = dict["destinationType"] as? String,
            let destinationType = PromoDestinationType(rawValue: destinationTypeRaw),
            let durationSec = dict["durationSec"] as? Double,
            let orderIndex = dict["orderIndex"] as? Int,
            let isActive = dict["isActive"] as? Bool
        else { return nil }

        self.id = id
        self.imageURL = imageURL
        self.destinationType = destinationType
        self.destinationValue = dict["destinationValue"] as? String
        self.durationSec = durationSec
        self.orderIndex = orderIndex
        self.isActive = isActive
    }

    func toFirestore() -> [String: Any] {
        [
            "imageURL": imageURL,
            "destinationType": destinationType.rawValue,
            "destinationValue": destinationValue as Any,
            "durationSec": durationSec,
            "orderIndex": orderIndex,
            "isActive": isActive
        ]
    }
}

// MARK: - ViewModel
class PromoCarouselViewModel: ObservableObject {
    @Published var slides: [PromoSlide] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var cachedImages: [String: UIImage] = [:] // Cache for instant display
    
    // MARK: - Hero Image State (for instant first image display)
    @Published var heroImage: UIImage? = nil           // The first image, loaded instantly
    @Published var heroImageReady: Bool = false        // True when hero image is available
    @Published var allImagesReady: Bool = false        // True when all images are prefetched (safe to start slideshow)

    private var listener: ListenerRegistration?
    private let cacheManager = PromoImageCacheManager.shared

    deinit {
        listener?.remove()
    }
    
    /// Load the persisted hero image immediately on init for instant display
    func loadPersistedHeroImage() {
        if let cached = cacheManager.loadHeroImage() {
            self.heroImage = cached
            self.heroImageReady = true
            DebugLogger.debug("✅ [Carousel] Hero image ready for instant display", category: "Promo")
        } else {
            DebugLogger.debug("📸 [Carousel] No persisted hero image yet - will show placeholder", category: "Promo")
        }
    }

    func startListener() {
        let db = Firestore.firestore()
        listener?.remove()
        listener = db.collection("promoSlides")
            .whereField("isActive", isEqualTo: true)
            .order(by: "orderIndex")
            .limit(to: 20)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }
                let docs = snapshot?.documents ?? []
                let mapped: [PromoSlide] = docs.compactMap { doc in
                    PromoSlide(from: doc.data(), id: doc.documentID)
                }
                DispatchQueue.main.async {
                    self.slides = mapped
                    // Immediately load cached images for instant display
                    self.loadCachedImages()
                    // Check for updates and prefetch all images
                    self.prefetchAllImages()
                }
            }
    }
    
    /// Load all cached images immediately for instant display.
    /// For safety and simplicity, we rely on Kingfisher's disk cache instead of a custom one.
    private func loadCachedImages() {
        // We no longer maintain a separate in-memory dictionary; KFImage will hit its own cache.
        cachedImages.removeAll()
        DebugLogger.debug("📸 [Carousel] Using Kingfisher cache only (no custom image cache).", category: "Promo")
    }
    
    /// Prefetch all slide images using Kingfisher so they are warm in disk cache.
    /// When complete, marks allImagesReady = true to allow slideshow to start.
    private func prefetchAllImages() {
        let urls = slides.compactMap { URL(string: $0.imageURL) }
        guard !urls.isEmpty else {
            DebugLogger.debug("🔄 [Carousel] No slide URLs to prefetch.", category: "Promo")
            // If no slides, mark as ready anyway
            DispatchQueue.main.async {
                self.allImagesReady = true
            }
            return
        }
        
        DebugLogger.debug("🔄 [Carousel] Prefetching \(urls.count) promo images with Kingfisher...", category: "Promo")
        let prefetcher = ImagePrefetcher(urls: urls) { [weak self] skipped, failed, completed in
            guard let self = self else { return }
            DebugLogger.debug("✅ [Carousel] Prefetch complete. Loaded: \(completed.count), failed: \(failed.count), skipped: \(skipped.count)", category: "Promo")
            
            DispatchQueue.main.async {
                // Mark all images as ready - slideshow can now start
                self.allImagesReady = true
                
                // Update hero image if needed (for next launch)
                self.updateHeroImageIfNeeded()
            }
        }
        prefetcher.start()
    }
    
    /// Save the first carousel image for instant loading on next app launch
    private func updateHeroImageIfNeeded() {
        guard let firstSlide = slides.first else { return }
        let firstURL = firstSlide.imageURL
        
        // Check if we need to update the hero image
        if cacheManager.heroImageNeedsUpdate(currentURL: firstURL) {
            DebugLogger.debug("🔄 [Hero] First slide URL changed, updating hero image...", category: "Promo")
            cacheManager.downloadAndSaveHeroImage(url: firstURL) { [weak self] image in
                if let image = image {
                    self?.heroImage = image
                    self?.heroImageReady = true
                    DebugLogger.debug("✅ [Hero] Hero image updated for next launch", category: "Promo")
                }
            }
        } else if !heroImageReady {
            // Hero URL matches but we didn't have it loaded - load from cache
            if let cached = cacheManager.loadHeroImage() {
                self.heroImage = cached
                self.heroImageReady = true
            }
        }
    }

    func addSlide(image: UIImage, destinationType: PromoDestinationType, destinationValue: String?, durationSec: Double, completion: @escaping (Bool) -> Void) {
        isLoading = true
        errorMessage = nil

        // Use 0.95 compression for higher quality while still keeping file size reasonable
        guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
            self.errorMessage = "Unable to compress image"
            self.isLoading = false
            completion(false)
            return
        }

        let storage = Storage.storage()
        let fileId = UUID().uuidString
        let ref = storage.reference().child("promo_slides/\(fileId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        ref.putData(jpegData, metadata: metadata) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    completion(false)
                }
                return
            }
            ref.downloadURL { url, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                        completion(false)
                    }
                    return
                }
                guard let url = url else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Missing download URL"
                        self.isLoading = false
                        completion(false)
                    }
                    return
                }

                // Save Firestore document
                let db = Firestore.firestore()
                let nextIndex = (self.slides.map { $0.orderIndex }.max() ?? -1) + 1
                let slide = PromoSlide(
                    imageURL: url.absoluteString,
                    destinationType: destinationType,
                    destinationValue: destinationValue,
                    durationSec: durationSec,
                    orderIndex: nextIndex,
                    isActive: true
                )
                db.collection("promoSlides").document(slide.id).setData(slide.toFirestore()) { err in
                    DispatchQueue.main.async {
                        if let err = err {
                            self.errorMessage = err.localizedDescription
                            self.isLoading = false
                            completion(false)
                        } else {
                            self.isLoading = false
                            completion(true)
                        }
                    }
                }
            }
        }
    }

    func updateSlide(_ slide: PromoSlide, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        db.collection("promoSlides").document(slide.id).updateData(slide.toFirestore()) { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func deleteSlide(_ slide: PromoSlide, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        db.collection("promoSlides").document(slide.id).delete { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func reorderSlides(from source: IndexSet, to destination: Int) {
        var newSlides = slides
        newSlides.move(fromOffsets: source, toOffset: destination)
        // write back order indices
        for (idx, var s) in newSlides.enumerated() {
            s.orderIndex = idx
            updateSlide(s) { _ in }
        }
        slides = newSlides
    }
}

// MARK: - Editor UI (Admin Only)
struct PromoCarouselEditorSheet: View {
    @ObservedObject var viewModel: PromoCarouselViewModel
    @EnvironmentObject var userVM: UserViewModel

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil

    @State private var newDestinationType: PromoDestinationType = .order
    @State private var newDestinationValue: String = ""
    @State private var newDuration: Double = 3.0
    @State private var isEditingOrder: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Uploading...")
                        .padding()
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                // Slides list with optional reorder mode
                if !viewModel.slides.isEmpty {
                    List {
                        Section(header: HStack {
                            Text("Current Slides")
                            Spacer()
                            Button(isEditingOrder ? "Done" : "Reorder") { 
                                withAnimation { isEditingOrder.toggle() }
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }) {
                            ForEach(viewModel.slides) { slide in
                                HStack(spacing: 12) {
                                    KFImage(URL(string: slide.imageURL))
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 64)
                                        .clipped()
                                        .cornerRadius(8)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(slide.destinationType.displayName)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Duration: \(String(format: "%.1f", slide.durationSec))s")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        if let v = slide.destinationValue, !v.isEmpty {
                                            Text(v)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Menu {
                                        Button("Edit") { editSlide(slide) }
                                        Button("Delete", role: .destructive) {
                                            viewModel.deleteSlide(slide) { _ in }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 18))
                                    }
                                }
                            }
                            .onMove(perform: viewModel.reorderSlides)
                        }
                    }
                    .environment(\.editMode, .constant(isEditingOrder ? EditMode.active : EditMode.inactive))
                }

                Divider()

                // Add New Form (Outside List for better tap handling)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Add New Slide")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal)
                            .padding(.top, 12)

                        // Image Picker Button
                        VStack(spacing: 12) {
                            if let img = selectedImage {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 240)
                                        .clipped()
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                    
                                    Button(action: {
                                        selectedImage = nil
                                        selectedItem = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.red))
                                    }
                                    .padding(8)
                                }
                                .padding(.horizontal)
                            }
                            
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                HStack {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 20))
                                    Text(selectedImage == nil ? "Select Image" : "Change Image")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                )
                                .shadow(radius: 4)
                            }
                            .padding(.horizontal)
                            .buttonStyle(PlainButtonStyle())
                            .onChange(of: selectedItem) { _, newItem in
                                guard let newItem = newItem else { return }
                                Task {
                                    if let data = try? await newItem.loadTransferable(type: Data.self), 
                                       let image = UIImage(data: data) {
                                        await MainActor.run {
                                            selectedImage = image
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Destination")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $newDestinationType) {
                                ForEach(PromoDestinationType.allCases) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                            )

                            if newDestinationType == .url {
                                TextField("https://example.com", text: $newDestinationValue)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.systemGray6))
                                    )
                            }
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Duration: \(Int(newDuration))s")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Slider(value: $newDuration, in: 1...10, step: 1)
                                .accentColor(.blue)
                        }
                        .padding(.horizontal)

                        Button(action: addNewSlide) {
                            HStack {
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                Text("Add Slide")
                                    .fontWeight(.bold)
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedImage == nil ? Color.gray : Color.green)
                            )
                            .shadow(radius: selectedImage == nil ? 0 : 4)
                        }
                        .disabled(selectedImage == nil)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Promo Carousel")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func addNewSlide() {
        guard let selectedImage = selectedImage else { return }
        let value = newDestinationType == .url ? newDestinationValue.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        viewModel.addSlide(image: selectedImage, destinationType: newDestinationType, destinationValue: value, durationSec: newDuration) { success in
            if success {
                // reset form
                self.selectedImage = nil
                self.selectedItem = nil
                self.newDestinationType = .order
                self.newDestinationValue = ""
                self.newDuration = 3.0
            }
        }
    }

    private func editSlide(_ slide: PromoSlide) {
        // Simple inline editor: prefill state and reuse add control; in production, present a dedicated editor
        self.newDestinationType = slide.destinationType
        self.newDestinationValue = slide.destinationValue ?? ""
        self.newDuration = slide.durationSec
    }
}

// MARK: - Carousel Card
struct PromoCarouselCard: View {
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var viewModel = PromoCarouselViewModel()

    /// Controls whether the auto-advancing slide timer should run.
    /// HomeView will set this to false while heavy overlays (like ReferralView) are on screen
    /// to avoid background work and reduce CPU usage.
    let isActive: Bool

    // Destinations provided by parent (HomeView)
    let openOrder: () -> Void
    let openScan: () -> Void
    let openRewards: () -> Void
    let openCommunity: () -> Void
    let openPersonalizedCombo: () -> Void

    @State private var currentIndex: Int = 0
    @State private var isEditorPresented: Bool = false
    @State private var slideTimerTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.slides.isEmpty && !viewModel.heroImageReady {
                // No slides and no hero image - show placeholder
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.cardGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Theme.darkGoldGradient, lineWidth: 3)
                        )
                        .shadow(color: Theme.goldShadow, radius: 18, x: 0, y: 8)
                        .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)

                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("Promotions coming soon")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(32)

                    if userVM.isAdmin {
                        Button(action: { isEditorPresented = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Edit")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Theme.goldGradient)
                                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                            )
                            .padding(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .zIndex(100)
                        .allowsHitTesting(true)
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            } else if viewModel.slides.isEmpty && viewModel.heroImageReady {
                // No slides loaded yet BUT we have a hero image - show it instantly!
                ZStack(alignment: .topTrailing) {
                    if let heroImage = viewModel.heroImage {
                        Image(uiImage: heroImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { openOrder() } // Default action while loading
                    }
                    
                    if userVM.isAdmin {
                        adminEditButton
                    }
                }
                .frame(height: 220)
                .background(carouselBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                // Slides available - show carousel
                ZStack(alignment: .topTrailing) {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.slides.enumerated()), id: \.offset) { index, slide in
                            ZStack {
                                // PRIORITY 1: Hero image for first slide (instant display)
                                if index == 0, viewModel.heroImageReady, let heroImage = viewModel.heroImage {
                                    Image(uiImage: heroImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture { handleTap(slide) }
                                }
                                // PRIORITY 2: Cached image from viewModel
                                else if let cachedImage = viewModel.cachedImages[slide.imageURL] {
                                    Image(uiImage: cachedImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture { handleTap(slide) }
                                }
                                // PRIORITY 3: Kingfisher with styled placeholder (not spinner)
                                else {
                                    KFImage.url(URL(string: slide.imageURL))
                                        .setProcessor(DefaultImageProcessor.default)
                                        .loadDiskFileSynchronously()
                                        .cacheMemoryOnly(false)
                                        .fade(duration: 0.2)
                                        .onSuccess { result in
                                            DebugLogger.debug("✅ Kingfisher loaded: \(slide.imageURL)", category: "Promo")
                                        }
                                        .placeholder {
                                            // Styled placeholder instead of spinner
                                            carouselPlaceholder
                                        }
                                        .resizable()
                                        .interpolation(.high)
                                        .renderingMode(.original)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture { handleTap(slide) }
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: viewModel.allImagesReady ? .automatic : .never))
                    .frame(height: 220)
                    .background(carouselBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    if userVM.isAdmin {
                        adminEditButton
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            // CRITICAL: Load persisted hero image FIRST for instant display
            viewModel.loadPersistedHeroImage()
            // Then start Firestore listener
            viewModel.startListener()
        }
        .onDisappear {
            // Ensure timer is cancelled when carousel goes off-screen
            slideTimerTask?.cancel()
            slideTimerTask = nil
        }
        .onChange(of: currentIndex) { _, _ in
            // Only reschedule if slideshow is allowed
            if viewModel.allImagesReady {
                scheduleNextSlide()
            }
        }
        .onChange(of: viewModel.slides) { _, _ in
            if currentIndex >= viewModel.slides.count { currentIndex = 0 }
            // Only start slideshow if all images are ready
            if viewModel.allImagesReady {
                scheduleNextSlide()
            }
        }
        .onChange(of: viewModel.allImagesReady) { _, ready in
            // START slideshow only when all images are prefetched
            if ready && isActive {
                DebugLogger.debug("✅ [Carousel] All images ready - starting slideshow", category: "Promo")
                scheduleNextSlide()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue && viewModel.allImagesReady {
                scheduleNextSlide()
            } else if !newValue {
                slideTimerTask?.cancel()
                slideTimerTask = nil
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            PromoCarouselEditorSheet(viewModel: viewModel)
                .environmentObject(userVM)
        }
    }
    
    // MARK: - Subviews
    
    private var carouselBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Theme.cardGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.darkGoldGradient, lineWidth: 3)
            )
            .shadow(color: Theme.goldShadow, radius: 18, x: 0, y: 8)
            .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
    }
    
    private var adminEditButton: some View {
        Button(action: { isEditorPresented = true }) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                Text("Edit")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Theme.goldGradient)
                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
            )
            .padding(10)
        }
        .buttonStyle(PlainButtonStyle())
        .zIndex(100)
        .allowsHitTesting(true)
    }
    
    /// Styled placeholder shown while images load (instead of a spinner)
    private var carouselPlaceholder: some View {
        ZStack {
            // Gradient background matching the card theme
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.gray.opacity(0.3),
                    Color.gray.opacity(0.2)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle shimmer effect
            VStack(spacing: 12) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                
                // Small loading indicator (subtle, not intrusive)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                    .scaleEffect(0.8)
            }
        }
    }

    private func scheduleNextSlide() {
        slideTimerTask?.cancel()
        slideTimerTask = nil
        // IMPORTANT: Only start slideshow when all images are ready
        guard isActive && viewModel.allImagesReady else { return }
        guard !viewModel.slides.isEmpty else { return }
        let safeIndex = max(0, min(currentIndex, viewModel.slides.count - 1))
        let duration = max(1.0, viewModel.slides[safeIndex].durationSec)
        slideTimerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            let next = (safeIndex + 1) % max(1, viewModel.slides.count)
            withAnimation { currentIndex = next }
        }
    }

    private func handleTap(_ slide: PromoSlide) {
        switch slide.destinationType {
        case .order:
            openOrder()
        case .scanReceipt:
            openScan()
        case .rewards:
            openRewards()
        case .community:
            openCommunity()
        case .personalizedCombo:
            openPersonalizedCombo()
        case .url:
            if let value = slide.destinationValue, let url = URL(string: value) {
                UIApplication.shared.open(url)
            }
        }
    }
}


