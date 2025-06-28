//
//  StripeCheckoutManager.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/27/25.
//

import Foundation
import SwiftUI

// This class handles creating a Stripe Checkout session by talking to a test server.
@MainActor // Ensures that updates to published properties happen on the main thread.
class StripeCheckoutManager: ObservableObject {
    
    @Published var checkoutURL: URL?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // This is a public test server that creates a checkout session for us.
    private let backendUrl = "https://stripe-example-backend-server.glitch.me/create-checkout-session"

    /// This function contacts the server to create a secure checkout session.
    func createCheckoutSession(from cartItems: [CartItem]) async {
        self.isLoading = true
        self.errorMessage = nil
        self.checkoutURL = nil
        
        guard let url = URL(string: backendUrl) else {
            errorMessage = "Invalid backend URL"
            isLoading = false
            return
        }
        
        // Prepare the list of items in the format Stripe's API expects.
        let lineItems = cartItems.map { item -> [String: Any] in
            return [
                "price_data": [
                    "currency": "usd",
                    "product_data": [
                        "name": item.menuItem.id,
                    ],
                    "unit_amount": Int(item.menuItem.price * 100), // Price must be in cents
                ],
                "quantity": item.quantity,
            ]
        }
        
        let body: [String: Any] = ["line_items": lineItems]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            // Perform the network request asynchronously.
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["url"] as? String,
                  let url = URL(string: urlString) else {
                throw "Failed to decode response from backend."
            }
            
            // On success, update the URL.
            self.checkoutURL = url
            
        } catch {
            // On failure, update the error message.
            self.errorMessage = error.localizedDescription
            if let customError = error as? String {
                self.errorMessage = customError
            }
        }
        
        self.isLoading = false
    }
}

// A helper to make String throwable, so we can have custom error messages.
extension String: LocalizedError {
    public var errorDescription: String? { self }
}
