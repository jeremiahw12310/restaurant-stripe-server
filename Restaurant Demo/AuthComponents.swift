//
//  AuthComponents.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/26/25.
//

import SwiftUI
import UIKit

// MARK: - OTP TextField (UIKit-based for reliable iOS autofill)
/// A UIKit-based text field specifically designed for OTP/SMS code entry.
/// Uses UITextField instead of SwiftUI TextField to ensure iOS autofill works correctly.
/// The key difference is using target-action (.editingChanged) instead of onChange,
/// which fires AFTER autofill completes rather than interrupting the autofill process.
struct OTPTextField: UIViewRepresentable {
    @Binding var text: String
    var onComplete: ((String) -> Void)?
    var shouldBecomeFirstResponder: Bool = false
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        
        // Critical: Set oneTimeCode content type for iOS autofill
        textField.textContentType = .oneTimeCode
        textField.keyboardType = .numberPad
        
        // Styling to match the app's design
        textField.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        textField.textAlignment = .center
        // Convert SwiftUI Color to UIColor using RGB values from Theme
        // Theme.modernPrimary = Color(red: 0.15, green: 0.15, blue: 0.25)
        textField.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.25, alpha: 1.0)
        // Theme.primaryGold = Color(red: 0.85, green: 0.65, blue: 0.25)
        textField.tintColor = UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1.0)
        
        // No placeholder - empty field works better with autofill
        textField.placeholder = ""
        
        // Set delegate for shouldChangeCharactersIn (must return true for autofill)
        textField.delegate = context.coordinator
        
        // Use target-action pattern - this fires AFTER autofill completes
        // Unlike SwiftUI's onChange which fires during autofill and can interrupt it
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textFieldDidChange(_:)),
            for: .editingChanged
        )
        
        // Set initial text if any
        textField.text = text
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Only update text if it differs (avoid cursor jump issues)
        if uiView.text != text {
            uiView.text = text
        }
        
        // CRITICAL: Only become first responder once, and only when:
        // 1. We're requested to focus
        // 2. The view is attached to a window (fully laid out)
        // 3. We haven't already focused once (prevents re-triggering during SwiftUI re-renders)
        // This prevents interrupting iOS autofill insertion
        if shouldBecomeFirstResponder 
            && !uiView.isFirstResponder 
            && uiView.window != nil 
            && !context.coordinator.hasFocusedOnce {
            context.coordinator.hasFocusedOnce = true
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OTPTextField
        var hasFocusedOnce: Bool = false
        
        init(_ parent: OTPTextField) {
            self.parent = parent
        }
        
        // CRITICAL: Always return true to allow autofill to work
        // Returning false or modifying text here will break iOS autofill
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            return true
        }
        
        // This fires AFTER the text has been changed (including autofill)
        // Safe to filter and validate here
        @objc func textFieldDidChange(_ textField: UITextField) {
            // Filter to only digits and limit to 6 characters
            let currentText = textField.text ?? ""
            let digits = currentText.filter { $0.isNumber }
            let limited = String(digits.prefix(6))
            
            // Update the text field if filtering changed anything
            if currentText != limited {
                textField.text = limited
            }
            
            // Sync back to SwiftUI binding
            DispatchQueue.main.async {
                self.parent.text = limited
                
                // Trigger completion callback when we have 6 digits
                if limited.count == 6 {
                    // Small delay to ensure UI is updated before verification starts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.parent.onComplete?(limited)
                    }
                }
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - Phone Number Input View
// A beautiful reusable view for phone number input with gold focus state
struct PhoneNumberInputView: View {
    let title: String
    @Binding var phoneNumber: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.primaryGold)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
            }
            
            // Phone input with gold border on focus
            TextField("(555) 123-4567", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isFocused ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2), lineWidth: isFocused ? 2 : 1)
                        )
                )
                .shadow(color: isFocused ? Theme.primaryGold.opacity(0.15) : Color.black.opacity(0.05), radius: isFocused ? 8 : 5, x: 0, y: 2)
                .focused($isFocused)
                .onChange(of: phoneNumber) { oldValue, newValue in
                    phoneNumber = formatPhoneNumber(newValue)
                }
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
    
    // Format phone number to (XXX) XXX-XXXX
    private func formatPhoneNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limitedDigits = String(digits.prefix(10))
        
        switch limitedDigits.count {
        case 0...3:
            return limitedDigits
        case 4...6:
            let areaCode = limitedDigits.prefix(3)
            let prefix = limitedDigits.dropFirst(3)
            return "(\(areaCode)) \(prefix)"
        case 7...10:
            let areaCode = limitedDigits.prefix(3)
            let prefix = limitedDigits.dropFirst(3).prefix(3)
            let lineNumber = limitedDigits.dropFirst(6)
            return "(\(areaCode)) \(prefix)-\(lineNumber)"
        default:
            return limitedDigits
        }
    }
}

