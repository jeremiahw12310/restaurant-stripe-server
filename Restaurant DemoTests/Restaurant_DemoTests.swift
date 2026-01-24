//
//  Restaurant_DemoTests.swift
//  Restaurant DemoTests
//
//  Created by Jeremiah Wiseman on 6/18/25.
//

import Testing
import Foundation
@testable import Restaurant_Demo

struct Restaurant_DemoTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testWelcomePopupLogic() async throws {
        // Test that the welcome popup notification name is defined
        let notificationName = Notification.Name.showWelcomePopup
        #expect(notificationName.rawValue == "showWelcomePopup")
        
        // Test that UserViewModel has isNewUser property
        let userVM = UserViewModel()
        #expect(userVM.isNewUser == false) // Should default to false
        
        // Test that the notification name extension is properly defined
        #expect(Notification.Name.showWelcomePopup.rawValue == "showWelcomePopup")
    }

}
