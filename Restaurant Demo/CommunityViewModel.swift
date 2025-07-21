import Foundation
import FirebaseFirestore
import Combine
import FirebaseAuth
import FirebaseStorage
import Kingfisher

// MARK: - Verification Request Model
struct VerificationRequest: Identifiable {
    let id: String
    let userId: String
    let userFirstName: String
    let requestedAt: Date
    let status: String
}

// MARK: - Report Model
struct Report: Identifiable {
    let id: String
    let postId: String
    let userId: String
    let reason: String
    let details: String?
    let createdAt: Date?
    let reviewed: Bool?
}

// MARK: - Comment Report Model
struct CommentReport: Identifiable, Codable {
    let id: String
    let commentId: String
    let userId: String
    let reason: String
    let details: String?
    let createdAt: Date?
    let reviewed: Bool?
}

// MARK: - Loading State Enum
enum LoadingState: Equatable {
    case initial
    case loading
    case loaded
    case error(String)
    
    static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.initial, .initial):
            return true
        case (.loading, .loading):
            return true
        case (.loaded, .loaded):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Performance Monitoring
struct PerformanceMetrics {
    var postsLoadTime: TimeInterval = 0
    var imageLoadTime: TimeInterval = 0
    var commentLoadTime: TimeInterval = 0
    var memoryUsage: Int64 = 0
    var cacheHitRate: Double = 0
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
}

class CommunityViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var posts: [CommunityPost] = []
    @Published var loadingState: LoadingState = .initial
    @Published var errorMessage: String? = nil
    @Published var postSubmissionError: String? = nil
    @Published var isLoadingMore: Bool = false
    @Published var hasMorePosts: Bool = true
    @Published var isAdmin: Bool = false
    @Published var totalStats: (posts: Int, likes: Int, comments: Int) = (0, 0, 0)
    
    // MARK: - Memory-Efficient User Profile Cache
    @Published var userProfiles: [String: UserProfile] = [:]
    private var userProfileFetches: Set<String> = []
    private var maxCachedProfiles = 12 // OPTIMIZED: Further reduced from 15 to 12 for lower memory usage
    private var profileCacheTimer: Timer?
    
    // MARK: - Pagination Properties
    @Published var regularPostsShown: Int = 5 // OPTIMIZED: Further reduced from 6 to 5 for better performance
    private let postsPerPage = 5 // OPTIMIZED: Further reduced from 6 to 5
    private var pinnedPosts: [CommunityPost] = []
    private var regularPosts: [CommunityPost] = []
    private var lastDocument: DocumentSnapshot?
    private var hasMorePostsAvailable = true
    
    // Expose total post count for UI
    public var totalPostCount: Int { pinnedPosts.count + regularPosts.count }
    
    // MARK: - Database & Listeners
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var userProfileListeners: [String: ListenerRegistration] = [:]
    private var hasInitializedListener = false
    @Published var reactionsForPost: [String: [String: Int]] = [:]
    
    // MARK: - Memory Management
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Advanced Optimization Properties for Large Scale
    @Published var imageCache: [String: UIImage] = [:]
    private var maxImageCacheSize = 12 // OPTIMIZED: Further reduced from 15 to 12 for lower memory usage
    private var commentCache: [String: [CommunityReply]] = [:]
    private var maxCommentCacheSize = 6 // OPTIMIZED: Further reduced from 8 to 6
    private var commentPaginationState: [String: (lastDoc: DocumentSnapshot?, hasMore: Bool)] = [:]
    private let commentsPerPage = 5 // OPTIMIZED: Further reduced from 6 to 5
    
    @Published var performanceMetrics = PerformanceMetrics()
    private var performanceTimer: Timer?
    
    // MARK: - Rate Limiting and Error Handling for Large Scale
    private var lastRequestTime: Date = Date()
    private var minimumRequestInterval: TimeInterval = 2.0 // OPTIMIZED: Further increased from 1.5 to 2.0 for lower energy usage
    private var consecutiveErrors = 0
    private let maxConsecutiveErrors = 3
    private var isRateLimited = false
    
    init() {
        setupMemoryManagement()
        setupAdvancedMemoryManagement()
        setupPerformanceMonitoring()
        fetchPosts()
        checkIfCurrentUserIsAdmin { [weak self] adminStatus in
            DispatchQueue.main.async(execute: {
                self?.isAdmin = adminStatus
            })
        }
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Memory Management
    private func setupMemoryManagement() {
        // Listen for memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        
        // Setup profile cache cleanup timer - OPTIMIZED: Further reduced frequency for lower energy usage
        profileCacheTimer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: true) { [weak self] _ in
            self?.cleanupProfileCache()
        }
    }
    
    private func setupAdvancedMemoryManagement() {
        // Enhanced memory warning handling
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAdvancedMemoryWarning()
        }
        
        // OPTIMIZED: Further reduced frequency for lower energy usage
        profileCacheTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.cleanupAllCaches()
        }
    }
    
    private func cleanup() {
        listener?.remove()
        
        // Clean up user profile listeners
        for (_, listener) in userProfileListeners {
            listener.remove()
        }
        userProfileListeners.removeAll()
        
        memoryWarningObserver = nil
        profileCacheTimer?.invalidate()
        cleanupProfileCache()
    }
    
    private func handleMemoryWarning() {
        print("⚠️ Memory warning received, cleaning up caches...")
        cleanupProfileCache()
        // Keep only essential data in memory
        if regularPosts.count > postsPerPage * 2 {
            regularPosts = Array(regularPosts.prefix(postsPerPage * 2))
            updateDisplayedPosts()
        }
    }
    
    private func handleAdvancedMemoryWarning() {
        print("⚠️ Advanced memory warning received, aggressive cleanup...")
        cleanupAllCaches()
        
        // More aggressive post limiting for large datasets
        if regularPosts.count > postsPerPage * 3 {
            regularPosts = Array(regularPosts.prefix(postsPerPage * 2))
            updateDisplayedPosts()
        }
        
        // Clear image cache completely
        imageCache.removeAll()
    }
    
    private func cleanupAllCaches() {
        // Cleanup profile cache
        if userProfiles.count > maxCachedProfiles {
            let sortedProfiles = userProfiles.sorted { $0.value.lastActive > $1.value.lastActive }
            let profilesToKeep = Array(sortedProfiles.prefix(maxCachedProfiles))
            userProfiles = Dictionary(uniqueKeysWithValues: profilesToKeep)
        }
        
        // Cleanup comment cache
        if commentCache.count > maxCommentCacheSize {
            let sortedComments = commentCache.sorted { $0.value.count > $1.value.count }
            let commentsToKeep = Array(sortedComments.prefix(maxCommentCacheSize))
            commentCache = Dictionary(uniqueKeysWithValues: commentsToKeep)
        }
        
        // Cleanup image cache
        if imageCache.count > maxImageCacheSize {
            imageCache.removeAll()
        }
        
        print("🧹 Advanced cache cleanup completed")
    }
    
    private func cleanupProfileCache() {
        if userProfiles.count > maxCachedProfiles {
            let sortedProfiles = userProfiles.sorted { $0.value.lastActive > $1.value.lastActive }
            let profilesToKeep = Array(sortedProfiles.prefix(maxCachedProfiles))
            userProfiles = Dictionary(uniqueKeysWithValues: profilesToKeep)
            print("🧹 Cleaned profile cache, kept \(userProfiles.count) profiles")
        }
    }
    
    func fetchPosts() {
        // Prevent multiple listeners
        if hasInitializedListener {
            print("🔄 Listener already initialized, skipping...")
            return
        }
        
        loadingState = .loading
        errorMessage = nil
        print("🔄 Starting TRUE pagination fetchPosts...")
        listener?.remove()
        
        hasInitializedListener = true
        
        // Reset pagination state
        lastDocument = nil
        hasMorePostsAvailable = true
        regularPosts = []
        pinnedPosts = []
        
        // First, load pinned posts (no pagination needed for pinned posts)
        fetchPinnedPosts { [weak self] in
            // Then load the first page of regular posts
            self?.fetchNextPageOfRegularPosts()
        }
    }
    
    private func fetchPinnedPosts(completion: @escaping () -> Void) {
        print("📌 Fetching pinned posts...")
        
        // OPTIMIZED: Single query for pinned posts with better filtering and limiting
        let pinnedQuery = db.collection("posts")
            .whereField("isPinned", isEqualTo: true)
            .whereField("isReported", isEqualTo: false) // OPTIMIZED: Filter out reported posts at query level
            .order(by: "createdAt", descending: true)
            .limit(to: 2) // OPTIMIZED: Reduced from 3 to 2 for lower energy usage
        
        pinnedQuery.getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching pinned posts: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                let pinnedPosts = snapshot?.documents.compactMap { doc -> CommunityPost? in
                    do {
                        let post = try doc.data(as: CommunityPost.self)
                        // OPTIMIZED: Additional filtering for deleted posts
                        if post.isDeleted {
                            return nil
                        }
                        return post
                    } catch {
                        print("❌ Failed to parse pinned post \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                
                let sortedPinnedPosts = pinnedPosts.sorted { $0.createdAt > $1.createdAt }
                self?.pinnedPosts = sortedPinnedPosts
                
                // FIXED: Immediately update posts array with pinned posts
                self?.posts = sortedPinnedPosts
                
                print("📌 Total pinned posts loaded: \(sortedPinnedPosts.count)")
                print("📌 Posts array updated with pinned posts immediately")
                completion()
            }
        }
    }
    
    private func fetchNextPageOfRegularPosts() {
        print("📄 Fetching next page of regular posts...")
        
        // OPTIMIZED: Single query for regular posts with better filtering and reduced page size
        var query = db.collection("posts")
            .whereField("isPinned", isEqualTo: false)
            .whereField("isReported", isEqualTo: false) // OPTIMIZED: Filter out reported posts at query level
            .order(by: "createdAt", descending: true)
            .limit(to: 5) // FIXED: Match postsPerPage for consistency
        
        // Add pagination cursor if we have one
        if let lastDocument = lastDocument {
            query = query.start(afterDocument: lastDocument)
        }
        
        query.getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching regular posts: \(error.localizedDescription)")
                    self.loadingState = .error(error.localizedDescription)
                    self.isLoadingMore = false // FIXED: Set isLoadingMore to false on error
                    return
                }
                
                let fetchedPosts = snapshot?.documents.compactMap { doc -> CommunityPost? in
                    do {
                        let post = try doc.data(as: CommunityPost.self)
                        // OPTIMIZED: Additional filtering for deleted posts
                        if post.isDeleted {
                            return nil
                        }
                        return post
                    } catch {
                        print("❌ Failed to parse regular post \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                
                let sortedNewPosts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
                
                // Add new posts to existing regular posts
                self.regularPosts.append(contentsOf: sortedNewPosts)
                
                // Update pagination state
                self.lastDocument = snapshot?.documents.last
                self.hasMorePostsAvailable = fetchedPosts.count == 5 // FIXED: Updated to match new limit
                
                // FIXED: Update regularPostsShown to show the newly fetched posts
                let newShownCount = min(self.regularPostsShown + 5, self.regularPosts.count)
                self.regularPostsShown = newShownCount
                
                // Update displayed posts
                let postsToShow = Array(self.regularPosts.prefix(self.regularPostsShown))
                self.posts = self.pinnedPosts + postsToShow
                self.hasMorePosts = self.hasMorePostsAvailable || self.regularPostsShown < self.regularPosts.count
                
                // Update loading state
                if self.loadingState == .loading {
                    self.loadingState = .loaded
                }
                
                // FIXED: Set isLoadingMore to false when fetch completes
                self.isLoadingMore = false
                
                print("🎯 Total posts now: \(self.posts.count)")
                print("📄 Regular posts loaded: \(self.regularPosts.count)")
                print("📄 Regular posts shown: \(self.regularPostsShown)")
                print("📄 Has more posts: \(self.hasMorePosts)")
                
                // FIXED: Set up listener for real-time updates ONLY AFTER initial data is loaded
                // This ensures pinned posts are not overridden during initial load
                if self.listener == nil {
                    print("🔄 Setting up real-time listener after initial load...")
                    self.setupRealTimeListener()
                }
                
                // Refresh comment counts to ensure accuracy
                self.refreshCommentCounts()
                
                // Update stats after posts are loaded
                self.fetchTotalStats()
            }
        }
    }
    
    // MARK: - Optimized Real-time Updates for Large Scale
    private func setupRealTimeListener() {
        // OPTIMIZED: Set up listener for real-time updates with reduced frequency for large scale
        listener = db.collection("posts")
            .whereField("isReported", isEqualTo: false) // isReported = false means approved
            .order(by: "createdAt", descending: true)
            .limit(to: 15)  // OPTIMIZED: Reduced from 25 to 15 for lower energy usage
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async(execute: {
                    if let error = error {
                        print("❌ Error in real-time listener: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("⚠️ No documents found in real-time snapshot")
                        return
                    }
                    
                    print("🔄 Real-time update: \(documents.count) posts")
                    
                    // OPTIMIZED: Only process if we have meaningful changes
                    guard let self = self else { return }
                    
                    // Parse all posts (both pinned and non-pinned)
                    let allPosts = documents.compactMap { doc -> CommunityPost? in
                        do {
                            let post = try doc.data(as: CommunityPost.self)
                            return post
                        } catch {
                            print("❌ Failed to parse post \(doc.documentID): \(error)")
                            return nil
                        }
                    }
                    
                    // Only update if we have posts
                    guard !allPosts.isEmpty else {
                        print("⚠️ No posts to update")
                        return
                    }
                    
                    // Separate pinned and regular posts
                    let newPinnedPosts = allPosts.filter { $0.isPinned }
                    let newRegularPosts = allPosts.filter { !$0.isPinned }
                    
                    // Sort by creation date
                    let sortedPinnedPosts = newPinnedPosts.sorted { $0.createdAt > $1.createdAt }
                    let sortedRegularPosts = newRegularPosts.sorted { $0.createdAt > $1.createdAt }
                    
                    // FIXED: Only update pinned posts if we have them and initial load is complete
                    // This prevents overriding pinned posts during initial load
                    if !sortedPinnedPosts.isEmpty && self.loadingState == .loaded {
                        self.pinnedPosts = sortedPinnedPosts
                        print("📌 Pinned posts updated via real-time: \(sortedPinnedPosts.count)")
                    } else if !sortedPinnedPosts.isEmpty {
                        print("📌 Skipping pinned posts update - initial load not complete")
                    }
                    
                    // FIXED: Only update regular posts if we haven't manually loaded more posts
                    if self.regularPosts.count <= self.postsPerPage {
                        // Only update if we're still at initial load (5 posts or less)
                        self.regularPosts = Array(sortedRegularPosts.prefix(self.postsPerPage))
                        self.hasMorePosts = sortedRegularPosts.count > self.postsPerPage
                    } else {
                        // We've manually loaded more posts, so don't interfere with pagination
                        // Just update the hasMorePosts flag based on total available
                        self.hasMorePosts = sortedRegularPosts.count > self.regularPosts.count
                        
                        // FIXED: Don't update regularPosts array when we've manually loaded more
                        // This prevents the duplication issue
                        print("📄 Skipping regular posts update - manual pagination active")
                    }
                    
                    // FIXED: Always combine pinned posts with regular posts
                    let postsToShow = Array(self.regularPosts.prefix(self.regularPostsShown))
                    let combinedPosts = self.pinnedPosts + postsToShow
                    
                    // OPTIMIZED: Check if the data has actually changed before updating
                    let currentPostIds = Set(self.posts.map { $0.id })
                    let newPostIds = Set(combinedPosts.map { $0.id })
                    
                    // Also check if any existing posts have updated comment counts
                    let hasCommentCountChanges = self.posts.contains { currentPost in
                        if let newPost = combinedPosts.first(where: { $0.id == currentPost.id }) {
                            return newPost.replyCount != currentPost.replyCount
                        }
                        return false
                    }
                    
                    if currentPostIds != newPostIds || hasCommentCountChanges {
                        // Update posts with new sorted array
                        self.posts = combinedPosts
                        
                        print("✅ Updated posts array: \(self.posts.count) total posts (pinned: \(self.pinnedPosts.count), regular: \(postsToShow.count))")
                        if hasCommentCountChanges {
                            print("📝 Comment counts updated")
                        }
                    } else {
                        print("🔄 No changes detected, skipping update")
                    }
                })
            }
    }
    
    func loadMorePosts() {
        print("🔄 loadMorePosts called - hasMorePosts: \(hasMorePosts), isLoadingMore: \(isLoadingMore)")
        
        // OPTIMIZED: Enhanced rate limiting check for large scale
        guard !isRateLimited else {
            print("⚠️ Request rate limited, try again later")
            return
        }
        
        guard hasMorePosts && !isLoadingMore else {
            print("🔄 Cannot load more posts: hasMorePosts=\(hasMorePosts), isLoadingMore=\(isLoadingMore)")
            return
        }
        
        // OPTIMIZED: Apply rate limiting to loadMorePosts as well
        guard checkRateLimit() else {
            print("⚠️ Rate limit exceeded, try again later")
            return
        }
        
        print("🔄 Loading more posts...")
        isLoadingMore = true
        
        // FIXED: Simplified logic to prevent double-tap issue
        // Always try to show more posts from local data first
        if regularPostsShown < regularPosts.count {
            // Show more posts from already loaded data
            let newCount = min(regularPostsShown + 5, regularPosts.count) // FIXED: Use 5 instead of 8 to match postsPerPage
            regularPostsShown = newCount
            
            // Update the displayed posts
            posts = pinnedPosts + Array(regularPosts.prefix(regularPostsShown))
            
            // Update hasMorePosts flag
            hasMorePosts = regularPostsShown < regularPosts.count || hasMorePostsAvailable
            
            isLoadingMore = false
            handleSuccess()
            
            print("🎯 Total posts now: \(posts.count)")
            print("📄 Regular posts shown: \(regularPostsShown)")
            print("📄 Has more posts: \(hasMorePosts)")
            fetchTotalStats()
        } else if hasMorePostsAvailable {
            // Fetch next page from Firestore
            fetchNextPageOfRegularPosts()
            // Note: isLoadingMore will be set to false in fetchNextPageOfRegularPosts completion
        } else {
            hasMorePosts = false
            isLoadingMore = false
        }
    }
    

    
    func submitPost(contentType: String, content: String, pollOptions: [String]? = nil, mediaType: String? = nil, attachedMenuItem: MenuItem? = nil, completion: @escaping (Bool) -> Void) {
        print("submitPost called with contentType: \(contentType), content: \(content)")
        guard let user = Auth.auth().currentUser else {
            print("User not authenticated")
            postSubmissionError = "User not authenticated."
            completion(false)
            return
        }
        print("User authenticated: \(user.uid)")
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        print("Fetching user data for: \(user.uid)")
        userRef.getDocument(source: .default) { [weak self] snapshot, error in
            if let error = error {
                print("Error fetching user data: \(error.localizedDescription)")
                self?.postSubmissionError = "Failed to fetch user info: \(error.localizedDescription)"
                completion(false)
                return
            }
            guard let data = snapshot?.data() else {
                print("User data not found for: \(user.uid)")
                self?.postSubmissionError = "User data not found."
                completion(false)
                return
            }
            print("User data found: \(data)")
            let firstName = data["firstName"] as? String ?? "User"
            let profilePhotoURL = data["profilePhotoURL"] as? String
            let avatarEmoji = data["avatarEmoji"] as? String ?? "👤"
            let avatarColorName = data["avatarColor"] as? String ?? "gray"
            let isVerified = data["isVerified"] as? Bool ?? false
            let postId = UUID().uuidString
            let post = CommunityPost(
                id: postId,
                userId: user.uid,
                userFirstName: firstName,
                userProfilePhotoURL: profilePhotoURL,
                avatarEmoji: avatarEmoji,
                avatarColorName: avatarColorName,
                isVerified: isVerified,
                contentType: contentType,
                content: content,
                mediaType: mediaType,
                pollOptions: pollOptions,
                pollVotes: [:], // Initialize with empty dictionary
                pollExpiresAt: nil,
                attachedMenuItem: attachedMenuItem,
                createdAt: Date(),
                likeCount: 0,
                replyCount: 0,
                isApproved: false,
                isDeleted: false
            )
            do {
                print("💾 Attempting to save post to Firestore with ID: \(postId)")
                try db.collection("posts").document(postId).setData(from: post) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Failed to save post to Firestore: \(error.localizedDescription)")
                            self?.postSubmissionError = "Failed to submit post: \(error.localizedDescription)"
                            completion(false)
                        } else {
                            print("✅ Successfully saved post to Firestore with ID: \(postId)")
                            self?.postSubmissionError = nil
                            completion(true)
                        }
                    }
                }
            } catch {
                print("❌ Failed to encode post: \(error)")
                self?.postSubmissionError = "Failed to encode post."
                completion(false)
            }
        }
    }
    
    func submitImagePost(image: UIImage, caption: String, attachedMenuItem: MenuItem? = nil, customPostId: String? = nil, completion: @escaping (Bool) -> Void) {
        let postId = customPostId ?? UUID().uuidString
        uploadImageToStorage(image: image, postId: postId) { [weak self] urlString in
            guard let urlString = urlString else {
                self?.postSubmissionError = "Failed to upload image."
                completion(false)
                return
            }
            // Store the actual Firebase Storage URL and caption
            self?.submitPost(contentType: "image", content: urlString, caption: caption, mediaType: "image/jpeg", attachedMenuItem: attachedMenuItem, completion: completion, customPostId: postId)
        }
    }
    
    func submitVideoPost(videoURL: URL, caption: String, attachedMenuItem: MenuItem? = nil, customPostId: String? = nil, completion: @escaping (Bool) -> Void) {
        let postId = customPostId ?? UUID().uuidString
        uploadVideoToStorage(videoURL: videoURL, postId: postId) { [weak self] urlString in
            guard let urlString = urlString else {
                self?.postSubmissionError = "Failed to upload video."
                completion(false)
                return
            }
            // Store the actual Firebase Storage URL and caption
            self?.submitPost(contentType: "video", content: urlString, caption: caption, mediaType: "video/mp4", attachedMenuItem: attachedMenuItem, completion: completion, customPostId: postId)
        }
    }
    
    func submitPollPost(options: [String], caption: String, attachedMenuItem: MenuItem? = nil, customPostId: String? = nil, completion: @escaping (Bool) -> Void) {
        // Only store the poll question in content, not the options
        let pollContent = caption
        submitPost(contentType: "poll", content: pollContent, pollOptions: options, attachedMenuItem: attachedMenuItem, completion: completion, customPostId: customPostId)
    }
    
    private func uploadImageToStorage(image: UIImage, postId: String, completion: @escaping (String?) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            completion(nil)
            return
        }
        let storageRef = Storage.storage().reference().child("community_posts/\(postId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        storageRef.putData(imageData, metadata: metadata) { metadata, error in
            if let error = error {
                print("Image upload error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            storageRef.downloadURL { url, error in
                completion(url?.absoluteString)
            }
        }
    }
    
    private func uploadVideoToStorage(videoURL: URL, postId: String, completion: @escaping (String?) -> Void) {
        let storageRef = Storage.storage().reference().child("community_posts/\(postId).mp4")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        guard let videoData = try? Data(contentsOf: videoURL) else {
            completion(nil)
            return
        }
        storageRef.putData(videoData, metadata: metadata) { metadata, error in
            if let error = error {
                print("Video upload error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            storageRef.downloadURL { url, error in
                completion(url?.absoluteString)
            }
        }
    }
    
    // Overload submitPost to allow custom postId for media posts
    func submitPost(contentType: String, content: String, caption: String? = nil, pollOptions: [String]? = nil, mediaType: String? = nil, attachedMenuItem: MenuItem? = nil, completion: @escaping (Bool) -> Void, customPostId: String? = nil) {
        guard let user = Auth.auth().currentUser else {
            postSubmissionError = "User not authenticated."
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        print("Fetching user data for: \(user.uid)")
        userRef.getDocument(source: .default) { [weak self] snapshot, error in
            if let error = error {
                print("Error fetching user data: \(error.localizedDescription)")
                self?.postSubmissionError = "Failed to fetch user info: \(error.localizedDescription)"
                completion(false)
                return
            }
            guard let data = snapshot?.data() else {
                print("User data not found for: \(user.uid)")
                self?.postSubmissionError = "User data not found."
                completion(false)
                return
            }
            print("User data found: \(data)")
            let firstName = data["firstName"] as? String ?? "User"
            let profilePhotoURL = data["profilePhotoURL"] as? String
            let avatarEmoji = data["avatarEmoji"] as? String ?? "👤"
            let avatarColorName = data["avatarColor"] as? String ?? "gray"
            let isVerified = data["isVerified"] as? Bool ?? false
            let postId = customPostId ?? UUID().uuidString
            let post = CommunityPost(
                id: postId,
                userId: user.uid,
                userFirstName: firstName,
                userProfilePhotoURL: profilePhotoURL,
                avatarEmoji: avatarEmoji,
                avatarColorName: avatarColorName,
                isVerified: isVerified,
                contentType: contentType,
                content: content,
                caption: caption,
                mediaType: mediaType,
                pollOptions: pollOptions,
                pollVotes: [:], // Initialize with empty dictionary
                pollExpiresAt: nil,
                attachedMenuItem: attachedMenuItem,
                createdAt: Date(),
                likeCount: 0,
                replyCount: 0,
                isApproved: false,
                isDeleted: false
            )
            do {
                print("💾 Attempting to save post to Firestore with ID: \(postId)")
                try db.collection("posts").document(postId).setData(from: post) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Failed to save post to Firestore: \(error.localizedDescription)")
                            self?.postSubmissionError = "Failed to submit post: \(error.localizedDescription)"
                            completion(false)
                        } else {
                            print("✅ Successfully saved post to Firestore with ID: \(postId)")
                            self?.postSubmissionError = nil
                            completion(true)
                        }
                    }
                }
            } catch {
                print("❌ Failed to encode post: \(error)")
                self?.postSubmissionError = "Failed to encode post."
                completion(false)
            }
        }
    }
    
    // Admin helpers
    func checkIfCurrentUserIsAdmin(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let data = snapshot?.data(), let isAdmin = data["isAdmin"] as? Bool {
                    self?.isAdmin = isAdmin
                    completion(isAdmin)
                } else {
                    self?.isAdmin = false
                    completion(false)
                }
            }
        }
    }
    
    func fetchTotalStats() {
        // Get all posts and filter them properly to avoid double counting
        db.collection("posts").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching posts for stats: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ No posts found for stats calculation")
                    return
                }
                
                var totalPosts = 0
                var totalLikes = 0
                var totalComments = 0
                var processedPostIds = Set<String>()
                
                for doc in documents {
                    let data = doc.data()
                    let postId = doc.documentID
                    
                    // Skip if we've already processed this post
                    if processedPostIds.contains(postId) {
                        continue
                    }
                    
                    // Check if post is approved/not deleted using both data structures
                    let isReported = data["isReported"] as? Bool ?? false
                    let isApproved = data["isApproved"] as? Bool ?? true
                    let isDeleted = data["isDeleted"] as? Bool ?? false
                    
                    // Post is approved if:
                    // 1. New structure: isReported = false
                    // 2. Old structure: isApproved = true AND isDeleted = false
                    let isApprovedPost = (!isReported) || (isApproved && !isDeleted)
                    
                    if isApprovedPost {
                        totalPosts += 1
                        totalLikes += data["likeCount"] as? Int ?? 0
                        totalComments += data["replyCount"] as? Int ?? 0
                        processedPostIds.insert(postId)
                    }
                }
                
                self?.totalStats = (totalPosts, totalLikes, totalComments)
                print("📊 Updated stats - Posts: \(totalPosts), Likes: \(totalLikes), Comments: \(totalComments)")
            }
        }
    }
    
    func fetchPendingPostsCount(completion: @escaping (Int) -> Void) {
        let db = Firestore.firestore()
        db.collection("posts")
            .whereField("isReported", isEqualTo: true) // isReported = true means pending (same as pending posts)
            .getDocuments { snapshot, error in
                if let docs = snapshot?.documents {
                    completion(docs.count)
                } else {
                    completion(0)
                }
            }
    }
    
    func fetchPendingPosts(completion: @escaping ([CommunityPost], String?) -> Void) {
        let db = Firestore.firestore()
        print("🔍 Fetching pending posts...")
        db.collection("posts")
            .whereField("isReported", isEqualTo: true) // isReported = true means not approved (pending)
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching pending posts: \(error.localizedDescription)")
                    completion([], error.localizedDescription)
                    return
                }
                
                print("📄 Raw documents count: \(snapshot?.documents.count ?? 0)")
                
                let posts = snapshot?.documents.compactMap { doc -> CommunityPost? in
                    do {
                        let post = try doc.data(as: CommunityPost.self)
                        print("✅ Successfully decoded post: \(post.id), isReported: \(post.isReported), isApproved: \(post.isApproved)")
                        return post
                    } catch {
                        print("❌ Failed to decode post \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                
                print("📋 Found \(posts.count) pending posts for admin approval")
                for post in posts {
                    print("   - Post ID: \(post.id), Content: \(String(post.content.prefix(30)))...")
                }
                completion(posts, nil)
            }
    }
    
    func approvePost(postId: String, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        print("✅ Approving post: \(postId)")
        
        // First, get the current post data to verify it exists
        db.collection("posts").document(postId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching post \(postId) before approval: \(error.localizedDescription)")
                completion()
                return
            }
            
            guard let data = snapshot?.data() else {
                print("❌ Post \(postId) not found before approval")
                completion()
                return
            }
            
            print("📋 Current post data before approval: \(data)")
            
            // Set isReported to false to approve the post
            let updateData: [String: Any] = [
                "isReported": false
            ]
            
            print("📝 Updating post \(postId) with data: \(updateData)")
            
            db.collection("posts").document(postId).updateData(updateData) { error in
                if let error = error {
                    print("❌ Error approving post \(postId): \(error.localizedDescription)")
                } else {
                    print("✅ Successfully approved post: \(postId) (isReported=false)")
                    
                    // Verify the update worked by fetching the post again
                    db.collection("posts").document(postId).getDocument { snapshot, error in
                        if let error = error {
                            print("❌ Error verifying post \(postId) after approval: \(error.localizedDescription)")
                        } else if let data = snapshot?.data() {
                            print("📋 Post data after approval: \(data)")
                        } else {
                            print("❌ Post \(postId) not found after approval")
                        }
                        completion()
                    }
                }
            }
        }
    }
    
    func denyPost(postId: String, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        print("❌ Denying post: \(postId)")
        
        // First, delete the associated media files from Firebase Storage
        deletePostMediaFiles(postId: postId) {
            // Then delete the document from Firestore
            db.collection("posts").document(postId).delete { error in
                if let error = error {
                    print("❌ Error denying post \(postId): \(error.localizedDescription)")
                } else {
                    print("✅ Successfully denied post: \(postId) (deleted from database and cleaned up media files)")
                }
                completion()
            }
        }
    }
    
    // MARK: - Firebase Storage Cleanup
    
    /// Deletes a file from Firebase Storage
    private func deleteFileFromStorage(filePath: String, completion: @escaping (Bool) -> Void) {
        let storageRef = Storage.storage().reference().child(filePath)
        storageRef.delete { error in
            if let error = error {
                // Check if the error is because the file doesn't exist (which is fine)
                let errorCode = StorageErrorCode(rawValue: error._code)
                if errorCode == .objectNotFound {
                    print("ℹ️ File doesn't exist in Firebase Storage (expected): \(filePath)")
                    completion(true) // Consider this a success since the goal is achieved
                } else {
                    print("❌ Error deleting file from Firebase Storage (\(filePath)): \(error.localizedDescription)")
                    completion(false)
                }
            } else {
                print("✅ Successfully deleted file from Firebase Storage: \(filePath)")
                completion(true)
            }
        }
    }
    
    /// Deletes all media files associated with a post
    private func deletePostMediaFiles(postId: String, completion: @escaping () -> Void) {
        let group = DispatchGroup()
        
        // First, get the post data to determine what media files exist
        let db = Firestore.firestore()
        db.collection("posts").document(postId).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("❌ Error fetching post data for media cleanup: \(error.localizedDescription)")
                completion()
                return
            }
            
            guard let data = snapshot?.data() else {
                print("⚠️ Post data not found for media cleanup: \(postId)")
                completion()
                return
            }
            
            // Check media type and content
            let mediaType = data["mediaType"] as? String
            let content = data["content"] as? String ?? ""
            let contentType = data["contentType"] as? String ?? "text"
            
            print("🗑️ Cleaning up media files for post \(postId) - Type: \(mediaType ?? "none"), ContentType: \(contentType)")
            
            // Delete image files if this is an image post
            if mediaType == "image" || contentType == "image" {
                // Try multiple image extensions
                let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
                for ext in imageExtensions {
                    let imagePath = "community_posts/\(postId).\(ext)"
                    group.enter()
                    self?.deleteFileFromStorage(filePath: imagePath) { success in
                        if success {
                            print("✅ Deleted image file: \(imagePath)")
                        }
                        group.leave()
                    }
                }
            }
            
            // Delete video file if this is a video post
            if mediaType == "video" || contentType == "video" {
                // Try multiple video extensions
                let videoExtensions = ["mp4", "mov", "avi", "m4v"]
                for ext in videoExtensions {
                    let videoPath = "community_posts/\(postId).\(ext)"
                    group.enter()
                    self?.deleteFileFromStorage(filePath: videoPath) { success in
                        if success {
                            print("✅ Deleted video file: \(videoPath)")
                        }
                        group.leave()
                    }
                }
            }
            
            // If no specific media type, try common extensions (for backward compatibility)
            if mediaType == nil && contentType == "text" {
                // Only try to delete if content suggests it might be a media post
                if content.contains("community_posts") || content.contains("firebasestorage") {
                    let commonExtensions = ["jpg", "jpeg", "png", "mp4", "mov"]
                    for ext in commonExtensions {
                        let filePath = "community_posts/\(postId).\(ext)"
                        group.enter()
                        self?.deleteFileFromStorage(filePath: filePath) { success in
                            if success {
                                print("✅ Deleted file (backward compatibility): \(filePath)")
                            }
                            group.leave()
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                print("✅ Completed media file cleanup for post: \(postId)")
                completion()
            }
        }
    }
    
    func deletePost(postId: String, completion: @escaping (Bool, String?) -> Void) {
        let db = Firestore.firestore()
        print("🗑️ Permanently deleting post: \(postId)")
        
        // First, delete the associated media files from Firebase Storage
        deletePostMediaFiles(postId: postId) {
            // Then delete the document from Firestore
            db.collection("posts").document(postId).delete { error in
                if let error = error {
                    print("❌ Error deleting post \(postId): \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Successfully permanently deleted post: \(postId)")
                    // Refresh stats after deletion
                    self.fetchTotalStats()
                    completion(true, nil)
                }
            }
        }
    }
    
    // Admin: Send notification to all users linked to a post
    func sendNotificationForPost(post: CommunityPost, message: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let notificationId = UUID().uuidString
        let notificationData: [String: Any] = [
            "id": notificationId,
            "postId": post.id,
            "postContent": post.content,
            "sentBy": user.uid,
            "sentAt": FieldValue.serverTimestamp(),
            "message": message
        ]
        db.collection("notifications").document(notificationId).setData(notificationData) { error in
            completion(error == nil)
        }
    }
    
    // Like/unlike functionality
    func likePost(postId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let likeRef = db.collection("posts").document(postId).collection("likes").document(user.uid)
        let likeData: [String: Any] = [
            "userId": user.uid,
            "likedAt": FieldValue.serverTimestamp()
        ]
        likeRef.setData(likeData) { error in
            if let error = error {
                print("Like error: \(error.localizedDescription)")
                completion(false)
            } else {
                // Increment likeCount
                db.collection("posts").document(postId).updateData(["likeCount": FieldValue.increment(Int64(1))]) { _ in }
                completion(true)
            }
        }
    }
    
    func unlikePost(postId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let likeRef = db.collection("posts").document(postId).collection("likes").document(user.uid)
        likeRef.delete { error in
            if let error = error {
                print("Unlike error: \(error.localizedDescription)")
                completion(false)
            } else {
                // Decrement likeCount
                db.collection("posts").document(postId).updateData(["likeCount": FieldValue.increment(Int64(-1))]) { _ in }
                completion(true)
            }
        }
    }
    
    func hasLikedPost(postId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let likeRef = db.collection("posts").document(postId).collection("likes").document(user.uid)
        likeRef.getDocument { snapshot, error in
            if let doc = snapshot, doc.exists {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    // Reply functionality
    func fetchReplies(for postId: String, completion: @escaping ([CommunityReply]) -> Void) {
        let db = Firestore.firestore()
        db.collection("posts").document(postId).collection("replies")
            .order(by: "createdAt", descending: false)
            .getDocuments { snapshot, error in
                let replies = snapshot?.documents.compactMap { try? $0.data(as: CommunityReply.self) } ?? []
                completion(replies)
            }
    }
    
    func observeReplies(for postId: String, onUpdate: @escaping ([CommunityReply]) -> Void) -> ListenerRegistration {
        let db = Firestore.firestore()
        return db.collection("posts").document(postId).collection("replies")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                let replies = snapshot?.documents.compactMap { try? $0.data(as: CommunityReply.self) } ?? []
                onUpdate(replies)
            }
    }
    
    func addReply(to postId: String, content: String, replyingTo: String? = nil, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)
        userRef.getDocument { snapshot, error in
            let data = snapshot?.data() ?? [:]
            let firstName = data["firstName"] as? String ?? "User"
            let profilePhotoURL = data["profilePhotoURL"] as? String
            let avatarEmoji = data["avatarEmoji"] as? String ?? "👤"
            let avatarColorName = data["avatarColor"] as? String ?? "gray"
            let isVerified = data["isVerified"] as? Bool ?? false
            let replyId = UUID().uuidString
            let reply = CommunityReply(
                id: replyId,
                userId: user.uid,
                userFirstName: firstName,
                userProfilePhotoURL: profilePhotoURL,
                avatarEmoji: avatarEmoji,
                avatarColorName: avatarColorName,
                isVerified: isVerified,
                content: content,
                createdAt: Date(),
                replyingToId: replyingTo,
                likeCount: 0
            )
            do {
                try db.collection("posts").document(postId).collection("replies").document(replyId).setData(from: reply) { error in
                    if let error = error {
                        print("Reply error: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        // Increment replyCount
                        db.collection("posts").document(postId).updateData(["replyCount": FieldValue.increment(Int64(1))]) { _ in }
                        completion(true)
                    }
                }
            } catch {
                completion(false)
            }
        }
    }
    
    // Like/unlike a reply
    func likeReply(replyId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        // Find the reply first
        db.collectionGroup("replies").whereField("id", isEqualTo: replyId).getDocuments { snapshot, error in
            guard let document = snapshot?.documents.first else {
                print("❌ Reply not found: \(replyId)")
                completion(false)
                return
            }
            
            let replyRef = document.reference
            let likeField = "likes.\(user.uid)"
            
            replyRef.getDocument { snapshot, error in
                if let error = error {
                    print("❌ Error getting reply document: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                if let data = snapshot?.data(), let likes = data["likes"] as? [String: Bool], likes[user.uid] == true {
                    // Unlike
                    replyRef.updateData([
                        likeField: FieldValue.delete(),
                        "likeCount": FieldValue.increment(Int64(-1))
                    ]) { error in
                        if let error = error {
                            print("❌ Error unliking reply: \(error.localizedDescription)")
                            completion(false)
                        } else {
                            print("✅ Reply unliked successfully")
                            completion(true)
                        }
                    }
                } else {
                    // Like
                    replyRef.updateData([
                        likeField: true,
                        "likeCount": FieldValue.increment(Int64(1))
                    ]) { error in
                        if let error = error {
                            print("❌ Error liking reply: \(error.localizedDescription)")
                            completion(false)
                        } else {
                            print("✅ Reply liked successfully")
                            completion(true)
                        }
                    }
                }
            }
        }
    }
    
    // Check if user has liked a reply
    func hasLikedReply(replyId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        // Find the reply first
        db.collectionGroup("replies").whereField("id", isEqualTo: replyId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error finding reply: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot?.documents.first else {
                print("❌ Reply not found: \(replyId)")
                completion(false)
                return
            }
            
            let replyRef = document.reference
            replyRef.getDocument { snapshot, error in
                if let error = error {
                    print("❌ Error getting reply document: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                if let data = snapshot?.data(), let likes = data["likes"] as? [String: Bool] {
                    let hasLiked = likes[user.uid] == true
                    print("✅ Like status for reply \(replyId): \(hasLiked)")
                    completion(hasLiked)
                } else {
                    print("✅ Reply \(replyId) has no likes or user hasn't liked it")
                    completion(false)
                }
            }
        }
    }
    
    // Delete a reply (admin or reply author)
    func deleteReply(replyId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            print("❌ Delete reply failed: No authenticated user")
            completion(false)
            return
        }
        let db = Firestore.firestore()
        
        print("🔍 Attempting to delete reply: \(replyId)")
        print("👤 Current user ID: \(user.uid)")
        print("👑 Is admin: \(self.isAdmin)")
        
        // First, we need to find which post contains this reply
        // We'll search through all posts to find the one with this reply
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching posts: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("❌ No posts found")
                completion(false)
                return
            }
            
            // Search through each post's replies collection
            var foundReply: (document: DocumentSnapshot, postId: String)?
            
            let group = DispatchGroup()
            
            for postDoc in documents {
                group.enter()
                let postId = postDoc.documentID
                db.collection("posts").document(postId).collection("replies").document(replyId).getDocument { snapshot, error in
                    defer { group.leave() }
                    
                    if let document = snapshot, document.exists {
                        foundReply = (document, postId)
                    }
                }
            }
            
            group.notify(queue: .main) {
                guard let (document, postId) = foundReply else {
                    print("❌ Reply not found: \(replyId)")
                    completion(false)
                    return
                }
                
                let replyData = document.data() ?? [:]
                let replyUserId = replyData["userId"] as? String ?? ""
                
                print("📋 Reply data: \(replyData)")
                print("👤 Reply user ID: \(replyUserId)")
                print("🔐 User can delete: \(replyUserId == user.uid || self.isAdmin)")
                
                // Check if user is admin or reply author
                if replyUserId == user.uid || self.isAdmin {
                    let replyRef = document.reference
                    replyRef.delete { error in
                        if let error = error {
                            print("❌ Error deleting reply: \(error.localizedDescription)")
                            completion(false)
                        } else {
                            print("✅ Reply deleted successfully")
                            // Decrement replyCount on the post
                            db.collection("posts").document(postId).updateData([
                                "replyCount": FieldValue.increment(Int64(-1))
                            ]) { _ in }
                            completion(true)
                        }
                    }
                } else {
                    print("❌ User not authorized to delete this reply")
                    completion(false)
                }
            }
        }
    }
    
    // Poll voting functionality
    func voteInPoll(post: CommunityPost, optionIndex: Int, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let postRef = db.collection("posts").document(post.id)
        let field = "pollVotes.\(user.uid)"
        postRef.updateData([field: optionIndex]) { error in
            completion(error == nil)
        }
    }
    
    func getPollVote(post: CommunityPost, completion: @escaping (Int?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(nil)
            return
        }
        let db = Firestore.firestore()
        db.collection("posts").document(post.id).getDocument { snapshot, error in
            if let data = snapshot?.data(), let pollVotes = data["pollVotes"] as? [String: Any], let vote = pollVotes[user.uid] as? Int {
                completion(vote)
            } else {
                completion(nil)
            }
        }
    }
    
    func isPollExpired(post: CommunityPost) -> Bool {
        guard let expiresAt = post.pollExpiresAt else { return false }
        return Date() > expiresAt
    }
    
    // Pin/unpin functionality (admin only, one post at a time)
    func pinPost(postId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        print("📌 Pinning post: \(postId)")
        // Unpin all posts first
        db.collection("posts").whereField("isPinned", isEqualTo: true).getDocuments { snapshot, error in
            let batch = db.batch()
            snapshot?.documents.forEach { doc in
                print("📌 Unpinning existing pinned post: \(doc.documentID)")
                batch.updateData(["isPinned": false], forDocument: doc.reference)
            }
            let targetRef = db.collection("posts").document(postId)
            print("📌 Setting post \(postId) as pinned")
            batch.updateData(["isPinned": true], forDocument: targetRef)
            batch.commit { err in
                if let err = err {
                    print("❌ Error pinning post: \(err.localizedDescription)")
                } else {
                    print("✅ Successfully pinned post: \(postId)")
                }
                completion(err == nil)
            }
        }
    }
    
    func unpinPost(postId: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        print("📌 Unpinning post: \(postId)")
        db.collection("posts").document(postId).updateData(["isPinned": false]) { error in
            if let error = error {
                print("❌ Error unpinning post: \(error.localizedDescription)")
            } else {
                print("✅ Successfully unpinned post: \(postId)")
            }
            completion(error == nil)
        }
    }
    
    // Reporting functionality
    func reportPost(postId: String, reason: String, details: String?, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let reportId = UUID().uuidString
        let reportData: [String: Any] = [
            "id": reportId,
            "postId": postId,
            "userId": user.uid,
            "reason": reason,
            "details": details ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection("reports").document(reportId).setData(reportData) { error in
            completion(error == nil)
        }
    }
    
    func reportComment(commentId: String, reason: String, details: String?, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let reportId = UUID().uuidString
        let reportData: [String: Any] = [
            "id": reportId,
            "commentId": commentId,
            "userId": user.uid,
            "reason": reason,
            "details": details ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "reviewed": false
        ]
        db.collection("commentReports").document(reportId).setData(reportData) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error reporting comment: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Comment reported successfully")
                    completion(true)
                }
            }
        }
    }
    
    // Admin: Fetch all reports, grouped by postId
    func fetchAllReports(completion: @escaping ([String: [Report]]) -> Void) {
        db.collection("reports").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching reports: \(error.localizedDescription)")
                    completion([:])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([:])
                    return
                }
                
                var reportsByPost: [String: [Report]] = [:]
                let group = DispatchGroup()
                
                for doc in documents {
                    let data = doc.data()
                    let report = Report(
                        id: doc.documentID,
                        postId: data["postId"] as? String ?? "",
                        userId: data["userId"] as? String ?? "",
                        reason: data["reason"] as? String ?? "",
                        details: data["details"] as? String,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                        reviewed: data["reviewed"] as? Bool
                    )
                    
                    // Check if the post still exists and isn't deleted
                    group.enter()
                    self.db.collection("posts").document(report.postId).getDocument { postSnapshot, postError in
                        defer { group.leave() }
                        
                        if let postError = postError {
                            print("❌ Error checking post \(report.postId): \(postError.localizedDescription)")
                            return
                        }
                        
                        guard let postData = postSnapshot?.data() else {
                            print("⚠️ Post \(report.postId) no longer exists")
                            return
                        }
                        
                        // Check if post is deleted (using both old and new data structures)
                        let isDeleted = postData["isDeleted"] as? Bool ?? false
                        let isReported = postData["isReported"] as? Bool ?? false
                        
                        // Only include reports for posts that exist, aren't deleted, and aren't reviewed
                        if !isDeleted && report.reviewed != true {
                            if reportsByPost[report.postId] == nil {
                                reportsByPost[report.postId] = []
                            }
                            reportsByPost[report.postId]?.append(report)
                        } else if isDeleted {
                            print("⚠️ Skipping report for deleted post \(report.postId)")
                        } else if report.reviewed == true {
                            print("⚠️ Skipping reviewed report for post \(report.postId)")
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    completion(reportsByPost)
                }
            }
        }
    }
    
    // Admin: Mark a report as reviewed
    func markReportReviewed(reportId: String, completion: @escaping (Bool) -> Void) {
        db.collection("reports").document(reportId).updateData([
            "reviewed": true
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error marking report as reviewed: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Report marked as reviewed successfully")
                    completion(true)
                }
            }
        }
    }
    
    // Admin: Mark a comment report as reviewed
    func markCommentReportReviewed(reportId: String, completion: @escaping (Bool) -> Void) {
        db.collection("commentReports").document(reportId).updateData([
            "reviewed": true
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error marking comment report as reviewed: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Comment report marked as reviewed successfully")
                    completion(true)
                }
            }
        }
    }
    
    // Admin: Fetch all comment reports
    func fetchAllCommentReports(completion: @escaping ([String: [CommentReport]]) -> Void) {
        db.collection("commentReports").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching comment reports: \(error.localizedDescription)")
                    completion([:])
                    return
                }
                
                var reportsByComment: [String: [CommentReport]] = [:]
                
                for document in snapshot?.documents ?? [] {
                    do {
                        let report = try document.data(as: CommentReport.self)
                        // Only include unreviewed reports
                        if report.reviewed != true {
                            if reportsByComment[report.commentId] == nil {
                                reportsByComment[report.commentId] = []
                            }
                            reportsByComment[report.commentId]?.append(report)
                        }
                    } catch {
                        print("❌ Error parsing comment report: \(error)")
                    }
                }
                
                completion(reportsByComment)
            }
        }
    }
    
    // Admin: Fetch a comment by ID
    func fetchComment(commentId: String, completion: @escaping (CommunityReply?) -> Void) {
        // Search through all posts to find the one with this reply
        db.collection("posts").getDocuments { [self] snapshot, error in
            if let error = error {
                print("❌ Error fetching posts: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("❌ No posts found")
                completion(nil)
                return
            }
            
            // Search through each post's replies collection
            let group = DispatchGroup()
            var foundReply: CommunityReply?
            
            for postDoc in documents {
                group.enter()
                let postId = postDoc.documentID
                self.db.collection("posts").document(postId).collection("replies").document(commentId).getDocument { snapshot, error in
                    defer { group.leave() }
                    
                    if let document = snapshot, document.exists {
                        do {
                            let reply = try document.data(as: CommunityReply.self)
                            foundReply = reply
                        } catch {
                            print("❌ Error parsing comment: \(error)")
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(foundReply)
            }
        }
    }
    
    // Admin: Delete a comment
    func deleteComment(commentId: String, completion: @escaping (Bool) -> Void) {
        // First, we need to find which post contains this reply
        // We'll search through all posts to find the one with this reply
        db.collection("posts").getDocuments { [self] snapshot, error in
            if let error = error {
                print("❌ Error fetching posts: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("❌ No posts found")
                completion(false)
                return
            }
            
            // Search through each post's replies collection
            var foundReply: (document: DocumentSnapshot, postId: String)?
            
            let group = DispatchGroup()
            
            for postDoc in documents {
                group.enter()
                let postId = postDoc.documentID
                self.db.collection("posts").document(postId).collection("replies").document(commentId).getDocument { snapshot, error in
                    defer { group.leave() }
                    
                    if let document = snapshot, document.exists {
                        foundReply = (document, postId)
                    }
                }
            }
            
            group.notify(queue: .main) {
                guard let (document, postId) = foundReply else {
                    print("❌ Comment not found: \(commentId)")
                    completion(false)
                    return
                }
                
                // Check if comment has any media files to delete
                let commentData = document.data()
                let hasMedia = commentData?["hasMedia"] as? Bool ?? false
                
                if hasMedia {
                    // Delete any associated media files from Firebase Storage
                    let commentImagePath = "community_comments/\(commentId).jpg"
                    let commentVideoPath = "community_comments/\(commentId).mp4"
                    
                    let mediaGroup = DispatchGroup()
                    
                    mediaGroup.enter()
                    deleteFileFromStorage(filePath: commentImagePath) { _ in
                        mediaGroup.leave()
                    }
                    
                    mediaGroup.enter()
                    deleteFileFromStorage(filePath: commentVideoPath) { _ in
                        mediaGroup.leave()
                    }
                    
                    mediaGroup.notify(queue: .main) {
                        // Now delete the comment document
                        self.deleteCommentDocument(replyRef: document.reference, postId: postId, completion: completion)
                    }
                } else {
                    // No media files, just delete the comment document
                    self.deleteCommentDocument(replyRef: document.reference, postId: postId, completion: completion)
                }
            }
        }
    }
    
    // Helper method to delete comment document
    private func deleteCommentDocument(replyRef: DocumentReference, postId: String, completion: @escaping (Bool) -> Void) {
        replyRef.delete { [self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error deleting comment: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Comment deleted successfully")
                    // Decrement replyCount on the post
                    self.db.collection("posts").document(postId).updateData([
                        "replyCount": FieldValue.increment(Int64(-1))
                    ]) { _ in }
                    completion(true)
                }
            }
        }
    }
    
    // Debug method to check all posts
    func debugAllPosts() {
        print("🔍 Debugging all posts in collection...")
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error getting all posts: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("⚠️ No documents found")
                return
            }
            
            print("📄 Found \(documents.count) total documents in posts collection")
            
            for (index, doc) in documents.enumerated() {
                let data = doc.data()
                print("📋 Document \(index + 1) (ID: \(doc.documentID)):")
                let isApproved = data["isApproved"]
                let isDeleted = data["isDeleted"]
                let contentType = data["contentType"]
                let userFirstName = data["userFirstName"]
                let createdAt = data["createdAt"]
                print("   isApproved: \(String(describing: isApproved))")
                print("   isDeleted: \(String(describing: isDeleted))")
                print("   contentType: \(String(describing: contentType))")
                print("   userFirstName: \(String(describing: userFirstName))")
                print("   createdAt: \(String(describing: createdAt))")
            }
        }
    }
    
    // Method to refresh posts (for pull-to-refresh)
    func refreshPosts() {
        print("🔄 Refreshing posts...")
        hasInitializedListener = false
        fetchPosts()
    }
    

    
    // MARK: - Large Scale Optimization Methods
    
    /// Optimized method for handling large datasets with improved memory management
    func optimizeForLargeScale() {
        // OPTIMIZED: More aggressive cache reduction for very large user bases
        maxCachedProfiles = 15 // Reduced from 20 for very large scale
        maxImageCacheSize = 20 // Reduced from 30 for very large scale
        maxCommentCacheSize = 10 // Reduced from 15 for very large scale
        
        // OPTIMIZED: More frequent cleanup for very large datasets
        profileCacheTimer?.invalidate()
        profileCacheTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            self?.cleanupAllCaches()
        }
        
        // OPTIMIZED: More conservative rate limiting for large scale
        minimumRequestInterval = 1.0 // Increased to 1 second between requests
        
        // Reset rate limiting
        isRateLimited = false
        consecutiveErrors = 0
        
        print("🔧 Large scale optimizations applied - Very aggressive mode")
    }
    
    // MARK: - Rate Limiting and Error Handling
    private func checkRateLimit() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastRequestTime) < minimumRequestInterval {
            return false // Rate limited
        }
        lastRequestTime = now
        return true
    }
    
    private func handleError(_ error: Error) {
        consecutiveErrors += 1
        if consecutiveErrors >= maxConsecutiveErrors {
            isRateLimited = true
            print("⚠️ Rate limiting activated due to consecutive errors")
            
            // Reset after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.isRateLimited = false
                self?.consecutiveErrors = 0
                print("✅ Rate limiting deactivated")
            }
        }
    }
    
    private func handleSuccess() {
        consecutiveErrors = 0
    }
    
    func restorePost(postId: String, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        print("🔄 Restoring post: \(postId)")
        // First, get the current post data to check its approval status
        db.collection("posts").document(postId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching post \(postId) for restore: \(error.localizedDescription)")
                completion()
                return
            }
            
            guard let data = snapshot?.data() else {
                print("❌ Post data not found for restore: \(postId)")
                completion()
                return
            }
            
            let wasApproved = data["isApproved"] as? Bool ?? false
            
            // Restore the post with the correct approval status
            let updateData: [String: Any] = [
                "isDeleted": false,
                "isApproved": wasApproved // Maintain the original approval status
            ]
            
            db.collection("posts").document(postId).updateData(updateData) { error in
                if let error = error {
                    print("❌ Error restoring post \(postId): \(error.localizedDescription)")
                } else {
                    print("✅ Successfully restored post: \(postId) (isDeleted=false, isApproved=\(wasApproved))")
                }
                completion()
            }
        }
    }
    
    // Helper function to fix inconsistent post states
    func fixPostState(postId: String, completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        print("🔧 Fixing post state: \(postId)")
        
        db.collection("posts").document(postId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching post \(postId) for state fix: \(error.localizedDescription)")
                completion()
                return
            }
            
            guard let data = snapshot?.data() else {
                print("❌ Post data not found for state fix: \(postId)")
                completion()
                return
            }
            
            let isApproved = data["isApproved"] as? Bool ?? false
            let isDeleted = data["isDeleted"] as? Bool ?? false
            
            print("📋 Current post state - isApproved: \(isApproved), isDeleted: \(isDeleted)")
            
            // Fix inconsistent states
            var needsUpdate = false
            var updateData: [String: Any] = [:]
            
            // If post is approved but also deleted, that's inconsistent
            if isApproved && isDeleted {
                print("⚠️ Inconsistent state detected: approved but deleted")
                updateData["isDeleted"] = false
                needsUpdate = true
            }
            
            // If post is not approved and not deleted, that's the default state (pending)
            // If post is approved and not deleted, that's the correct approved state
            // If post is not approved and deleted, that's the correct denied state
            
            if needsUpdate {
                db.collection("posts").document(postId).updateData(updateData) { error in
                    if let error = error {
                        print("❌ Error fixing post state \(postId): \(error.localizedDescription)")
                    } else {
                        print("✅ Successfully fixed post state: \(postId)")
                    }
                    completion()
                }
            } else {
                print("✅ Post state is already consistent")
                completion()
            }
        }
    }
    
    func fetchAllPosts(completion: @escaping ([CommunityPost], String?) -> Void) {
        let db = Firestore.firestore()
        print("🔍 Fetching ALL posts for admin dashboard...")
        
        // Fetch ALL posts regardless of status for admin dashboard
        db.collection("posts")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching all posts: \(error.localizedDescription)")
                    completion([], error.localizedDescription)
                    return
                }
                
                var allPosts = snapshot?.documents.compactMap { doc -> CommunityPost? in
                    do {
                        let post = try doc.data(as: CommunityPost.self)
                        return post
                    } catch {
                        print("❌ Failed to parse post \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                
                // Sort by creation date
                allPosts.sort { $0.createdAt > $1.createdAt }
                
                print("📋 Total posts for admin dashboard: \(allPosts.count)")
                print("📊 Breakdown:")
                let approvedPosts = allPosts.filter { post in
                    if let data = snapshot?.documents.first(where: { $0.documentID == post.id })?.data() {
                        let isReported = data["isReported"] as? Bool ?? false
                        let isApproved = data["isApproved"] as? Bool ?? true
                        let isDeleted = data["isDeleted"] as? Bool ?? false
                        return !isReported && isApproved && !isDeleted
                    }
                    return true
                }
                let pendingPosts = allPosts.filter { post in
                    if let data = snapshot?.documents.first(where: { $0.documentID == post.id })?.data() {
                        let isReported = data["isReported"] as? Bool ?? false
                        return isReported
                    }
                    return false
                }
                let deletedPosts = allPosts.filter { post in
                    if let data = snapshot?.documents.first(where: { $0.documentID == post.id })?.data() {
                        let isDeleted = data["isDeleted"] as? Bool ?? false
                        return isDeleted
                    }
                    return false
                }
                print("   ✅ Approved: \(approvedPosts.count)")
                print("   ⏳ Pending: \(pendingPosts.count)")
                print("   🗑️ Deleted: \(deletedPosts.count)")
                
                completion(allPosts, nil)
            }
    }
    
    func fetchAllPostsWithPagination(limit: Int = 20, lastDocument: DocumentSnapshot? = nil, completion: @escaping ([CommunityPost], DocumentSnapshot?, Bool, String?) -> Void) {
        let db = Firestore.firestore()
        print("🔍 Fetching posts with pagination (limit: \(limit))...")
        
        var query = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let lastDocument = lastDocument {
            query = query.start(afterDocument: lastDocument)
        }
        
        query.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching posts with pagination: \(error.localizedDescription)")
                completion([], nil, false, error.localizedDescription)
                return
            }
            
            let posts = snapshot?.documents.compactMap { doc -> CommunityPost? in
                do {
                    let post = try doc.data(as: CommunityPost.self)
                    return post
                } catch {
                    print("❌ Failed to parse post \(doc.documentID): \(error)")
                    return nil
                }
            } ?? []
            
            let lastDoc = snapshot?.documents.last
            let hasMore = snapshot?.documents.count == limit
            
            print("📋 Fetched \(posts.count) posts, hasMore: \(hasMore)")
            completion(posts, lastDoc, hasMore, nil)
        }
    }
    
    // MARK: - Verification Request Methods
    
    func fetchVerificationRequests(completion: @escaping ([VerificationRequest]) -> Void) {
        db.collection("verificationRequests")
            .whereField("status", isEqualTo: "pending")
            .order(by: "requestedAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error fetching verification requests: \(error.localizedDescription)")
                        completion([])
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        completion([])
                        return
                    }
                    
                    let requests = documents.compactMap { doc -> VerificationRequest? in
                        let data = doc.data()
                        return VerificationRequest(
                            id: doc.documentID,
                            userId: data["userId"] as? String ?? "",
                            userFirstName: data["userFirstName"] as? String ?? "",
                            requestedAt: (data["requestedAt"] as? Timestamp)?.dateValue() ?? Date(),
                            status: data["status"] as? String ?? "pending"
                        )
                    }
                    
                    completion(requests)
                }
            }
    }
    
    func approveVerificationRequest(requestId: String, completion: @escaping (Bool) -> Void) {
        let batch = db.batch()
        
        // Update verification request status
        let requestRef = db.collection("verificationRequests").document(requestId)
        batch.updateData(["status": "approved"], forDocument: requestRef)
        
        // Get the request to find the user ID
        requestRef.getDocument { snapshot, error in
            if let error = error {
                print("❌ Error getting verification request: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let data = snapshot?.data(),
                  let userId = data["userId"] as? String else {
                print("❌ No user ID found in verification request")
                completion(false)
                return
            }
            
            // Update user's verification status
            let userRef = self.db.collection("users").document(userId)
            batch.updateData(["isVerified": true], forDocument: userRef)
            
            // Commit the batch
            batch.commit { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error approving verification request: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        print("✅ Verification request approved successfully")
                        completion(true)
                    }
                }
            }
        }
    }
    
    func denyVerificationRequest(requestId: String, completion: @escaping (Bool) -> Void) {
        db.collection("verificationRequests").document(requestId).updateData([
            "status": "denied"
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error denying verification request: \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ Verification request denied successfully")
                    completion(true)
                }
            }
        }
    }
    
    // MARK: - Admin Functions
    
    func dismissReports(for postId: String, completion: @escaping (Bool) -> Void) {
        // First, get all reports for this post
        db.collection("reports").whereField("postId", isEqualTo: postId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching reports for dismissal: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            guard let documents = snapshot?.documents, !documents.isEmpty else {
                print("✅ No reports found for post \(postId)")
                DispatchQueue.main.async {
                    completion(true)
                }
                return
            }
            
            // Mark all reports as reviewed
            let batch = self.db.batch()
            for doc in documents {
                let reportRef = doc.reference
                batch.updateData(["reviewed": true], forDocument: reportRef)
            }
            
            batch.commit { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error dismissing reports: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        print("✅ Successfully dismissed \(documents.count) reports for post \(postId)")
                        completion(true)
                    }
                }
            }
        }
    }
    
    func approveVerification(userId: String, completion: @escaping (Bool) -> Void) {
        // Find the verification request for this user
        db.collection("verificationRequests").whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error finding verification request: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot?.documents.first else {
                print("❌ No verification request found for user")
                completion(false)
                return
            }
            
            // Approve the request
            self.approveVerificationRequest(requestId: document.documentID, completion: completion)
        }
    }
    
    func rejectVerification(userId: String, completion: @escaping (Bool) -> Void) {
        // Find the verification request for this user
        db.collection("verificationRequests").whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error finding verification request: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let document = snapshot?.documents.first else {
                print("❌ No verification request found for user")
                completion(false)
                return
            }
            
            // Deny the request
            self.denyVerificationRequest(requestId: document.documentID, completion: completion)
        }
    }
    
    // MARK: - Avatar Update Functions
    
    func updateUserAvatarInAllPosts(userId: String, avatarEmoji: String, avatarColorName: String, completion: @escaping (Bool) -> Void) {
        let batch = db.batch()
        
        // Update all posts by this user
        db.collection("posts").whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching user posts: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("✅ No posts found for user")
                completion(true)
                return
            }
            
            // Update posts
            for doc in documents {
                let postRef = doc.reference
                batch.updateData([
                    "avatarEmoji": avatarEmoji,
                    "avatarColorName": avatarColorName
                ], forDocument: postRef)
            }
            
            // Update replies for this user in all posts
            self.updateUserAvatarInAllReplies(userId: userId, avatarEmoji: avatarEmoji, avatarColorName: avatarColorName) { success in
                if success {
                    // Commit the batch update for posts
                    batch.commit { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ Error updating posts: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("✅ Successfully updated \(documents.count) posts for user")
                                completion(true)
                            }
                        }
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private func updateUserAvatarInAllReplies(userId: String, avatarEmoji: String, avatarColorName: String, completion: @escaping (Bool) -> Void) {
        // Get all posts that have replies
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching posts for reply updates: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let postDocuments = snapshot?.documents else {
                print("✅ No posts found for reply updates")
                completion(true)
                return
            }
            
            let group = DispatchGroup()
            var hasErrors = false
            
            for postDoc in postDocuments {
                group.enter()
                
                // Get replies for this post
                postDoc.reference.collection("replies").whereField("userId", isEqualTo: userId).getDocuments { replySnapshot, replyError in
                    defer { group.leave() }
                    
                    if let replyError = replyError {
                        print("❌ Error fetching replies for post \(postDoc.documentID): \(replyError.localizedDescription)")
                        hasErrors = true
                        return
                    }
                    
                    guard let replyDocuments = replySnapshot?.documents else {
                        return
                    }
                    
                    // Update replies for this user
                    let replyBatch = self.db.batch()
                    for replyDoc in replyDocuments {
                        let replyRef = replyDoc.reference
                        replyBatch.updateData([
                            "avatarEmoji": avatarEmoji,
                            "avatarColorName": avatarColorName
                        ], forDocument: replyRef)
                    }
                    
                    replyBatch.commit { batchError in
                        if let batchError = batchError {
                            print("❌ Error updating replies for post \(postDoc.documentID): \(batchError.localizedDescription)")
                            hasErrors = true
                        } else if !replyDocuments.isEmpty {
                            print("✅ Updated \(replyDocuments.count) replies for post \(postDoc.documentID)")
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion(!hasErrors)
            }
        }
    }
    
    // Reaction functionality
    func addReaction(postId: String, reaction: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let reactionRef = db.collection("posts").document(postId).collection("reactions").document(user.uid)
        let reactionData: [String: Any] = [
            "userId": user.uid,
            "reaction": reaction,
            "reactedAt": FieldValue.serverTimestamp()
        ]
        reactionRef.setData(reactionData) { error in
            if let error = error {
                print("Reaction error: \(error.localizedDescription)")
                completion(false)
            } else {
                // Update reaction count
                db.collection("posts").document(postId).updateData([
                    "reactionCount": FieldValue.increment(Int64(1))
                ]) { _ in }
                completion(true)
            }
        }
    }
    
    func removeReaction(postId: String, completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        let db = Firestore.firestore()
        let reactionRef = db.collection("posts").document(postId).collection("reactions").document(user.uid)
        reactionRef.delete { error in
            if let error = error {
                print("Remove reaction error: \(error.localizedDescription)")
                completion(false)
            } else {
                // Decrement reaction count
                db.collection("posts").document(postId).updateData([
                    "reactionCount": FieldValue.increment(Int64(-1))
                ]) { _ in }
                completion(true)
            }
        }
    }
    
    func getUserReaction(postId: String, completion: @escaping (String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(nil)
            return
        }
        let db = Firestore.firestore()
        let reactionRef = db.collection("posts").document(postId).collection("reactions").document(user.uid)
        reactionRef.getDocument { snapshot, error in
            if let doc = snapshot, doc.exists {
                let reaction = doc.data()?["reaction"] as? String
                completion(reaction)
            } else {
                completion(nil)
            }
        }
    }
    
    // --- NEW: Fetch user profile for a given userId with memory management ---
    func fetchUserProfile(userId: String) {
        guard !userId.isEmpty else { return }
        if userProfiles[userId] != nil || userProfileFetches.contains(userId) { return }
        
        // Memory management: remove oldest profiles if cache is full
        if userProfiles.count >= maxCachedProfiles {
            let oldestKeys = Array(userProfiles.keys.prefix(userProfiles.count - maxCachedProfiles + 1))
            for key in oldestKeys {
                userProfiles.removeValue(forKey: key)
                userProfileListeners[key]?.remove()
                userProfileListeners.removeValue(forKey: key)
            }
            print("🧹 Cleaned up \(oldestKeys.count) old user profiles from cache")
        }
        
        userProfileFetches.insert(userId)
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async(execute: {
                guard let self = self else { return }
                self.userProfileFetches.remove(userId)
                
                if let data = snapshot?.data() {
                    let profile = UserProfile(
                        id: userId,
                        firstName: data["firstName"] as? String ?? "User",
                        lastName: data["lastName"] as? String ?? "",
                        email: data["email"] as? String ?? "",
                        avatarEmoji: data["avatarEmoji"] as? String ?? "👤",
                        avatarColorName: data["avatarColor"] as? String ?? "gray",
                        profilePhotoURL: data["profilePhotoURL"] as? String,
                        lastActive: Date(),
                        isVerified: data["isVerified"] as? Bool ?? false
                    )
                    self.userProfiles[userId] = profile
                    
                    // Set up real-time listener for this user profile
                    self.observeUserProfile(userId: userId)
                }
            })
        }
    }
    
    // --- NEW: Refresh user profile for a given userId (force refresh) ---
    func refreshUserProfile(userId: String) {
        guard !userId.isEmpty else { return }
        
        // Remove from cache to force refresh
        userProfiles.removeValue(forKey: userId)
        userProfileFetches.remove(userId)
        
        // Fetch fresh data
        fetchUserProfile(userId: userId)
    }
    
    // --- NEW: Set up real-time listener for user profile updates ---
    func observeUserProfile(userId: String) {
        guard !userId.isEmpty else { return }
        
        // Remove existing listener if any
        userProfileListeners[userId]?.remove()
        
        // Set up new listener
        let listener = db.collection("users").document(userId).addSnapshotListener { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let data = snapshot?.data() {
                    let profile = UserProfile(
                        id: userId,
                        firstName: data["firstName"] as? String ?? "User",
                        lastName: data["lastName"] as? String ?? "",
                        email: data["email"] as? String ?? "",
                        avatarEmoji: data["avatarEmoji"] as? String ?? "👤",
                        avatarColorName: data["avatarColor"] as? String ?? "gray",
                        profilePhotoURL: data["profilePhotoURL"] as? String,
                        lastActive: Date(),
                        isVerified: data["isVerified"] as? Bool ?? false
                    )
                    self.userProfiles[userId] = profile
                    print("🔄 Updated user profile for \(userId): \(profile.avatarEmoji ?? "no emoji")")
                }
            }
        }
        
        userProfileListeners[userId] = listener
    }
    // --- END NEW ---
    
    // --- NEW: Refresh comment counts for all posts ---
    func refreshCommentCounts() {
        print("🔄 Refreshing comment counts for all posts...")
        let db = Firestore.firestore()
        
        // Get all post IDs
        let postIds = posts.map { $0.id }
        
        for postId in postIds {
            db.collection("posts").document(postId).getDocument { [weak self] snapshot, error in
                DispatchQueue.main.async(execute: {
                    guard let self = self else { return }
                    
                    if let data = snapshot?.data() {
                        let currentReplyCount = data["replyCount"] as? Int ?? 0
                        
                        // Update the post in our array if the count has changed
                        if let postIndex = self.posts.firstIndex(where: { $0.id == postId }) {
                            let currentPost = self.posts[postIndex]
                            if currentPost.replyCount != currentReplyCount {
                                // Create updated post with new comment count
                                var updatedPost = currentPost
                                updatedPost.commentCount = currentReplyCount
                                self.posts[postIndex] = updatedPost
                                
                                // Also update in regular/pinned posts arrays
                                if let regularIndex = self.regularPosts.firstIndex(where: { $0.id == postId }) {
                                    self.regularPosts[regularIndex] = updatedPost
                                }
                                if let pinnedIndex = self.pinnedPosts.firstIndex(where: { $0.id == postId }) {
                                    self.pinnedPosts[pinnedIndex] = updatedPost
                                }
                                
                                print("📝 Updated comment count for post \(postId): \(currentPost.replyCount) -> \(currentReplyCount)")
                            }
                        }
                    }
                })
            }
        }
    }
    // --- END NEW ---
    
    // Call this to show more regular posts
    func showMoreRegularPosts() {
        let previousCount = regularPostsShown
        regularPostsShown += postsPerPage
        
        // Fetch additional posts from Firestore
        fetchMorePosts(currentCount: previousCount, newCount: regularPostsShown)
    }
    
    func observeReactions(for postId: String) {
        let db = Firestore.firestore()
        db.collection("posts").document(postId).collection("reactions").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            var counts: [String: Int] = [:]
            if let docs = snapshot?.documents {
                for doc in docs {
                    if let reaction = doc.data()["reaction"] as? String {
                        counts[reaction, default: 0] += 1
                    }
                }
            }
            DispatchQueue.main.async(execute: {
                self.reactionsForPost[postId] = counts
            })
        }
    }
    
    // Fetch latest pollVotes for a post
    func fetchLatestPollVotes(for postId: String, completion: @escaping ([String: Int]?) -> Void) {
        let db = Firestore.firestore()
        db.collection("posts").document(postId).getDocument { snapshot, error in
            if let data = snapshot?.data(), let pollVotes = data["pollVotes"] as? [String: Int] {
                completion(pollVotes)
            } else {
                completion(nil)
            }
        }
    }
    
    // Fetch additional posts when user taps "Load More"
    private func fetchMorePosts(currentCount: Int, newCount: Int) {
        let db = Firestore.firestore()
        
        // Get the last document from current posts to use as starting point
        guard let lastDoc = lastDocument else {
            print("❌ No last document available for pagination")
            return
        }
        
        print("🔄 Fetching more posts: \(currentCount) -> \(newCount)")
        
        // Fetch additional posts starting from the last document
        let additionalQuery = db.collection("posts")
            .whereField("isReported", isEqualTo: false)
            .whereField("isPinned", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .start(afterDocument: lastDoc)
            .limit(to: postsPerPage)
        
        additionalQuery.getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async(execute: {
                if let error = error {
                    print("❌ Error fetching additional posts: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("📄 No more posts to load")
                    self?.hasMorePosts = false
                    return
                }
                
                let additionalPosts = documents.compactMap { doc -> CommunityPost? in
                    do {
                        let post = try doc.data(as: CommunityPost.self)
                        return post
                    } catch {
                        print("❌ Failed to parse additional post \(doc.documentID): \(error)")
                        return nil
                    }
                }
                
                // Add new posts to existing regular posts
                self?.regularPosts.append(contentsOf: additionalPosts)
                
                // Update the last document for next pagination
                self?.lastDocument = documents.last
                
                // Check if there are more posts available
                self?.hasMorePosts = documents.count == self?.postsPerPage
                
                // Update the combined posts array
                self?.posts = (self?.pinnedPosts ?? []) + (self?.regularPosts ?? [])
                
                print("✅ Loaded \(additionalPosts.count) additional posts")
                print("📊 Total regular posts now: \(self?.regularPosts.count ?? 0)")
            })
        }
    }
    
    private func updateDisplayedPosts() {
        let postsToShow = Array(regularPosts.prefix(regularPostsShown))
        posts = pinnedPosts + postsToShow
        hasMorePosts = regularPostsShown < regularPosts.count || hasMorePostsAvailable
    }
    
    // MARK: - Optimized Comment Loading
    func loadCommentsForPost(_ postId: String, forceRefresh: Bool = false, completion: @escaping ([CommunityReply]) -> Void) {
        // Check cache first
        if !forceRefresh, let cachedComments = commentCache[postId] {
            completion(cachedComments)
            return
        }
        
        // Load comments with pagination
        var query = db.collection("posts").document(postId).collection("replies")
            .order(by: "createdAt", descending: false)
            .limit(to: commentsPerPage)
        
        if let paginationState = commentPaginationState[postId],
           let lastDoc = paginationState.lastDoc {
            query = query.start(afterDocument: lastDoc)
        }
        
        query.getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error loading comments: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let comments = snapshot?.documents.compactMap { doc -> CommunityReply? in
                    try? doc.data(as: CommunityReply.self)
                } ?? []
                
                // Update cache
                if let existingComments = self?.commentCache[postId] {
                    self?.commentCache[postId] = existingComments + comments
                } else {
                    self?.commentCache[postId] = comments
                }
                
                // Update pagination state
                self?.commentPaginationState[postId] = (
                    lastDoc: snapshot?.documents.last,
                    hasMore: comments.count == self?.commentsPerPage
                )
                
                completion(self?.commentCache[postId] ?? [])
            }
        }
    }
    
    // MARK: - Optimized Image Loading
    func loadImageWithCaching(from url: String, completion: @escaping (UIImage?) -> Void) {
        // Validate URL first
        guard !url.isEmpty, let imageURL = URL(string: url) else {
            print("❌ Invalid image URL: \(url)")
            completion(nil)
            return
        }
        
        // Check memory cache first
        if let cachedImage = imageCache[url] {
            print("✅ Image found in memory cache: \(url)")
            completion(cachedImage)
            return
        }
        
        // Check disk cache using Kingfisher
        let cache = ImageCache.default
        cache.retrieveImage(forKey: url) { result in
            switch result {
            case .success(let value):
                DispatchQueue.main.async {
                    if let uiImage = value.image {
                        print("✅ Image found in disk cache: \(url)")
                        self.imageCache[url] = uiImage
                        completion(uiImage)
                    } else {
                        print("🔄 Image not in disk cache, downloading: \(url)")
                        self.downloadAndCacheImage(from: url, completion: completion)
                    }
                }
            case .failure(let error):
                print("❌ Disk cache error for \(url): \(error.localizedDescription)")
                // Download and cache
                self.downloadAndCacheImage(from: url, completion: completion)
            }
        }
    }
    
    private func downloadAndCacheImage(from url: String, completion: @escaping (UIImage?) -> Void) {
        guard let imageURL = URL(string: url) else {
            print("❌ Invalid URL for download: \(url)")
            completion(nil)
            return
        }
        
        print("📥 Downloading image: \(url)")
        
        URLSession.shared.dataTask(with: imageURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Download error for \(url): \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let data = data, let image = UIImage(data: data) else {
                    print("❌ Failed to create image from data for \(url)")
                    completion(nil)
                    return
                }
                
                print("✅ Image downloaded successfully: \(url), size: \(data.count) bytes")
                
                // Add to memory cache
                self?.imageCache[url] = image
                
                // Add to disk cache
                ImageCache.default.store(image, forKey: url)
                
                completion(image)
            }
        }.resume()
    }
    
    // MARK: - Enhanced Real-time Updates
    private func setupOptimizedRealTimeListener() {
        // Use more granular listeners for better performance
        listener = db.collection("posts")
            .whereField("isReported", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 12) // OPTIMIZED: Reduced from 25 to 12 for better performance
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error in optimized real-time listener: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("⚠️ No documents found in optimized real-time snapshot")
                        return
                    }
                    
                    print("🔄 Optimized real-time update: \(documents.count) posts")
                    
                    guard let self = self else { return }
                    
                    // Process changes more efficiently
                    self.processOptimizedRealTimeChanges(documents: documents)
                }
            }
    }
    
    private func processOptimizedRealTimeChanges(documents: [QueryDocumentSnapshot]) {
        // Parse posts efficiently
        let allPosts = documents.compactMap { doc -> CommunityPost? in
            do {
                return try doc.data(as: CommunityPost.self)
            } catch {
                print("❌ Failed to parse post \(doc.documentID): \(error)")
                return nil
            }
        }
        
        guard !allPosts.isEmpty else {
            print("⚠️ No posts to update")
            return
        }
        
        // Separate pinned and regular posts
        let newPinnedPosts = allPosts.filter { $0.isPinned }
        let newRegularPosts = allPosts.filter { !$0.isPinned }
        
        // Sort efficiently
        let sortedPinnedPosts = newPinnedPosts.sorted { $0.createdAt > $1.createdAt }
        let sortedRegularPosts = newRegularPosts.sorted { $0.createdAt > $1.createdAt }
        
        // Update pinned posts
        pinnedPosts = sortedPinnedPosts
        
        // Smart regular posts update
        if regularPosts.count <= postsPerPage {
            regularPosts = Array(sortedRegularPosts.prefix(postsPerPage))
            hasMorePosts = sortedRegularPosts.count > postsPerPage
        } else {
            hasMorePosts = sortedRegularPosts.count > regularPosts.count
        }
        
        // Efficient UI update
        let combinedPosts = sortedPinnedPosts + regularPosts
        let currentPostIds = Set(posts.map { $0.id })
        let newPostIds = Set(combinedPosts.map { $0.id })
        
        // Only update if there are actual changes
        if currentPostIds != newPostIds {
            posts = combinedPosts
            print("✅ Optimized posts update: \(posts.count) total posts")
        } else {
            print("🔄 No changes detected, skipping update")
        }
    }
    
    // MARK: - Database Query Optimization
    private func fetchOptimizedPosts() {
        // Single optimized query instead of multiple queries
        let query = db.collection("posts")
            .whereField("isReported", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: postsPerPage * 2) // Load more initially for better UX
        
        query.getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching optimized posts: \(error.localizedDescription)")
                    self?.loadingState = .error(error.localizedDescription)
                    return
                }
                
                let allPosts = snapshot?.documents.compactMap { doc -> CommunityPost? in
                    do {
                        return try doc.data(as: CommunityPost.self)
                    } catch {
                        print("❌ Failed to parse post \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                
                // Separate and sort posts
                let pinnedPosts = allPosts.filter { $0.isPinned }.sorted { $0.createdAt > $1.createdAt }
                let regularPosts = allPosts.filter { !$0.isPinned }.sorted { $0.createdAt > $1.createdAt }
                
                self?.pinnedPosts = pinnedPosts
                self?.regularPosts = regularPosts
                self?.posts = pinnedPosts + Array(regularPosts.prefix(self?.postsPerPage ?? 12))
                self?.hasMorePosts = regularPosts.count > (self?.postsPerPage ?? 12)
                self?.loadingState = .loaded
                
                print("🎯 Optimized posts loaded: \(self?.posts.count ?? 0) total posts")
            }
        }
    }
    
    private func setupPerformanceMonitoring() {
        // OPTIMIZED: Reduced frequency for lower energy usage
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    private func updatePerformanceMetrics() {
        // Calculate memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            performanceMetrics.memoryUsage = Int64(info.resident_size)
        }
        
        // Calculate cache hit rate
        let totalCacheAccess = performanceMetrics.totalRequests
        let cacheHits = performanceMetrics.successfulRequests
        performanceMetrics.cacheHitRate = totalCacheAccess > 0 ? Double(cacheHits) / Double(totalCacheAccess) : 0
        
        print("📊 Performance Metrics:")
        print("   Memory Usage: \(performanceMetrics.memoryUsage / 1024 / 1024) MB")
        print("   Cache Hit Rate: \(String(format: "%.2f", performanceMetrics.cacheHitRate * 100))%")
        print("   Posts Load Time: \(String(format: "%.3f", performanceMetrics.postsLoadTime))s")
        print("   Image Load Time: \(String(format: "%.3f", performanceMetrics.imageLoadTime))s")
        print("   Comment Load Time: \(String(format: "%.3f", performanceMetrics.commentLoadTime))s")
    }
    
    private func trackRequest<T>(_ operation: String, completion: @escaping (T) -> Void) -> (T) -> Void {
        let startTime = Date()
        performanceMetrics.totalRequests += 1
        
        return { result in
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            DispatchQueue.main.async {
                self.performanceMetrics.successfulRequests += 1
                
                switch operation {
                case "posts":
                    self.performanceMetrics.postsLoadTime = duration
                case "images":
                    self.performanceMetrics.imageLoadTime = duration
                case "comments":
                    self.performanceMetrics.commentLoadTime = duration
                default:
                    break
                }
            }
            
            completion(result)
        }
    }
    
    // MARK: - Advanced Admin Functions for Large User Loads
    
    // Bulk user operations for scalability
    func fetchUsersWithPagination(limit: Int = 50, lastDocument: DocumentSnapshot? = nil, completion: @escaping ([UserProfile], DocumentSnapshot?, Bool) -> Void) {
        var query = db.collection("users").order(by: "createdAt", descending: true).limit(to: limit)
        
        if let lastDocument = lastDocument {
            query = query.start(afterDocument: lastDocument)
        }
        
        query.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error fetching users: \(error.localizedDescription)")
                completion([], nil, false)
                return
            }
            
            let users = snapshot?.documents.compactMap { doc -> UserProfile? in
                try? doc.data(as: UserProfile.self)
            } ?? []
            
            let lastDoc = snapshot?.documents.last
            let hasMore = snapshot?.documents.count == limit
            
            completion(users, lastDoc, hasMore)
        }
    }
    
    // Bulk user verification for efficiency
    func bulkVerifyUsers(userIds: [String], completion: @escaping (Bool, [String]) -> Void) {
        let batch = db.batch()
        var successIds: [String] = []
        
        for userId in userIds {
            let userRef = db.collection("users").document(userId)
            batch.updateData(["isVerified": true], forDocument: userRef)
            successIds.append(userId)
        }
        
        batch.commit { error in
            if let error = error {
                print("❌ Error bulk verifying users: \(error.localizedDescription)")
                completion(false, [])
            } else {
                print("✅ Successfully verified \(successIds.count) users")
                completion(true, successIds)
            }
        }
    }
    
    // Bulk user suspension for moderation
    func bulkSuspendUsers(userIds: [String], reason: String, duration: TimeInterval, completion: @escaping (Bool, [String]) -> Void) {
        let batch = db.batch()
        let suspensionEnd = Date().addingTimeInterval(duration)
        var successIds: [String] = []
        
        for userId in userIds {
            let userRef = db.collection("users").document(userId)
            batch.updateData([
                "isSuspended": true,
                "suspensionReason": reason,
                "suspensionEndDate": suspensionEnd,
                "suspendedAt": FieldValue.serverTimestamp()
            ], forDocument: userRef)
            successIds.append(userId)
        }
        
        batch.commit { error in
            if let error = error {
                print("❌ Error bulk suspending users: \(error.localizedDescription)")
                completion(false, [])
            } else {
                print("✅ Successfully suspended \(successIds.count) users")
                completion(true, successIds)
            }
        }
    }
    
    // Search users with pagination
    func searchUsers(query: String, limit: Int = 50, lastDocument: DocumentSnapshot? = nil, completion: @escaping ([UserProfile], DocumentSnapshot?, Bool) -> Void) {
        var userQuery = db.collection("users")
            .whereField("firstName", isGreaterThanOrEqualTo: query)
            .whereField("firstName", isLessThan: query + "\u{f8ff}")
            .limit(to: limit)
        
        if let lastDocument = lastDocument {
            userQuery = userQuery.start(afterDocument: lastDocument)
        }
        
        userQuery.getDocuments { snapshot, error in
            if let error = error {
                print("❌ Error searching users: \(error.localizedDescription)")
                completion([], nil, false)
                return
            }
            
            let users = snapshot?.documents.compactMap { doc -> UserProfile? in
                try? doc.data(as: UserProfile.self)
            } ?? []
            
            let lastDoc = snapshot?.documents.last
            let hasMore = snapshot?.documents.count == limit
            
            completion(users, lastDoc, hasMore)
        }
    }
    
    // Get user analytics for admin dashboard
    func fetchUserAnalytics(completion: @escaping (UserAnalytics) -> Void) {
        let analyticsRef = db.collection("analytics").document("users")
        
        analyticsRef.getDocument { snapshot, error in
            if let data = snapshot?.data() {
                let analytics = UserAnalytics(
                    totalUsers: data["totalUsers"] as? Int ?? 0,
                    activeUsers: data["activeUsers"] as? Int ?? 0,
                    verifiedUsers: data["verifiedUsers"] as? Int ?? 0,
                    suspendedUsers: data["suspendedUsers"] as? Int ?? 0,
                    newUsersToday: data["newUsersToday"] as? Int ?? 0,
                    newUsersThisWeek: data["newUsersThisWeek"] as? Int ?? 0
                )
                completion(analytics)
            } else {
                completion(UserAnalytics())
            }
        }
    }
    
    // Assign moderator role
    func assignModeratorRole(userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(userId).updateData([
            "isModerator": true,
            "moderatorAssignedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ Error assigning moderator role: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully assigned moderator role to user: \(userId)")
                completion(true)
            }
        }
    }
    
    // Remove moderator role
    func removeModeratorRole(userId: String, completion: @escaping (Bool) -> Void) {
        db.collection("users").document(userId).updateData([
            "isModerator": false,
            "moderatorRemovedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("❌ Error removing moderator role: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Successfully removed moderator role from user: \(userId)")
                completion(true)
            }
        }
    }
    
    // Get user activity for monitoring
    func fetchUserActivity(userId: String, limit: Int = 20, completion: @escaping ([UserActivity]) -> Void) {
        db.collection("users").document(userId).collection("activity")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching user activity: \(error.localizedDescription)")
                    completion([])
                    return
                }
                
                let activities = snapshot?.documents.compactMap { doc -> UserActivity? in
                    try? doc.data(as: UserActivity.self)
                } ?? []
                
                completion(activities)
            }
    }
    
    // Rate limiting for admin actions
    private var adminActionTimestamps: [String: Date] = [:]
    private let adminActionCooldown: TimeInterval = 1.0 // 1 second between actions
    
    func canPerformAdminAction(action: String) -> Bool {
        let now = Date()
        if let lastAction = adminActionTimestamps[action] {
            if now.timeIntervalSince(lastAction) < adminActionCooldown {
                return false
            }
        }
        adminActionTimestamps[action] = now
        return true
    }
    
    // MARK: - Fetch Post by ID for Admin Dashboard
    func fetchPostById(postId: String, completion: @escaping (CommunityPost?, String?) -> Void) {
        db.collection("posts").document(postId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching post by ID: \(error.localizedDescription)")
                completion(nil, error.localizedDescription)
                return
            }
            
            guard let document = snapshot, document.exists else {
                print("❌ Post not found: \(postId)")
                completion(nil, "Post not found")
                return
            }
            
            do {
                let post = try document.data(as: CommunityPost.self)
                print("✅ Successfully fetched post: \(postId)")
                completion(post, nil)
            } catch {
                print("❌ Error parsing post: \(error.localizedDescription)")
                completion(nil, "Failed to parse post data")
            }
        }
    }
    
    // MARK: - Delete All Posts by User (for Account Deletion)
    
    /// Deletes all posts created by a specific user when their account is deleted
    /// This method is called automatically when a user deletes their account or when an admin deletes a user
    func deleteAllPostsByUser(userId: String, completion: @escaping (Bool, Int, String?) -> Void) {
        let db = Firestore.firestore()
        print("🗑️ Starting deletion of all posts by user: \(userId)")
        
        // First, get all posts by this user
        db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error fetching posts by user \(userId): \(error.localizedDescription)")
                    completion(false, 0, error.localizedDescription)
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("✅ No posts found for user: \(userId)")
                    completion(true, 0, nil)
                    return
                }
                
                print("📝 Found \(documents.count) posts to delete for user: \(userId)")
                
                // Create a batch for efficient deletion
                let batch = db.batch()
                var deletedCount = 0
                let group = DispatchGroup()
                
                // Process each post
                for document in documents {
                    let postId = document.documentID
                    group.enter()
                    
                    // Delete media files first
                    self?.deletePostMediaFiles(postId: postId) {
                        // Add post deletion to batch
                        let postRef = db.collection("posts").document(postId)
                        batch.deleteDocument(postRef)
                        deletedCount += 1
                        group.leave()
                    }
                }
                
                // Commit the batch after all media files are deleted
                group.notify(queue: .main) {
                    batch.commit { error in
                        if let error = error {
                            print("❌ Error deleting posts batch for user \(userId): \(error.localizedDescription)")
                            completion(false, deletedCount, error.localizedDescription)
                        } else {
                            print("✅ Successfully deleted \(deletedCount) posts for user: \(userId)")
                            
                            // Refresh stats after deletion
                            self?.fetchTotalStats()
                            
                            completion(true, deletedCount, nil)
                        }
                    }
                }
            }
    }
    
    /// Deletes all comments/replies by a specific user when their account is deleted
    /// This method is called automatically when a user deletes their account or when an admin deletes a user
    func deleteAllCommentsByUser(userId: String, completion: @escaping (Bool, Int, String?) -> Void) {
        let db = Firestore.firestore()
        print("🗑️ Starting deletion of all comments by user: \(userId)")
        
        // Get all replies by this user across all posts
        db.collectionGroup("replies")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching comments by user \(userId): \(error.localizedDescription)")
                    completion(false, 0, error.localizedDescription)
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("✅ No comments found for user: \(userId)")
                    completion(true, 0, nil)
                    return
                }
                
                print("💬 Found \(documents.count) comments to delete for user: \(userId)")
                
                // Create a batch for efficient deletion
                let batch = db.batch()
                var deletedCount = 0
                
                // Process each comment
                for document in documents {
                    let commentRef = document.reference
                    batch.deleteDocument(commentRef)
                    deletedCount += 1
                }
                
                // Commit the batch
                batch.commit { error in
                    if let error = error {
                        print("❌ Error deleting comments batch for user \(userId): \(error.localizedDescription)")
                        completion(false, deletedCount, error.localizedDescription)
                    } else {
                        print("✅ Successfully deleted \(deletedCount) comments for user: \(userId)")
                        completion(true, deletedCount, nil)
                    }
                }
            }
    }
    
    /// Deletes all likes by a specific user when their account is deleted
    /// This method is called automatically when a user deletes their account or when an admin deletes a user
    func deleteAllLikesByUser(userId: String, completion: @escaping (Bool, Int, String?) -> Void) {
        let db = Firestore.firestore()
        print("🗑️ Starting deletion of all likes by user: \(userId)")
        
        // Get all likes by this user across all posts
        db.collectionGroup("likes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching likes by user \(userId): \(error.localizedDescription)")
                    completion(false, 0, error.localizedDescription)
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    print("✅ No likes found for user: \(userId)")
                    completion(true, 0, nil)
                    return
                }
                
                print("❤️ Found \(documents.count) likes to delete for user: \(userId)")
                
                // Create a batch for efficient deletion
                let batch = db.batch()
                var deletedCount = 0
                
                // Process each like
                for document in documents {
                    let likeRef = document.reference
                    batch.deleteDocument(likeRef)
                    deletedCount += 1
                }
                
                // Commit the batch
                batch.commit { error in
                    if let error = error {
                        print("❌ Error deleting likes batch for user \(userId): \(error.localizedDescription)")
                        completion(false, deletedCount, error.localizedDescription)
                    } else {
                        print("✅ Successfully deleted \(deletedCount) likes for user: \(userId)")
                        completion(true, deletedCount, nil)
                    }
                }
            }
    }
    
    /// Comprehensive method to delete all community content by a user
    /// This includes posts, comments, likes, and any other user-generated content
    /// Called automatically when a user deletes their account or when an admin deletes a user
    func deleteAllUserContent(userId: String, completion: @escaping (Bool, String?) -> Void) {
        print("🗑️ Starting comprehensive deletion of all content by user: \(userId)")
        
        let group = DispatchGroup()
        var hasErrors = false
        var errorMessages: [String] = []
        
        // Delete all posts by the user
        group.enter()
        deleteAllPostsByUser(userId: userId) { success, postCount, error in
            if !success {
                hasErrors = true
                if let error = error {
                    errorMessages.append("Posts: \(error)")
                }
            } else {
                print("✅ Deleted \(postCount) posts")
            }
            group.leave()
        }
        
        // Delete all comments by the user
        group.enter()
        deleteAllCommentsByUser(userId: userId) { success, commentCount, error in
            if !success {
                hasErrors = true
                if let error = error {
                    errorMessages.append("Comments: \(error)")
                }
            } else {
                print("✅ Deleted \(commentCount) comments")
            }
            group.leave()
        }
        
        // Delete all likes by the user
        group.enter()
        deleteAllLikesByUser(userId: userId) { success, likeCount, error in
            if !success {
                hasErrors = true
                if let error = error {
                    errorMessages.append("Likes: \(error)")
                }
            } else {
                print("✅ Deleted \(likeCount) likes")
            }
            group.leave()
        }
        
        // Wait for all operations to complete
        group.notify(queue: .main) {
            if hasErrors {
                let errorMessage = errorMessages.joined(separator: "; ")
                print("❌ Some errors occurred during user content deletion: \(errorMessage)")
                completion(false, errorMessage)
            } else {
                print("✅ Successfully deleted all content for user: \(userId)")
                completion(true, nil)
            }
        }
    }
    
    // MARK: - Dumpling Hero Post Generation
    
    /// Generates a Dumpling Hero post using AI
    /// Only available to admin users
    func generateDumplingHeroPost(prompt: String? = nil, completion: @escaping (Bool, DumplingHeroPost?, String?) -> Void) {
        guard isAdmin else {
            completion(false, nil, "Only admins can generate Dumpling Hero posts")
            return
        }
        
        print("🤖 Generating Dumpling Hero post...")
        
        // Get the base URL from Config
        let baseURL = Config.backendURL
        
        // Prepare the request body
        var requestBody: [String: Any] = [:]
        if let prompt = prompt, !prompt.isEmpty {
            requestBody["prompt"] = prompt
        }
        
        // Add menu items if available
        if let menuItems = getMenuItemsForHero() {
            requestBody["menuItems"] = menuItems
        }
        
        // Create the request
        guard let url = URL(string: "\(baseURL)/generate-dumpling-hero-post") else {
            completion(false, nil, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(false, nil, "Failed to serialize request: \(error.localizedDescription)")
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error: \(error.localizedDescription)")
                    completion(false, nil, "Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    completion(false, nil, "No data received")
                    return
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    
                    if let success = json?["success"] as? Bool, success {
                        if let postData = json?["post"] as? [String: Any] {
                            let dumplingHeroPost = DumplingHeroPost(from: postData)
                            print("✅ Generated Dumpling Hero post successfully")
                            completion(true, dumplingHeroPost, nil)
                        } else {
                            completion(false, nil, "Invalid post data format")
                        }
                    } else {
                        let errorMessage = json?["error"] as? String ?? "Unknown error"
                        print("❌ API error: \(errorMessage)")
                        completion(false, nil, errorMessage)
                    }
                } catch {
                    print("❌ JSON parsing error: \(error.localizedDescription)")
                    completion(false, nil, "Failed to parse response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    /// Helper method to get menu items for Dumpling Hero posts
    private func getMenuItemsForHero() -> [[String: Any]]? {
        // This would ideally fetch from your menu data
        // For now, return a simplified version
        return [
            ["id": "curry-chicken", "description": "Curry Chicken Dumplings", "price": 12.99],
            ["id": "spicy-pork", "description": "Spicy Pork Dumplings", "price": 14.99],
            ["id": "pork-cabbage", "description": "Pork & Cabbage Dumplings", "price": 14.99],
            ["id": "thai-brown-sugar", "description": "Capped Thai Brown Sugar Milk Tea", "price": 6.90],
            ["id": "peach-strawberry", "description": "Peach Strawberry Fruit Tea", "price": 6.75]
        ]
    }
    
    /// Submits a Dumpling Hero post to the community
    /// Only available to admin users
    func submitDumplingHeroPost(_ heroPost: DumplingHeroPost, completion: @escaping (Bool, String?) -> Void) {
        guard isAdmin else {
            completion(false, "Only admins can submit Dumpling Hero posts")
            return
        }
        
        print("📝 Submitting Dumpling Hero post...")
        
        let db = Firestore.firestore()
        let postRef = db.collection("posts").document()
        
        // Create the post content
        var contentType = "text"
        var content = heroPost.postText
        var pollOptions: [String]? = nil
        
        // If there's a poll, create poll content
        if let poll = heroPost.suggestedPoll {
            contentType = "poll"
            content = heroPost.postText
            pollOptions = poll.options
        }
        
        // Create post data with Dumpling Hero author info
        var postData: [String: Any] = [
            "id": postRef.documentID,
            "content": content,
            "contentType": contentType,
            "authorId": "dumpling-hero", // Special ID for Dumpling Hero
            "authorName": "Dumpling Hero",
            "authorFirstName": "Dumpling Hero",
            "authorProfilePhotoURL": "hero.png", // Use hero.png as profile picture
            "authorAvatarEmoji": "🥟",
            "authorAvatarColorName": "gold",
            "authorIsVerified": false,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "likeCount": 0,
            "commentCount": 0,
            "shareCount": 0,
            "isPinned": false,
            "isReported": false, // FIXED: Set isReported to false so posts show in feed
            "isDumplingHeroPost": true, // Special flag to identify Dumpling Hero posts
            "reactions": [:],
            "imageURLs": [],
            "videoURL": "",
            "postType": contentType,
            "location": "",
            "mentionedUsers": [],
            "hashtags": [],
            "caption": "",
            "pollVotes": [:]
        ]
        
        // Add poll if present
        if let poll = heroPost.suggestedPoll {
            let pollData: [String: Any] = [
                "id": UUID().uuidString,
                "question": poll.question,
                "options": poll.options.enumerated().map { index, text in
                    [
                        "id": UUID().uuidString,
                        "text": text,
                        "voteCount": 0,
                        "voters": []
                    ]
                },
                "allowMultiple": false,
                "expiresAt": "",
                "totalVotes": 0,
                "createdAt": FieldValue.serverTimestamp(),
                "isActive": true
            ]
            postData["poll"] = pollData
        }
        
        // Add attached menu item if present
        if let menuItem = heroPost.suggestedMenuItem {
            postData["attachedMenuItem"] = [
                "id": menuItem.id,
                "description": menuItem.description,
                "price": menuItem.price,
                "imageURL": menuItem.imageURL,
                "isAvailable": menuItem.isAvailable,
                "paymentLinkID": menuItem.paymentLinkID,
                "isDumpling": menuItem.isDumpling,
                "isDrink": menuItem.isDrink
            ]
        }
        
        // Submit the post
        postRef.setData(postData) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error submitting Dumpling Hero post: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                } else {
                    print("✅ Dumpling Hero post submitted successfully")
                    
                    // Refresh posts to show the new post
                    self.refreshPosts()
                    
                    completion(true, nil)
                }
            }
        }
    }
    
    /// Submits a Dumpling Hero comment to a post
    /// Only available to admin users
    func submitDumplingHeroComment(to postId: String, replyingTo: String? = nil, prompt: String? = nil, customComment: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard isAdmin else {
            completion(false, "Only admins can submit Dumpling Hero comments")
            return
        }
        
        print("💬 Submitting Dumpling Hero comment...")
        
        // Get the post context from the current posts
        let postContext = posts.first { $0.id == postId }
        
        // Debug logging for post context
        print("🔍 Looking for post with ID: \(postId)")
        print("📋 Total posts available: \(posts.count)")
        if let foundPost = postContext {
            print("✅ Found post context:")
            print("   - Content: \(foundPost.content)")
            print("   - Author: \(foundPost.authorName)")
            print("   - Type: \(foundPost.postType.rawValue)")
            print("   - Images: \(foundPost.imageURLs.count)")
            print("   - Has Menu Item: \(foundPost.attachedMenuItem != nil)")
            print("   - Has Poll: \(foundPost.poll != nil)")
        } else {
            print("❌ No post context found for ID: \(postId)")
        }
        
        // If we have a custom comment, use it directly
        if let customComment = customComment {
            createDumplingHeroComment(to: postId, content: customComment, replyingTo: replyingTo, completion: completion)
            return
        }
        
        // Generate the comment content using the backend
        generateDumplingHeroComment(prompt: prompt, postContext: postContext) { [weak self] result in
            switch result {
            case .success(let commentText):
                self?.createDumplingHeroComment(to: postId, content: commentText, replyingTo: replyingTo, completion: completion)
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }
    
    /// Generates a preview of a Dumpling Hero comment using the backend API
    func generateDumplingHeroCommentPreview(prompt: String?, postId: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Get the post context from the current posts
        let postContext = posts.first { $0.id == postId }
        
        // Debug logging for post context
        print("🔍 Looking for post with ID: \(postId)")
        print("📋 Total posts available: \(posts.count)")
        if let foundPost = postContext {
            print("✅ Found post context:")
            print("   - Content: \(foundPost.content)")
            print("   - Author: \(foundPost.authorName)")
            print("   - Type: \(foundPost.postType.rawValue)")
            print("   - Images: \(foundPost.imageURLs.count)")
            print("   - Has Menu Item: \(foundPost.attachedMenuItem != nil)")
            print("   - Has Poll: \(foundPost.poll != nil)")
        } else {
            print("❌ No post context found for ID: \(postId)")
        }
        
        // Generate the comment content using the preview endpoint
        generateDumplingHeroCommentPreview(prompt: prompt, postContext: postContext, completion: completion)
    }
    
    /// Generates a preview of a Dumpling Hero comment using the preview endpoint
    private func generateDumplingHeroCommentPreview(prompt: String?, postContext: CommunityPost?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(Config.backendURL)/preview-dumpling-hero-comment") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build post context data
        var postContextData: [String: Any] = [:]
        if let post = postContext {
            postContextData = [
                "content": post.content,
                "imageURLs": post.imageURLs,
                "videoURL": post.videoURL ?? "",
                "postType": post.postType.rawValue,
                "caption": post.caption ?? "",
                "hashtags": post.hashtags,
                "authorName": post.authorName
            ]
            
            // Add attached menu item if present
            if let menuItem = post.attachedMenuItem {
                postContextData["attachedMenuItem"] = [
                    "id": menuItem.id,
                    "description": menuItem.description,
                    "price": menuItem.price,
                    "imageURL": menuItem.imageURL,
                    "category": menuItem.category,
                    "isDumpling": menuItem.isDumpling,
                    "isDrink": menuItem.isDrink
                ]
            }
            
            // Add poll data if present
            if let poll = post.poll {
                postContextData["poll"] = [
                    "question": poll.question,
                    "options": poll.options.map { option in
                        [
                            "text": option.text,
                            "voteCount": option.voteCount
                        ]
                    },
                    "totalVotes": poll.totalVotes
                ]
            }
        }
        
        let body: [String: Any] = [
            "prompt": prompt ?? "",
            "postContext": postContextData
        ]
        
        // Debug logging
        print("🤖 Sending Dumpling Hero comment preview request:")
        print("📝 Prompt: \(prompt ?? "None")")
        print("📊 Post Context: \(postContextData)")
        print("📦 Full Request Body: \(body)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("❌ Failed to serialize request body: \(error)")
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "No data received", code: -1, userInfo: nil)))
                    return
                }
                
                do {
                    // Debug: Print the raw response data
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📥 Raw preview response data: \(responseString)")
                    }
                    
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    print("📥 Parsed preview JSON response: \(json ?? [:])")
                    
                    // Handle preview endpoint format (success + comment object)
                    if let json = json,
                       let success = json["success"] as? Bool, success,
                       let commentData = json["comment"] as? [String: Any],
                       let commentText = commentData["commentText"] as? String {
                        print("✅ Successfully parsed preview comment: \(commentText)")
                        completion(.success(commentText))
                    } else {
                        print("❌ Invalid preview response format: \(json ?? [:])")
                        completion(.failure(NSError(domain: "Invalid response format", code: -1, userInfo: nil)))
                    }
                } catch {
                    print("❌ JSON parsing error: \(error)")
                    print("❌ Error details: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Generates a Dumpling Hero comment using the backend API
    private func generateDumplingHeroComment(prompt: String?, postContext: CommunityPost?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(Config.backendURL)/generate-dumpling-hero-comment-simple") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build post context data
        var postContextData: [String: Any] = [:]
        if let post = postContext {
            postContextData = [
                "content": post.content,
                "imageURLs": post.imageURLs,
                "videoURL": post.videoURL ?? "",
                "postType": post.postType.rawValue,
                "caption": post.caption ?? "",
                "hashtags": post.hashtags,
                "authorName": post.authorName
            ]
            
            // Add attached menu item if present
            if let menuItem = post.attachedMenuItem {
                postContextData["attachedMenuItem"] = [
                    "id": menuItem.id,
                    "description": menuItem.description,
                    "price": menuItem.price,
                    "imageURL": menuItem.imageURL,
                    "category": menuItem.category,
                    "isDumpling": menuItem.isDumpling,
                    "isDrink": menuItem.isDrink
                ]
            }
            
            // Add poll data if present
            if let poll = post.poll {
                postContextData["poll"] = [
                    "question": poll.question,
                    "options": poll.options.map { option in
                        [
                            "text": option.text,
                            "voteCount": option.voteCount
                        ]
                    },
                    "totalVotes": poll.totalVotes
                ]
            }
        }
        
        let body: [String: Any] = [
            "prompt": prompt ?? "",
            "postContext": postContextData
        ]
        
        // Debug logging
        print("🤖 Sending Dumpling Hero comment request:")
        print("📝 Prompt: \(prompt ?? "None")")
        print("📊 Post Context: \(postContextData)")
        print("📦 Full Request Body: \(body)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("❌ Failed to serialize request body: \(error)")
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 HTTP Status Code: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        print("❌ HTTP Error: \(httpResponse.statusCode)")
                        let errorMessage = "Server returned HTTP \(httpResponse.statusCode)"
                        completion(.failure(NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                        return
                    }
                }
                
                guard let data = data else {
                    print("❌ No data received from server")
                    completion(.failure(NSError(domain: "No data received", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                    return
                }
                
                do {
                    // Debug: Print the raw response data
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📥 Raw response data: \(responseString)")
                        
                        // Check if response is HTML (error page)
                        if responseString.contains("<html") || responseString.contains("<!DOCTYPE") {
                            print("❌ Received HTML error page instead of JSON")
                            completion(.failure(NSError(domain: "Server returned HTML error page", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server returned HTML error page. This usually means the endpoint doesn't exist or there's a server error."])))
                            return
                        }
                    }
                    
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    print("📥 Parsed JSON response: \(json ?? [:])")
                    
                    // Handle simple endpoint format (direct commentText)
                    if let json = json,
                       let commentText = json["commentText"] as? String {
                        print("✅ Successfully parsed comment: \(commentText)")
                        completion(.success(commentText))
                    }
                    // Handle legacy format (success + comment object)
                    else if let json = json,
                              let success = json["success"] as? Bool, success,
                              let commentData = json["comment"] as? [String: Any],
                              let commentText = commentData["commentText"] as? String {
                        print("✅ Successfully parsed comment (legacy format): \(commentText)")
                        completion(.success(commentText))
                    } else {
                        print("❌ Invalid response format: \(json ?? [:])")
                        completion(.failure(NSError(domain: "Invalid response format", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server returned invalid JSON format"])))
                    }
                } catch {
                    print("❌ JSON parsing error: \(error)")
                    print("❌ Error details: \(error.localizedDescription)")
                    
                    // Check if the error is due to HTML response
                    if let responseString = String(data: data, encoding: .utf8),
                       (responseString.contains("<html") || responseString.contains("<!DOCTYPE")) {
                        completion(.failure(NSError(domain: "Server returned HTML error page", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server returned HTML error page. This usually means the endpoint doesn't exist or there's a server error."])))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }
    
    /// Creates the actual Dumpling Hero comment in Firestore
    private func createDumplingHeroComment(to postId: String, content: String, replyingTo: String?, completion: @escaping (Bool, String?) -> Void) {
        let db = Firestore.firestore()
        let replyId = UUID().uuidString
        
        // Create Dumpling Hero comment data
        let replyData: [String: Any] = [
            "id": replyId,
            "userId": "dumpling-hero", // Special ID for Dumpling Hero
            "userFirstName": "Dumpling Hero",
            "userProfilePhotoURL": "hero.png", // Use hero.png as profile picture
            "avatarEmoji": "🥟",
            "avatarColorName": "gold",
            "isVerified": false,
            "content": content,
            "createdAt": FieldValue.serverTimestamp(),
            "replyingToId": replyingTo as Any,
            "likeCount": 0,
            "isDumplingHeroComment": true // Special flag to identify Dumpling Hero comments
        ]
        
        db.collection("posts").document(postId).collection("replies").document(replyId).setData(replyData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error submitting Dumpling Hero comment: \(error.localizedDescription)")
                        completion(false, error.localizedDescription)
                    } else {
                        print("✅ Dumpling Hero comment submitted successfully")
                        
                        // Increment replyCount
                        db.collection("posts").document(postId).updateData(["replyCount": FieldValue.increment(Int64(1))]) { _ in }
                        
                        completion(true, nil)
                    }
                }
            }

    }
}

// MARK: - Dumpling Hero Post Model
struct DumplingHeroPost {
    let postText: String
    let suggestedMenuItem: MenuItem?
    let suggestedPoll: DumplingHeroPoll?
    
    init(from json: [String: Any]) {
        self.postText = json["postText"] as? String ?? ""
        
        // Parse suggested menu item
        if let menuItemData = json["suggestedMenuItem"] as? [String: Any] {
            self.suggestedMenuItem = MenuItem(
                id: menuItemData["id"] as? String ?? "",
                description: menuItemData["description"] as? String ?? "",
                price: menuItemData["price"] as? Double ?? 0.0,
                imageURL: menuItemData["imageURL"] as? String ?? "",
                isAvailable: menuItemData["isAvailable"] as? Bool ?? true,
                paymentLinkID: menuItemData["paymentLinkID"] as? String ?? "",
                isDumpling: menuItemData["isDumpling"] as? Bool ?? false,
                isDrink: menuItemData["isDrink"] as? Bool ?? false,
                iceLevelEnabled: menuItemData["iceLevelEnabled"] as? Bool ?? false,
                sugarLevelEnabled: menuItemData["sugarLevelEnabled"] as? Bool ?? false,
                toppingModifiersEnabled: menuItemData["toppingModifiersEnabled"] as? Bool ?? false,
                milkSubModifiersEnabled: menuItemData["milkSubModifiersEnabled"] as? Bool ?? false,
                availableToppingIDs: menuItemData["availableToppingIDs"] as? [String] ?? [],
                availableMilkSubIDs: menuItemData["availableMilkSubIDs"] as? [String] ?? [],
                category: menuItemData["category"] as? String ?? ""
            )
        } else {
            self.suggestedMenuItem = nil
        }
        
        // Parse suggested poll
        if let pollData = json["suggestedPoll"] as? [String: Any] {
            self.suggestedPoll = DumplingHeroPoll(
                question: pollData["question"] as? String ?? "",
                options: pollData["options"] as? [String] ?? []
            )
        } else {
            self.suggestedPoll = nil
        }
    }
}

struct DumplingHeroPoll {
    let question: String
    let options: [String]
}