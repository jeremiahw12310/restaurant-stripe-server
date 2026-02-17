//
//  ReservationSheetView.swift
//  Restaurant Demo
//
//  Form for customers to create a table reservation; submits to POST /reservations.
//

import SwiftUI
import FirebaseAuth

// MARK: - View Model

final class ReservationSheetViewModel: ObservableObject {
    @Published var date: Date = Calendar.current.startOfDay(for: Date())
    @Published var time: Date = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date()) ?? Date()
    @Published var partySize: Int = 2
    @Published var customerName: String = ""
    @Published var phone: String = ""
    @Published var email: String = ""
    @Published var specialRequests: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSuccess = false

    private let minPartySize = 1
    private let maxPartySize = 20

    var partySizeRange: ClosedRange<Int> { minPartySize...maxPartySize }

    func incrementPartySize() {
        if partySize < maxPartySize { partySize += 1 }
    }

    func decrementPartySize() {
        if partySize > minPartySize { partySize -= 1 }
    }

    /// Format time for API (e.g. "6:30 PM")
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Format date for API (YYYY-MM-DD)
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// True if contact step (step 3) has required fields filled.
    var isContactStepValid: Bool {
        !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() {
        errorMessage = nil
        let name = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneTrimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errorMessage = "Please enter your name."
            return
        }
        if phoneTrimmed.isEmpty {
            errorMessage = "Please enter your phone number."
            return
        }

        guard let user = Auth.auth().currentUser else {
            errorMessage = "Please sign in to make a reservation."
            return
        }

        let dateStr = Self.formatDate(date)
        let timeStr = Self.formatTime(time)
        let today = Calendar.current.startOfDay(for: Date())
        let selectedDay = Calendar.current.startOfDay(for: date)
        if selectedDay < today {
            errorMessage = "Please select today or a future date."
            return
        }

        isLoading = true
        user.getIDToken { [weak self] token, err in
            guard let self = self else { return }
            DispatchQueue.main.async { self.isLoading = false }
            if let err = err {
                DispatchQueue.main.async {
                    self.errorMessage = "Sign-in error. Please try again."
                }
                return
            }
            guard let token = token,
                  let url = URL(string: "\(Config.backendURL)/reservations") else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid configuration."
                }
                return
            }

            var body: [String: Any] = [
                "customerName": name,
                "phone": phoneTrimmed,
                "date": dateStr,
                "time": timeStr,
                "partySize": partySize
            ]
            if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["email"] = email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !specialRequests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body["specialRequests"] = specialRequests.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                DispatchQueue.main.async { self.errorMessage = "Invalid form data." }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, response, _ in
                DispatchQueue.main.async {
                    guard let http = response as? HTTPURLResponse else {
                        self.errorMessage = "Request failed."
                        return
                    }
                    if http.statusCode == 201 {
                        self.showSuccess = true
                    } else {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let msg = json["error"] as? String {
                            self.errorMessage = msg
                        } else {
                            self.errorMessage = "Unable to create reservation. Please try again."
                        }
                    }
                }
            }.resume()
        }
    }
}

// MARK: - Step Hero Header

private struct StepHeroHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGold.opacity(0.2), Theme.deepGold.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.darkGoldGradient)
            }
            .shadow(color: Theme.primaryGold.opacity(0.3), radius: 10, x: 0, y: 4)

            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.darkGoldGradient)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

// MARK: - Reservation Step Indicator

private struct ReservationStepIndicator: View {
    let currentStep: Int
    private let totalSteps = 4
    private let stepLabels = ["When", "Party", "Contact", "Confirm"]
    private let stepIcons = ["calendar", "person.3.fill", "person.text.rectangle", "checkmark.shield"]

