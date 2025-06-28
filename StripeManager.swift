import Foundation
import Stripe
import StripePaymentSheet
import FirebaseFunctions

class StripeManager: ObservableObject {
    @Published var paymentSheet: PaymentSheet?
    @Published var paymentResult: PaymentSheetResult?
    
    // ✅ FIX: We are now explicitly telling the app which region your function is in.
    // Replace "your-region-here" with the value you copied from the Google Cloud website.
    private lazy var functions = Functions.functions(region: "us-central1") // <-- PASTE YOUR REGION HERE

    init() {
        StripeAPI.defaultPublishableKey = "pk_test_51RelK3H2xFvy1B3DgTw6MRYnoTQ5xAG3ZV6vf0C8BvNKPcKDbe1I5FUIfrKPpFZTTKH1yC2YnzrZRFgZORE4yYbE00j21uLHKk"
    }

    func preparePaymentSheet(amount: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async {
            self.paymentSheet = nil
        }
        
        let amountInCents = Int(amount * 100)
        
        // This call will now be made to the correct region.
        functions.httpsCallable("createPaymentIntent").call(["amount": amountInCents]) { result, error in
            if let error = error {
                print("Error calling cloud function: \(error.localizedDescription)")
                // This is the error you are seeing. The region fix should solve it.
                completion(.failure(error))
                return
            }
            
            guard let json = result?.data as? [String: Any],
                  let customerId = json["customer"] as? String,
                  let customerEphemeralKeySecret = json["ephemeralKey"] as? String,
                  let paymentIntentClientSecret = json["paymentIntent"] as? String else {
                completion(.failure(NSError(domain: "StripeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode backend response from your function."])))
                return
            }
            
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Dumpling House"
            configuration.customer = .init(id: customerId, ephemeralKeySecret: customerEphemeralKeySecret)
            configuration.allowsDelayedPaymentMethods = true
            
            DispatchQueue.main.async {
                self.paymentSheet = PaymentSheet(paymentIntentClientSecret: paymentIntentClientSecret, configuration: configuration)
                completion(.success(()))
            }
        }
    }
}