// A beautiful reusable view for a single digit input field with gold styling
struct DigitTextField: View {
    @Binding var text: String
    let isSecure: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Beautiful background with gold focus state
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Theme.primaryGold : (text.isEmpty ? Theme.modernSecondary.opacity(0.2) : Theme.primaryGold.opacity(0.5)), lineWidth: isFocused ? 2 : 1)
                )
                .shadow(color: isFocused ? Theme.primaryGold.opacity(0.2) : Color.black.opacity(0.05), radius: isFocused ? 6 : 4, x: 0, y: 2)
            
            // This is what the user sees.
            Text(isSecure ? (text.isEmpty ? "" : "•") : text)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
                .frame(width: 40, height: 50)
            
            // This is the invisible TextField that handles the input.
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .multilineTextAlignment(.center)
                .tint(.clear)
                .foregroundColor(.clear)
                .focused($isFocused)
                .onChange(of: text) { oldValue, newValue in
                    if newValue.count > 1 {
                        text = String(newValue.suffix(1))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                    if isFocused && text.isEmpty {
                        // This will be handled by the parent view
                    }
                }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.isEmpty)
    }
}

// A beautiful reusable view that arranges multiple digit fields into a row.
struct DigitInputView: View {
    let title: String
    @Binding var digits: [String]
    var isSecure: Bool = false
    @FocusState.Binding var focusedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            // ✅ CHANGE: Custom layout for phone numbers vs. PINs.
            if digits.count == 10 && !isSecure {
                phoneNumberLayout
            } else {
                pinLayout
            }
        }
    }
    
    // ✅ NEW: A dedicated layout for the phone number input for better formatting.
    private var phoneNumberLayout: some View {
        HStack(spacing: 6) {
            // Country code
            Text("+1")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                )
            
            // Area code
            Text("(")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            
            ForEach(0..<3, id: \.self) { index in
                digitField(for: index)
            }
            
            Text(")")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            
            // Middle digits
            ForEach(3..<6, id: \.self) { index in
                digitField(for: index)
            }
            
            Text("-")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            
            // Last digits
            ForEach(6..<10, id: \.self) { index in
                digitField(for: index)
            }
        }
    }
    
    // The beautiful layout for PINs.
    private var pinLayout: some View {
        HStack(spacing: 12) {
            ForEach(0..<digits.count, id: \.self) { index in
                digitField(for: index)
            }
        }
    }
    
    // Helper view to avoid repeating the text field and its modifiers.
    @ViewBuilder
    private func digitField(for index: Int) -> some View {
        DigitTextField(text: $digits[index], isSecure: isSecure)
            .focused($focusedIndex, equals: index)
            .onChange(of: digits[index]) { oldValue, newValue in
                // Move focus to the next field when a digit is entered.
                if !newValue.isEmpty {
                    if index + 1 < digits.count {
                        focusedIndex = index + 1
                    } else {
                        focusedIndex = nil // Unfocus after the last field
                    }
                }
            }
            .onTapGesture {
                // Allow tapping to focus on any field
                focusedIndex = index
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                // Handle backspace when keyboard is dismissed
                if focusedIndex == index && digits[index].isEmpty && index > 0 {
                    // Move to previous field and clear it
                    focusedIndex = index - 1
                    digits[index - 1] = ""
                }
            }
            .onSubmit {
                // Handle backspace by moving to previous field
                if digits[index].isEmpty && index > 0 {
                    focusedIndex = index - 1
                    digits[index - 1] = ""
                }
            }
    }
}

// Enhanced primary button style using design system - Matching Get Started button
struct PrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color = AppColors.dumplingGold
    var foregroundColor: Color = .white
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .tracking(0.5)
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.darkGoldGradient)
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Enhanced secondary button style with gold accent
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.modernSecondary)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.modernSecondary.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// A beautiful text field style with gold focus state
struct BeautifulTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
            }
        }
        .font(.system(size: 17, weight: .medium, design: .rounded))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2), lineWidth: isFocused ? 2 : 1)
                )
        )
        .shadow(color: isFocused ? Theme.primaryGold.opacity(0.15) : Color.black.opacity(0.05), radius: isFocused ? 8 : 5, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