    var body: some View {
        VStack(spacing: 14) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Theme.modernSecondary.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Theme.darkGoldGradient)
                        .frame(
                            width: max(0, geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps)),
                            height: 4
                        )
                        .shadow(color: Theme.primaryGold.opacity(0.4), radius: 4, x: 0, y: 1)
                }
            }
            .frame(height: 4)
            .animation(.spring(response: 0.48, dampingFraction: 0.88), value: currentStep)

            // Step circles with connectors
            HStack(spacing: 0) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    // Step circle + label
                    VStack(spacing: 6) {
                        ZStack {
                            if step < currentStep {
                                // Completed: gold fill + checkmark
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.primaryGold, Theme.deepGold],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 30, height: 30)
                                    .shadow(color: Theme.goldShadow, radius: 4, x: 0, y: 2)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            } else if step == currentStep {
                                // Current: gold fill + number
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.primaryGold, Theme.deepGold],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 30, height: 30)
                                    .shadow(color: Theme.goldShadow, radius: 6, x: 0, y: 2)
                                Text("\(step + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            } else {
                                // Future: gray stroke + number
                                Circle()
                                    .stroke(Theme.modernSecondary.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 30, height: 30)
                                Text("\(step + 1)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary.opacity(0.5))
                            }
                        }

                        Text(stepLabels[step])
                            .font(.system(size: 12, weight: step == currentStep ? .bold : .medium, design: .rounded))
                            .foregroundColor(step <= currentStep ? Theme.primaryGold : Theme.modernSecondary.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)

                    // Connector line between steps
                    if step < totalSteps - 1 {
                        Rectangle()
                            .fill(step < currentStep ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: 20)
                            .offset(y: -10)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.primaryGold.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
        )
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: currentStep)
    }
}

// MARK: - Reservation Success View

private struct ReservationSuccessView: View {
    let onDone: () -> Void
    @State private var iconScale: CGFloat = 0.3
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Checkmark icon with animated entrance
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryGold, Theme.deepGold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Theme.goldShadow, radius: 20, x: 0, y: 10)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(iconScale)
            .opacity(iconOpacity)

            VStack(spacing: 8) {
                Text("Reservation Requested!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .multilineTextAlignment(.center)

                Text("We'll confirm your booking soon.\nOur team may call you if needed.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(textOpacity)

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.darkGoldGradient)
                            .shadow(color: Theme.goldShadow, radius: 10, x: 0, y: 4)
                    )
            }
            .opacity(textOpacity)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                textOpacity = 1.0
            }
        }
    }
}

// MARK: - Sheet View

