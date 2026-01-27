import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Crowd Meter Data Models

struct CrowdLevel: Codable, Identifiable {
    let id: String
    let hour: Int // 0-23
    let dayOfWeek: Int // 0-6 (Sunday = 0)
    let level: Int // 1-5 (1 = Not Busy, 5 = Very Busy)
    let lastUpdated: Date
    let updatedBy: String // User ID who updated it
    
    enum CodingKeys: String, CodingKey {
        case id
        case hour
        case dayOfWeek
        case level
        case lastUpdated
        case updatedBy
    }
}

struct CrowdMeterData: Codable {
    let currentLevel: Int
    let currentHour: Int
    let currentDay: Int
    let weeklyData: [CrowdLevel]
    let lastUpdated: Date
    
    var currentLevelDescription: String {
        switch currentLevel {
        case 1: return "Not Busy"
        case 2: return "A Little Busy"
        case 3: return "Moderately Busy"
        case 4: return "Busy"
        case 5: return "Very Busy"
        default: return "Unknown"
        }
    }
    
    var currentLevelColor: String {
        switch currentLevel {
        case 1: return "green"
        case 2: return "yellow"
        case 3: return "orange"
        case 4: return "red"
        case 5: return "darkred"
        default: return "gray"
        }
    }
}

// MARK: - Crowd Meter ViewModel

class CrowdMeterViewModel: ObservableObject {
    @Published var currentData: CrowdMeterData?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAdmin = false
    @Published var weeklyData: [CrowdLevel] = []
    
    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    init() {
        checkAdminStatus()
        loadCurrentData()
    }
    
    deinit {
        listenerRegistration?.remove()
    }
    
    // MARK: - Admin Status Check
    
    private func checkAdminStatus() {
        guard let user = Auth.auth().currentUser else {
            isAdmin = false
            return
        }
        
        db.collection("users").document(user.uid).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let data = snapshot?.data(), let adminStatus = data["isAdmin"] as? Bool {
                    self?.isAdmin = adminStatus
                } else {
                    self?.isAdmin = false
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    func loadCurrentData() {
        isLoading = true
        errorMessage = nil
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentDay = calendar.component(.weekday, from: now) - 1 // Convert to 0-6
        
        // Get current crowd level for this hour and day
        db.collection("crowdMeter")
            .whereField("hour", isEqualTo: currentHour)
            .whereField("dayOfWeek", isEqualTo: currentDay)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    
                    if let error = error {
                        self?.errorMessage = "Failed to load crowd data: \(error.localizedDescription)"
                        return
                    }
                    
                    let currentLevel: Int
                    let lastUpdated: Date
                    let updatedBy: String
                    
                    if let document = snapshot?.documents.first,
                       let data = document.data() as? [String: Any],
                       let level = data["level"] as? Int,
                       let timestamp = data["lastUpdated"] as? Timestamp,
                       let user = data["updatedBy"] as? String {
                        currentLevel = level
                        lastUpdated = timestamp.dateValue()
                        updatedBy = user
                    } else {
                        // Default values if no data exists
                        currentLevel = 3 // Moderately busy
                        lastUpdated = now
                        updatedBy = "system"
                    }
                    
                    // Create current data
                    let currentData = CrowdMeterData(
                        currentLevel: currentLevel,
                        currentHour: currentHour,
                        currentDay: currentDay,
                        weeklyData: [], // We'll load this separately if needed
                        lastUpdated: lastUpdated
                    )
                    
                    self?.currentData = currentData
                    
                    // Also load weekly data for admin functionality
                    self?.getWeeklyData { _ in }
                }
            }
    }
    
    // MARK: - Admin Functions
    
