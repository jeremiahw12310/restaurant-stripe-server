import Foundation

struct UserProfile: Identifiable, Codable {
    var id: String
    var firstName: String
    var lastName: String
    var email: String
    var avatarEmoji: String?
    var avatarColorName: String?
    var profilePhotoURL: String?
    var lastActive: Date = Date() // Default to now
    var isVerified: Bool = false // Default to false
    var isModerator: Bool = false // Admin role
    var isSuspended: Bool = false // Suspension status
    var suspensionReason: String? // Reason for suspension
    var suspensionEndDate: Date? // When suspension ends
    var suspendedAt: Date? // When suspension started
    var moderatorAssignedAt: Date? // When moderator role was assigned
    var createdAt: Date = Date() // When user was created
    // Add other properties as needed
}

// MARK: - Admin Analytics Models

struct UserAnalytics: Codable {
    let totalUsers: Int
    let activeUsers: Int
    let verifiedUsers: Int
    let suspendedUsers: Int
    let newUsersToday: Int
    let newUsersThisWeek: Int
    
    init(totalUsers: Int = 0, activeUsers: Int = 0, verifiedUsers: Int = 0, suspendedUsers: Int = 0, newUsersToday: Int = 0, newUsersThisWeek: Int = 0) {
        self.totalUsers = totalUsers
        self.activeUsers = activeUsers
        self.verifiedUsers = verifiedUsers
        self.suspendedUsers = suspendedUsers
        self.newUsersToday = newUsersToday
        self.newUsersThisWeek = newUsersThisWeek
    }
}

struct UserActivity: Codable, Identifiable {
    let id: String
    let userId: String
    let activityType: String // "post_created", "comment_added", "like_given", etc.
    let description: String
    let timestamp: Date
    let metadata: [String: String]?
    
    init(id: String = UUID().uuidString, userId: String, activityType: String, description: String, timestamp: Date = Date(), metadata: [String: String]? = nil) {
        self.id = id
        self.userId = userId
        self.activityType = activityType
        self.description = description
        self.timestamp = timestamp
        self.metadata = metadata
    }
} 