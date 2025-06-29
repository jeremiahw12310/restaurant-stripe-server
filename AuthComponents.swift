//
//  AuthComponents.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/26/25.
//

import SwiftUI

// A beautiful reusable view for phone number input
struct PhoneNumberInputView: View {
    let title: String
    @Binding var phoneNumber: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            // Simple, reliable phone number input
            TextField("(555) 123-4567", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.ultraThinMaterial, lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .focused($isFocused)
                .onChange(of: phoneNumber) { oldValue, newValue in
                    // Format the phone number as user types
                    phoneNumber = formatPhoneNumber(newValue)
                }
        }
    }
    
    // Format phone number to (XXX) XXX-XXXX
    private func formatPhoneNumber(_ input: String) -> String {
        // Remove all non-digit characters
        let digits = input.filter { $0.isNumber }
        
        // Limit to 10 digits
        let limitedDigits = String(digits.prefix(10))
        
        // Format based on length
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

// A beautiful reusable view for a single digit input field.
struct DigitTextField: View {
    @Binding var text: String
    let isSecure: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Beautiful background with glass effect
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.ultraThinMaterial, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // This is what the user sees.
            Text(isSecure ? (text.isEmpty ? "" : "•") : text)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(width: 40, height: 50)
            
            // This is the invisible TextField that handles the input.
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .multilineTextAlignment(.center)
                .tint(.clear) // Hides the editing cursor
                .foregroundColor(.clear) // Hides the typed text
                .focused($isFocused)
                .onChange(of: text) { oldValue, newValue in
                    // Ensure only one digit per field.
                    if newValue.count > 1 {
                        text = String(newValue.suffix(1))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                    // Handle backspace when keyboard is dismissed
                    if isFocused && text.isEmpty {
                        // This will be handled by the parent view
                    }
                }
        }
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

// A beautiful custom style for our main action buttons.
struct PrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color = .blue
    var foregroundColor: Color = .white
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(foregroundColor)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [backgroundColor, backgroundColor.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: backgroundColor.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// A beautiful secondary button style
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.ultraThinMaterial, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// A beautiful text field style
struct BeautifulTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    
    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.ultraThinMaterial, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