struct ReservationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var viewModel = ReservationSheetViewModel()
    @State private var currentStep: Int = 0
    @State private var partySizeScale: CGFloat = 1.0

    // Focus states for contact fields
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var phoneFieldFocused: Bool
    @FocusState private var emailFieldFocused: Bool
    @FocusState private var requestsFieldFocused: Bool

    private let totalSteps = 4
    private let stepLabels = ["When", "Party", "Contact", "Confirm"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.modernBackground
                    .ignoresSafeArea()

                if viewModel.showSuccess {
                    // In-sheet celebration screen
                    ReservationSuccessView(onDone: { dismiss() })
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 24) {
                                ReservationStepIndicator(currentStep: currentStep)
                                    .id("reservationScrollTop")
                                stepContent
                                if let msg = viewModel.errorMessage {
                                    Text(msg)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                stepActions
                            }
                            .padding(24)
                        }
                        .onChange(of: currentStep) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("reservationScrollTop", anchor: .top)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.showSuccess)
            .navigationTitle("Reserve a Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        nameFieldFocused = false
                        phoneFieldFocused = false
                        emailFieldFocused = false
                        requestsFieldFocused = false
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.primaryGold)
                }
            }
            .onAppear {
                viewModel.customerName = userVM.firstName
                viewModel.phone = userVM.phoneNumber
            }
        }
    }

    // MARK: - Step Content Router

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0:
                whenStep
                    .transition(.opacity)
            case 1:
                partyStep
                    .transition(.opacity)
            case 2:
                contactStep
                    .transition(.opacity)
            case 3:
                confirmStep
                    .transition(.opacity)
            default:
                whenStep
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: currentStep)
    }

    // MARK: - Step 0: When

    private var whenStep: some View {
        VStack(spacing: 24) {
            StepHeroHeader(
                icon: "calendar",
                title: "When are you coming?",
                subtitle: "Pick the perfect date and time"
            )

            // Card 1: Date
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.primaryGold)
                    Text("Date")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }

                DatePicker("Date", selection: $viewModel.date, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.primaryGold)
                    .onTapGesture(count: 99) { }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.modernCard)
                    .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
            )

            // Card 2: Time
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.primaryGold)
                    Text("Time")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }

                DatePicker("Time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                    .tint(Theme.primaryGold)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.modernCard)
                    .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
            )
        }
    }

    // MARK: - Step 1: Party

    private var partyStep: some View {
        VStack(spacing: 20) {
            StepHeroHeader(
                icon: "person.3.fill",
                title: "How many guests?",
                subtitle: "We'll find you the right table"
            )

            VStack(spacing: 20) {
                // Large party size display
                VStack(spacing: 4) {
                    Text("\(viewModel.partySize)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .scaleEffect(partySizeScale)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: partySizeScale)

                    Text(viewModel.partySize == 1 ? "guest" : "guests")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .frame(maxWidth: .infinity)

                // Large +/- buttons
                HStack(spacing: 40) {
                    Button(action: {
                        viewModel.decrementPartySize()
                        bouncePartySize()
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(
                                        viewModel.partySize <= viewModel.partySizeRange.lowerBound
                                            ? LinearGradient(colors: [Theme.modernSecondary.opacity(0.3), Theme.modernSecondary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : Theme.darkGoldGradient
                                    )
                                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                            )
                    }
                    .disabled(viewModel.partySize <= viewModel.partySizeRange.lowerBound)

                    Button(action: {
                        viewModel.incrementPartySize()
                        bouncePartySize()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(
                                        viewModel.partySize >= viewModel.partySizeRange.upperBound
                                            ? LinearGradient(colors: [Theme.modernSecondary.opacity(0.3), Theme.modernSecondary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : Theme.darkGoldGradient
                                    )
                                    .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                            )
                    }
                    .disabled(viewModel.partySize >= viewModel.partySizeRange.upperBound)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.modernCard)
                    .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
            )
        }
    }

    private func bouncePartySize() {
        partySizeScale = 1.15
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            partySizeScale = 1.0
        }
    }

    // MARK: - Step 2: Contact

    private var contactStep: some View {
        VStack(spacing: 20) {
            StepHeroHeader(
                icon: "person.text.rectangle",
                title: "Your details",
                subtitle: "So we can confirm your booking"
            )

            VStack(alignment: .leading, spacing: 20) {
                goldTextField(
                    icon: "person.fill",
                    placeholder: "Name",
                    text: $viewModel.customerName,
                    isFocused: nameFieldFocused,
                    focusBinding: $nameFieldFocused,
                    contentType: .name,
                    capitalization: .words
                )

                goldTextField(
                    icon: "phone.fill",
                    placeholder: "Phone",
                    text: $viewModel.phone,
                    isFocused: phoneFieldFocused,
                    focusBinding: $phoneFieldFocused,
                    contentType: .telephoneNumber,
                    keyboardType: .phonePad
                )

                goldTextField(
                    icon: "envelope.fill",
                    placeholder: "Email (optional)",
                    text: $viewModel.email,
                    isFocused: emailFieldFocused,
                    focusBinding: $emailFieldFocused,
                    contentType: .emailAddress,
                    keyboardType: .emailAddress,
                    capitalization: .none
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.modernCard)
                    .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
            )
        }
    }

    /// Reusable gold-accent text field with icon and focus glow
    private func goldTextField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isFocused: Bool,
        focusBinding: FocusState<Bool>.Binding,
        contentType: UITextContentType? = nil,
        keyboardType: UIKeyboardType = .default,
        capitalization: UITextAutocapitalizationType = .sentences
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isFocused ? Theme.primaryGold : Theme.modernSecondary)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: isFocused)

            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .autocapitalization(capitalization)
                .focused(focusBinding)
        }
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
        .shadow(color: isFocused ? Theme.primaryGold.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    // MARK: - Step 3: Confirm

    private var confirmStep: some View {
        VStack(spacing: 20) {
            StepHeroHeader(
                icon: "checkmark.shield",
                title: "Review and confirm",
                subtitle: "Almost there!"
            )

            VStack(alignment: .leading, spacing: 20) {
                // Special requests with gold-focus style
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.primaryGold)
                        Text("Special requests (optional)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                    }

                    TextField("Dietary needs, high chair, etc.", text: $viewModel.specialRequests, axis: .vertical)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .focused($requestsFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { requestsFieldFocused = false }
                        .lineLimit(3...6)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            requestsFieldFocused ? Theme.primaryGold : Theme.modernSecondary.opacity(0.2),
                                            lineWidth: requestsFieldFocused ? 2 : 1
                                        )
                                )
                        )
                        .shadow(color: requestsFieldFocused ? Theme.primaryGold.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 2)
                        .animation(.easeInOut(duration: 0.2), value: requestsFieldFocused)
                }

                Divider()
                    .padding(.vertical, 4)

                // Summary header
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.primaryGold)
                    Text("Summary")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                }

                reservationSummary
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.modernCard)
                    .shadow(color: Theme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
            )
            .onChange(of: viewModel.specialRequests) { _, newValue in
                if requestsFieldFocused && newValue.contains("\n") {
                    requestsFieldFocused = false
                    viewModel.specialRequests = newValue.replacingOccurrences(of: "\n", with: "")
                }
            }
        }
    }

    // MARK: - Summary with Icons

    private var reservationSummary: some View {
        let dateStr = formatDate(viewModel.date)
        let timeStr = formatTime(viewModel.time)
        return VStack(spacing: 0) {
            summaryRow(icon: "calendar", iconColor: Theme.energyOrange, label: "Date", value: dateStr)
            Divider().padding(.leading, 44)
            summaryRow(icon: "clock.fill", iconColor: Theme.energyBlue, label: "Time", value: timeStr)
            Divider().padding(.leading, 44)
            summaryRow(icon: "person.2.fill", iconColor: Theme.energyGreen, label: "Party size", value: "\(viewModel.partySize) \(viewModel.partySize == 1 ? "guest" : "guests")")
            Divider().padding(.leading, 44)
            summaryRow(icon: "person.fill", iconColor: Theme.primaryGold, label: "Name", value: viewModel.customerName.isEmpty ? "—" : viewModel.customerName)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.modernCardSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.modernSecondary.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func summaryRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.modernSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.modernPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    // MARK: - Formatters

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Step Actions (Buttons)

    @ViewBuilder
    private var stepActions: some View {
        HStack(spacing: 16) {
            if currentStep > 0 {
                Button(action: {
                    viewModel.errorMessage = nil
                    nameFieldFocused = false
                    phoneFieldFocused = false
                    emailFieldFocused = false
                    requestsFieldFocused = false
                    withAnimation { currentStep -= 1 }
                }) {
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.primaryGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Theme.primaryGold, lineWidth: 2)
                                )
                        )
                        .shadow(color: Theme.goldShadow, radius: 6, x: 0, y: 3)
                }
            }

            if currentStep < totalSteps - 1 {
                let isDisabled = currentStep == 2 && !viewModel.isContactStepValid
                Button(action: goNext) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Theme.darkGoldGradient)
                    )
                    .shadow(color: Theme.goldShadow, radius: 10, x: 0, y: 4)
                    .opacity(isDisabled ? 0.5 : 1.0)
                }
                .disabled(isDisabled)
            } else {
                Button(action: { viewModel.submit() }) {
                    HStack(spacing: 8) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Request reservation")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(viewModel.isLoading ? Theme.modernSecondary : Theme.energyOrange)
                    )
                    .foregroundColor(.white)
                    .shadow(color: viewModel.isLoading ? Color.clear : Theme.energyOrange.opacity(0.4), radius: 10, x: 0, y: 4)
                }
                .disabled(viewModel.isLoading)
            }
        }
    }

    private func goNext() {
        viewModel.errorMessage = nil
        if currentStep == 2 && !viewModel.isContactStepValid { return }
        // Dismiss keyboard when advancing
        nameFieldFocused = false
        phoneFieldFocused = false
        emailFieldFocused = false
        requestsFieldFocused = false
        withAnimation { currentStep += 1 }
    }
}

#Preview {
    ReservationSheetView()
        .environmentObject(UserViewModel())
}
