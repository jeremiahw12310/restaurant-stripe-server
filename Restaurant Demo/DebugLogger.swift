import Foundation

// Lightweight debug logger with deduplication and rate limiting to prevent Xcode console overload.
enum DebugLogger {
    private static let queue = DispatchQueue(label: "debug.logger.queue")
    private static var lastLogTimestamps: [String: TimeInterval] = [:]
    private static var bucketCounts: [Int: Int] = [:]
    private static let bucketWindow: TimeInterval = 1.0 // seconds

    /// Logs message in DEBUG only, with simple dedupe and per-second throttling.
    static func debug(_ message: @autoclosure () -> String,
                      category: String = "General",
                      dedupeInterval: TimeInterval = 2.0,
                      maxPerSecond: Int = 20) {
        #if DEBUG
        let now = Date().timeIntervalSince1970
        let key = category + "::" + message()

        var shouldLog = true

        queue.sync {
            // Dedupe same message for dedupeInterval
            if let last = lastLogTimestamps[key], now - last < dedupeInterval {
                shouldLog = false
            }

            // Per-second simple bucket throttling
            let bucket = Int(now)
            let count = bucketCounts[bucket] ?? 0
            if count >= maxPerSecond {
                shouldLog = false
            } else {
                bucketCounts[bucket] = count + 1
                // Clean old buckets
                bucketCounts = bucketCounts.filter { abs($0.key - bucket) <= 1 }
            }

            if shouldLog {
                lastLogTimestamps[key] = now
            }
        }

        if shouldLog {
            Swift.print("[\(category)] \(message())")
        }
        #endif
    }
}