    func updateCrowdLevel(hour: Int, dayOfWeek: Int, level: Int, completion: @escaping (Bool) -> Void) {
        guard isAdmin, let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        let data: [String: Any] = [
            "hour": hour,
            "dayOfWeek": dayOfWeek,
            "level": level,
            "lastUpdated": Timestamp(date: Date()),
            "updatedBy": user.uid
        ]
        
        // Use a compound document ID for hour and day
        let documentId = "\(dayOfWeek)_\(hour)"
        
        db.collection("crowdMeter").document(documentId).setData(data) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Failed to update crowd level: \(error.localizedDescription)"
                    completion(false)
                } else {
                    // Update local cache
                    let newCrowdLevel = CrowdLevel(
                        id: documentId,
                        hour: hour,
                        dayOfWeek: dayOfWeek,
                        level: level,
                        lastUpdated: Date(),
                        updatedBy: user.uid
                    )
                    
                    // Remove existing entry if it exists
                    self?.weeklyData.removeAll { $0.hour == hour && $0.dayOfWeek == dayOfWeek }
                    
                    // Add new entry
                    self?.weeklyData.append(newCrowdLevel)
                    
                    // Force UI update by triggering objectWillChange
                    self?.objectWillChange.send()
                    
                    // Reload current data
                    self?.loadCurrentData()
                    completion(true)
                }
            }
        }
    }
    
    func getWeeklyData(completion: @escaping ([CrowdLevel]) -> Void) {
        // Load data for all users, not just admins (limited to 100 for performance)
        
        db.collection("crowdMeter").limit(to: 100).getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to load weekly data: \(error.localizedDescription)"
                    completion([])
                    return
                }
                
                let crowdLevels = snapshot?.documents.compactMap { document -> CrowdLevel? in
                    guard let data = document.data() as? [String: Any],
                          let hour = data["hour"] as? Int,
                          let dayOfWeek = data["dayOfWeek"] as? Int,
                          let level = data["level"] as? Int,
                          let timestamp = data["lastUpdated"] as? Timestamp,
                          let updatedBy = data["updatedBy"] as? String else {
                        return nil
                    }
                    
                    return CrowdLevel(
                        id: document.documentID,
                        hour: hour,
                        dayOfWeek: dayOfWeek,
                        level: level,
                        lastUpdated: timestamp.dateValue(),
                        updatedBy: updatedBy
                    )
                } ?? []
                
                // Update local cache
                self.weeklyData = crowdLevels
                
                completion(crowdLevels)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    func getDayName(_ day: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[day]
    }
    
    func getHourDisplay(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    func isCurrentHour(_ hour: Int, _ day: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentDay = calendar.component(.weekday, from: now) - 1
        return hour == currentHour && day == currentDay
    }
    
    func isCurrentTimeSlot(hour: Int, day: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentDay = calendar.component(.weekday, from: now) - 1
        
        // Check if it's the current day
        guard day == currentDay else { return false }
        
        // Special logic for 12:00 bar - lit from 11:30 to 12:59
        if hour == 12 {
            let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
            return currentTimeDecimal >= 11.5 && currentTimeDecimal < 13.0
        }
        
        // For all other hours, use the standard logic
        return hour == currentHour
    }
    
    // MARK: - Restaurant Hours Logic
    
    func isRestaurantOpen(hour: Double, day: Int) -> Bool {
        // Sunday-Thursday: 11:30 AM - 9:00 PM (11.5 - 21)
        // Friday-Saturday: 11:30 AM - 10:00 PM (11.5 - 22)
        
        let isWeekend = day == 5 || day == 6 // Friday = 5, Saturday = 6
        let closingHour = isWeekend ? 22.0 : 21.0
        
        // Convert 11:30 AM to 11.5 for comparison
        return hour >= 11.5 && hour < closingHour
    }
    
    func isCurrentlyOpen() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentDay = calendar.component(.weekday, from: now) - 1
        
        // Convert current time to decimal hours
        let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
        
        return isRestaurantOpen(hour: currentTimeDecimal, day: currentDay)
    }
    
    func getNextOpeningTime() -> String {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.weekday, from: now) - 1
        
        // If it's before 11:30 AM today, return "11:30 AM"
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
        
        if currentTimeDecimal < 11.5 {
            return "11:30 AM"
        }
        
        // Otherwise, return next day's opening time
        let nextDay = (currentDay + 1) % 7
        let nextDayName = getDayName(nextDay)
        return "\(nextDayName) at 11:30 AM"
    }
    
    func getTimeUntilOpening() -> (minutes: Int, message: String) {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.weekday, from: now) - 1
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
        
        // If it's before 11:30 AM today
        if currentTimeDecimal < 11.5 {
            let openingTime = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: now)!
            let timeInterval = openingTime.timeIntervalSince(now)
            let minutes = Int(timeInterval / 60)
            
            if minutes < 60 {
                return (minutes, "Opening in \(minutes) min")
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                if remainingMinutes == 0 {
                    return (minutes, "Opening in \(hours)h")
                } else {
                    return (minutes, "Opening in \(hours)h \(remainingMinutes)m")
                }
            }
        }
        
        // If it's after closing today, calculate for tomorrow
        let isWeekend = currentDay == 5 || currentDay == 6 // Friday = 5, Saturday = 6
        let closingHour = isWeekend ? 22.0 : 21.0
        
        if currentTimeDecimal >= closingHour {
            let nextDay = (currentDay + 1) % 7
            let nextDayName = getDayName(nextDay)
            
            // Calculate time until tomorrow's opening
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            let tomorrowOpening = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: tomorrow)!
            let timeInterval = tomorrowOpening.timeIntervalSince(now)
            let minutes = Int(timeInterval / 60)
            
            if minutes < 60 {
                return (minutes, "Closed until \(nextDayName) • Opens in \(minutes)m")
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                if remainingMinutes == 0 {
                    return (minutes, "Closed until \(nextDayName) • Opens in \(hours)h")
                } else {
                    return (minutes, "Closed until \(nextDayName) • Opens in \(hours)h \(remainingMinutes)m")
                }
            }
        }
        
        // Should not reach here if restaurant is closed
        return (0, "Opening soon")
    }
    
    func isBeforeOpeningToday() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
        return currentTimeDecimal < 11.5
    }
    
    func isAfterClosingToday() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.component(.weekday, from: now) - 1
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeDecimal = Double(currentHour) + Double(currentMinute) / 60.0
        
        let isWeekend = currentDay == 5 || currentDay == 6 // Friday = 5, Saturday = 6
        let closingHour = isWeekend ? 22.0 : 21.0
        
        return currentTimeDecimal >= closingHour
    }
    
    func getCrowdLevelForHour(_ hour: Int, day: Int) -> Int {
        // First check if we have stored data for this hour and day
        if let storedLevel = weeklyData.first(where: { $0.hour == hour && $0.dayOfWeek == day }) {
            return storedLevel.level
        }
        
        // If no stored data, return default pattern based on typical restaurant busyness
        switch hour {
        case 6...8: return 2   // Early morning - light
        case 9...11: return 3  // Late morning - moderate
        case 12...13: return 5 // Lunch rush - very busy
        case 14...16: return 2 // Afternoon - light
        case 17...19: return 4 // Dinner rush - busy
        case 20...22: return 3 // Evening - moderate
        default: return 1      // Late night/early morning - not busy
        }
    }
} 