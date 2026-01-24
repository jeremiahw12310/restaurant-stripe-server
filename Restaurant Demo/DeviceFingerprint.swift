import Foundation
import UIKit

struct DeviceFingerprint {
    static func generate() -> [String: Any] {
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let platform = "iOS \(UIDevice.current.systemVersion)"
        let model = UIDevice.current.model
        let screenWidth = Int(UIScreen.main.bounds.width)
        let screenHeight = Int(UIScreen.main.bounds.height)
        let timezone = TimeZone.current.identifier
        
        return [
            "vendorId": vendorId,
            "platform": platform,
            "model": model,
            "screenWidth": screenWidth,
            "screenHeight": screenHeight,
            "timezone": timezone
        ]
    }
    
    static func addToRequest(_ request: inout URLRequest) {
        let fingerprint = generate()
        if let jsonData = try? JSONSerialization.data(withJSONObject: fingerprint),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            request.setValue(jsonString, forHTTPHeaderField: "X-Device-Fingerprint")
        }
    }
}
