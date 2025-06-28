//
//  AuthComponents.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/26/25.
//

import SwiftUI

// A reusable view for a single digit input field.
struct DigitTextField: View {
    @Binding var text: String
    let isSecure: Bool
    
    var body: some View {
        ZStack {
            // This is what the user sees.
            Text(isSecure ? (text.isEmpty ? "" : "•") : text)
                // ✅ FIX: Reduced font size to help fields fit on screen.
                .font(isSecure ? .system(size: 30) : .system(size: 22, weight: .bold))
                // ✅ FIX: Reduced frame size to prevent overflow.
                .frame(width: 35, height: 45)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            // This is the invisible TextField that handles the input.
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .tint(.clear) // Hides the editing cursor
                .foregroundColor(.clear) // Hides the typed text
                .onChange(of: text) { oldValue, newValue in
                    // Ensure only one digit per field.
                    if newValue.count > 1 {
                        text = String(newValue.suffix(1))
                    }
                }
        }
    }
}

// A reusable view that arranges multiple digit fields into a row.
struct DigitInputView: View {
    let title: String
    @Binding var digits: [String]
    var isSecure: Bool = false
    @FocusState.Binding var focusedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            
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
        HStack(spacing: 4) {
            Text("+1")
                .font(.headline)
            
            Text("(")
            ForEach(0..<3, id: \.self) { index in
                digitField(for: index)
            }
            Text(")")
            
            ForEach(3..<6, id: \.self) { index in
                digitField(for: index)
            }
            
            Text("-")
            
            ForEach(6..<10, id: \.self) { index in
                digitField(for: index)
            }
        }
    }
    
    // The original layout, now used for PINs.
    private var pinLayout: some View {
        HStack(spacing: 10) {
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
    }
}

// A custom style for our main action buttons.
struct PrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color = .blue
    var foregroundColor: Color = .white
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .font(.headline)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0) // Adds a nice press effect
    }
}
