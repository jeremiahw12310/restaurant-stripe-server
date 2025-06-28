//
//  StripeCheckoutManager.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/27/25.
//

import Foundation
import SwiftUI

// This class handles creating a Stripe Checkout session using a local server.
@MainActor // Ensures that updates to published properties happen on the main thread.
class StripeCheckoutManager: ObservableObject {
    
    @Published var checkoutURL: URL?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var paymentSuccess = false
    
    // Local server URL - make sure to start the server first!
    private let backendUrl = "https://restaurant-stripe-server.onrender.com/create-checkout-session"

    /// This function contacts the local server to create a secure checkout session.
    func createCheckoutSession(from cartItems: [CartItem]) async {
        self.isLoading = true
        self.errorMessage = nil
        self.checkoutURL = nil
        self.paymentSuccess = false
        
        print("🛒 Starting checkout process with \(cartItems.count) items")
        
        // Check if cart is empty
        guard !cartItems.isEmpty else {
            self.errorMessage = "Cart is empty"
            self.isLoading = false
            return
        }
        
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
        
        print("📦 Prepared data for server: \(body)")
        
        do {
            print("🚀 Calling local server...")
            // Perform the network request asynchronously.
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("✅ Server response received")
            print("📡 Response status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            print("📄 Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            
            // Check if we got a valid HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    throw "Server returned status code \(httpResponse.statusCode). Make sure the local server is running!"
                }
            }
            
            // Try to parse the JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["url"] as? String,
                  let url = URL(string: urlString) else {
                throw "Failed to decode response from backend. Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")"
            }
            
            print("🔗 Checkout URL created: \(url)")
            
            // On success, update the URL.
            self.checkoutURL = url
            
        } catch {
            print("❌ Error during checkout: \(error)")
            // On failure, update the error message.
            self.errorMessage = error.localizedDescription
            if let customError = error as? String {
                self.errorMessage = customError
            }
        }
        
        self.isLoading = false
    }
    
    /// Handle successful payment completion
    func handlePaymentSuccess() {
        self.paymentSuccess = true
        self.checkoutURL = nil
        // You can add additional logic here like clearing the cart
    }
    
    /// Handle payment cancellation
    func handlePaymentCancellation() {
        self.checkoutURL = nil
        self.errorMessage = nil
    }
    
    /// Create checkout session with line items (for tip selection)
    func createCheckoutSession(lineItems: [[String: Any]]) async {
        self.isLoading = true
        self.errorMessage = nil
        self.checkoutURL = nil
        self.paymentSuccess = false
        
        print("🛒 Starting checkout process with \(lineItems.count) line items")
        
        // Check if line items are empty
        guard !lineItems.isEmpty else {
            self.errorMessage = "No items to checkout"
            self.isLoading = false
            return
        }
        
        guard let url = URL(string: backendUrl) else {
            errorMessage = "Invalid backend URL"
            isLoading = false
            return
        }
        
        let body: [String: Any] = ["line_items": lineItems]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("📦 Prepared data for server: \(body)")
        
        do {
            print("🚀 Calling local server...")
            // Perform the network request asynchronously.
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("✅ Server response received")
            print("📡 Response status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            print("📄 Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            
            // Check if we got a valid HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    throw "Server returned status code \(httpResponse.statusCode). Make sure the local server is running!"
                }
            }
            
            // Try to parse the JSON response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlString = json["url"] as? String,
                  let url = URL(string: urlString) else {
                throw "Failed to decode response from backend. Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")"
            }
            
            print("🔗 Checkout URL created: \(url)")
            
            // On success, update the URL.
            self.checkoutURL = url
            
        } catch {
            print("❌ Error during checkout: \(error)")
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
