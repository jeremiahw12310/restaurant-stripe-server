import SwiftUI
import AVFoundation
import FirebaseAuth

// MARK: - Admin/Employee Rewards QR Scanner

struct AdminRewardsScanView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scanner = QRScannerController()
    @StateObject private var viewModel = AdminRewardsScanViewModel()
    @State private var showConfirmScreen = false

    var body: some View {
        NavigationStack {
            ZStack {
                RewardQRScannerPreview(scanner: scanner)
                    .ignoresSafeArea()

                // Dim overlay to increase contrast
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 16) {
                    header

                    Spacer()

                    viewfinder

                    statusCard

                    Spacer()

                    controls
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)

                if !scanner.isAuthorized {
                    permissionOverlay
                }
            }
            .navigationTitle("Rewards Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                scanner.onStringScanned = { scannedString in
                    viewModel.handleScannedString(scannedString) { code in
                        scanner.pause()
                        Task {
                            await viewModel.validate(code: code)
                        }
                    }
                }
                scanner.checkPermissionAndSetup()
            }
            .onChange(of: viewModel.phase) { _, newValue in
                // Resume scanning whenever we go back to scanning phase
                if newValue == .scanning {
                    scanner.resume()
                }
                // Push confirm screen as soon as validation succeeds
                if newValue == .confirm {
                    showConfirmScreen = true
                }
            }
            .onChange(of: showConfirmScreen) { _, isShowing in
                // If confirm is dismissed (back/cancel), resume scanning cleanly.
                if !isShowing, viewModel.phase == .confirm {
                    viewModel.reset(keepPhaseScanning: true)
                    scanner.resume()
                }
            }
            .onDisappear {
                scanner.stop()
            }
            .navigationDestination(isPresented: $showConfirmScreen) {
                AdminRewardsConfirmView(
                    viewModel: viewModel,
                    onCancel: {
                        showConfirmScreen = false
                    },
                    onFinished: {
                        dismiss()
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Theme.darkGoldGradient)
                .shadow(color: Theme.goldShadow, radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rewards Scan")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Scan customer QR to validate, then confirm")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 280, height: 280)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 6)

            // Corner accents
            RoundedRectangle(cornerRadius: 18)
                .trim(from: 0.02, to: 0.12)
                .stroke(Theme.primaryGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 280, height: 280)
                .rotationEffect(.degrees(0))

            RoundedRectangle(cornerRadius: 18)
                .trim(from: 0.27, to: 0.37)
                .stroke(Theme.primaryGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 280, height: 280)
                .rotationEffect(.degrees(0))

            RoundedRectangle(cornerRadius: 18)
                .trim(from: 0.52, to: 0.62)
                .stroke(Theme.primaryGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 280, height: 280)
                .rotationEffect(.degrees(0))

            RoundedRectangle(cornerRadius: 18)
                .trim(from: 0.77, to: 0.87)
                .stroke(Theme.primaryGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 280, height: 280)
                .rotationEffect(.degrees(0))
        }
        .accessibilityLabel("QR code viewfinder")
    }

    private var statusCard: some View {
        VStack(spacing: 10) {
            switch viewModel.phase {
            case .scanning:
                Text("Point camera at the customer’s QR code")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

            case .validating:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Validating…")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

            case .confirm:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Reward found…")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

            case .consuming:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Confirming…")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

            case .done:
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.green)
                    Text("Reward confirmed")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

            case .error:
                VStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.red)
                    Text(viewModel.errorMessage ?? "Something went wrong.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    viewModel.reset()
                } label: {
                    Text(viewModel.phase == .scanning ? "Reset" : "Scan Another")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                }
                .disabled(viewModel.phase == .validating || viewModel.phase == .consuming)

                Button {
                    scanner.resume()
                    viewModel.reset(keepPhaseScanning: true)
                } label: {
                    Text("Resume")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        )
                }
                .disabled(viewModel.phase == .validating || viewModel.phase == .consuming)
            }
        }
    }

    private var permissionOverlay: some View {
        Color.black.opacity(0.92)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.white)

                    Text("Camera access needed")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text("Enable camera access in Settings to scan reward QR codes.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            )
    }
}

// MARK: - Confirm Screen

private struct AdminRewardsConfirmView: View {
    @Environment(\.dismiss) private var navDismiss
    @ObservedObject var viewModel: AdminRewardsScanViewModel

    let onCancel: () -> Void
    let onFinished: () -> Void

    @State private var autoDismissScheduled = false
    @State private var showGiveCustomerScreen = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Theme.modernBackground, Theme.modernCardSecondary, Theme.modernBackground]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Confirm Reward")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)

                    Text("Double-check details, then confirm.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    if let reward = viewModel.reward {
                        VStack(spacing: 8) {
                            // Build display name based on reward type
                            let displayName = viewModel.buildDisplayName(for: reward)
                            
                            Text(displayName)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(Theme.modernPrimary)
                                .multilineTextAlignment(.center)
                            
                            // Show reward tier if we have detailed selections
                            if displayName != reward.rewardTitle {
                                Text("(\(reward.rewardTitle ?? "Reward"))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary.opacity(0.8))
                            }

                            if let expiresAtText = viewModel.expiresAtText {
                                Text("Expires: \(expiresAtText)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary)
                            }

                            Text("Code: \(reward.redemptionCode ?? "--")")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundStyle(Theme.darkGoldGradient)
                        }
                    } else {
                        Text("No reward details available.")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Theme.modernCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
                )

                if viewModel.phase == .error {
                    Text(viewModel.errorMessage ?? "Something went wrong.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }

                if viewModel.phase == .done {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 22, weight: .bold))
                        Text("Reward confirmed")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                    }
                }

                Spacer()

                Button {
                    Task { await viewModel.consume() }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.phase == .consuming {
                            ProgressView().tint(Color(red: 0.15, green: 0.1, blue: 0.0))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .black))
                        }
                        Text(viewModel.phase == .consuming ? "Confirming…" : "Confirm Reward")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                    }
                    .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [Theme.primaryGold, Theme.energyOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: Theme.primaryGold.opacity(0.35), radius: 12, x: 0, y: 6)
                    )
                }
                .disabled(viewModel.isBusy || viewModel.phase == .done)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                        navDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Theme.modernCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    }

                    Button {
                        viewModel.reset(keepPhaseScanning: true)
                        onCancel()
                        navDismiss()
                    } label: {
                        Text("Scan Another")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    onCancel()
                    navDismiss()
                }
                .disabled(viewModel.isBusy)
            }
        }
        .onChange(of: viewModel.phase) { _, newValue in
            guard newValue == .done else { return }
            guard !autoDismissScheduled else { return }
            autoDismissScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showGiveCustomerScreen = true
            }
        }
        .fullScreenCover(isPresented: $showGiveCustomerScreen) {
            if let reward = viewModel.reward {
                AdminRewardGiveCustomerView(
                    reward: reward,
                    displayName: viewModel.buildDisplayName(for: reward),
                    onDone: {
                        showGiveCustomerScreen = false
                        onFinished()
                    }
                )
            }
        }
    }
}

// MARK: - Give Customer View

private struct AdminRewardGiveCustomerView: View {
    let reward: AdminRewardsScanViewModel.Reward
    let displayName: String
    let onDone: () -> Void
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Theme.modernBackground, Theme.modernCardSecondary, Theme.modernBackground]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Success checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundColor(.green)
                    .shadow(color: .green.opacity(0.3), radius: 20, x: 0, y: 10)
                
                // Header text
                Text("Please give the customer:")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Theme.modernPrimary)
                
                // Item details card
                VStack(spacing: 16) {
                    // Main item display name
                    Text(displayName)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Theme.modernPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    // Reward tier name
                    if let rewardTitle = reward.rewardTitle {
                        VStack(spacing: 6) {
                            Text(rewardTitle)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                            
                            if let pointsRequired = reward.pointsRequired {
                                Text("\(pointsRequired) Points")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary.opacity(0.8))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.modernCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Theme.cardShadow, radius: 15, x: 0, y: 8)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Done button
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.1, blue: 0.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [Theme.primaryGold, Theme.energyOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: Theme.primaryGold.opacity(0.35), radius: 12, x: 0, y: 6)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AdminRewardsScanViewModel: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case validating
        case confirm
        case consuming
        case done
        case error
    }

    struct Reward: Codable, Equatable {
        let id: String?
        let userId: String?
        let rewardTitle: String?
        let rewardDescription: String?
        let rewardCategory: String?
        let pointsRequired: Int?
        let redemptionCode: String?
        let redeemedAt: String?
        let expiresAt: String?
        let isUsed: Bool?
        let isExpired: Bool?
        let selectedItemId: String?      // Selected item ID
        let selectedItemName: String?    // Selected item name for display
        let selectedToppingId: String?   // NEW: Topping ID (for drink rewards)
        let selectedToppingName: String? // NEW: Topping name (for drink rewards)
        let selectedItemId2: String?     // NEW: Second item ID (for half-and-half)
        let selectedItemName2: String?   // NEW: Second item name (for half-and-half)
        let cookingMethod: String?       // NEW: Cooking method (for dumpling rewards)
        let drinkType: String?           // NEW: Drink type (Lemonade or Soda)
        let selectedDrinkItemId: String? // NEW: Drink item ID (for Full Combo)
        let selectedDrinkItemName: String? // NEW: Drink item name (for Full Combo)
    }

    struct ValidateResponse: Codable {
        let status: String
        let reward: Reward?
        let error: String?
    }

    @Published var phase: Phase = .scanning
    @Published var scannedCode: String?
    @Published var reward: Reward?
    @Published var errorMessage: String?

    var isBusy: Bool { phase == .validating || phase == .consuming }

    var expiresAtText: String? {
        guard let iso = reward?.expiresAt else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        // Support fractional seconds (e.g., "2023-11-02T11:47:32.135Z")
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: iso) {
            let fmt = DateFormatter()
            fmt.dateStyle = .none
            fmt.timeStyle = .short
            return fmt.string(from: date)
        }
        return nil
    }
    
    func buildDisplayName(for reward: Reward) -> String {
        // Check if this is Full Combo
        if reward.rewardTitle == "Full Combo" {
            var display = ""
            
            // Check if it's half-and-half (has selectedItemName2 as second dumpling AND selectedDrinkItemName)
            if let itemName = reward.selectedItemName, 
               let itemName2 = reward.selectedItemName2, 
               reward.selectedDrinkItemName != nil {
                // Half-and-half Full Combo
                display = "Half and Half: \(itemName) + \(itemName2)"
                if let method = reward.cookingMethod {
                    display += " (\(method))"
                }
            } else if let dumplingName = reward.selectedItemName {
                // Single dumpling Full Combo
                display = dumplingName
                if let method = reward.cookingMethod {
                    display += " (\(method))"
                }
            }
            
            // Add drink (from selectedDrinkItemName, not selectedItemName2)
            if let drinkName = reward.selectedDrinkItemName {
                display += " + \(drinkName)"
                if let drinkType = reward.drinkType {
                    display += " (\(drinkType))"
                }
            }
            
            // Add topping
            if let toppingName = reward.selectedToppingName {
                display += " with \(toppingName)"
            }
            
            return display.isEmpty ? (reward.rewardTitle ?? "Full Combo") : display
        }
        
        // Check for half-and-half (has second item) - shows both flavors and cooking method
        // This is for regular 12-piece dumplings, not Full Combo
        // Note: 6-Piece Lunch Special does NOT support half-and-half
        if let itemName = reward.selectedItemName, let itemName2 = reward.selectedItemName2 {
            var display = "Half and Half: \(itemName) + \(itemName2)"
            if let method = reward.cookingMethod {
                display += " (\(method))"
            }
            return display
        }
        
        // Check for single dumpling with cooking method (has item but no second item)
        // Shows flavor and cooking method
        if let itemName = reward.selectedItemName,
           reward.selectedItemName2 == nil,
           let method = reward.cookingMethod {
            var display = "\(itemName) (\(method))"
            // Add tag for 6-Piece Lunch Special
            if reward.rewardTitle == "6-Piece Lunch Special Dumplings" {
                display += " (6 Piece Lunch Special)"
            }
            return display
        }
        
        // Check for drink with topping
        // For Lemonade/Soda: shows flavor, drink type, and topping
        // For other teas: shows flavor and topping
        if let itemName = reward.selectedItemName, let toppingName = reward.selectedToppingName {
            if let drinkType = reward.drinkType {
                // Lemonade or Soda with topping
                return "\(itemName) (\(drinkType)) with \(toppingName)"
            }
            // Other teas (Milk Tea, Fruit Tea, Coffee) with topping
            return "\(itemName) with \(toppingName)"
        }
        
        // Check for drink with drink type but no topping (Lemonade/Soda only)
        if let itemName = reward.selectedItemName, let drinkType = reward.drinkType {
            return "\(itemName) (\(drinkType))"
        }
        
        // Check for drink without topping (other teas - Milk Tea, Fruit Tea, Coffee)
        // Shows just the flavor/item name
        if let itemName = reward.selectedItemName {
            var display = itemName
            // Add tag for 6-Piece Lunch Special (in case there's no cooking method shown)
            if reward.rewardTitle == "6-Piece Lunch Special Dumplings" {
                display += " (6 Piece Lunch Special)"
            }
            return display
        }
        
        // Fallback to reward title
        return reward.rewardTitle ?? "Reward"
    }

    func handleScannedString(_ scannedString: String, onCode: (String) -> Void) {
        guard phase == .scanning else { return }
        guard let code = extractEightDigitCode(from: scannedString) else { return }
        scannedCode = code
        onCode(code)
    }

    func validate(code: String) async {
        phase = .validating
        errorMessage = nil
        reward = nil

        do {
            let token = try await requireIdToken()
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/validate") else {
                throw NSError(domain: "AdminRewardsScan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration."])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let body = ["redemptionCode": code]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            guard let statusCode = http?.statusCode else {
                throw NSError(domain: "AdminRewardsScan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
            }
            guard (200..<300).contains(statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "AdminRewardsScan", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Validate failed (\(statusCode)). \(bodyText)"])
            }

            let decoded = try JSONDecoder().decode(ValidateResponse.self, from: data)
            self.reward = decoded.reward

            switch decoded.status {
            case "ok":
                phase = .confirm
            case "expired":
                phase = .error
                errorMessage = "Expired reward."
            case "already_used":
                phase = .error
                errorMessage = "This reward was already used."
            case "not_found":
                phase = .error
                errorMessage = "No matching reward found."
            default:
                phase = .error
                errorMessage = "Unexpected status: \(decoded.status)"
            }
        } catch {
            phase = .error
            errorMessage = error.localizedDescription
        }
    }

    func consume() async {
        guard let code = scannedCode else { return }
        phase = .consuming
        errorMessage = nil

        do {
            let token = try await requireIdToken()
            guard let url = URL(string: "\(Config.backendURL)/admin/rewards/consume") else {
                throw NSError(domain: "AdminRewardsScan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL configuration."])
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let body = ["redemptionCode": code]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            guard let statusCode = http?.statusCode else {
                throw NSError(domain: "AdminRewardsScan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
            }
            guard (200..<300).contains(statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "AdminRewardsScan", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Confirm failed (\(statusCode)). \(bodyText)"])
            }

            let decoded = try JSONDecoder().decode(ValidateResponse.self, from: data)
            self.reward = decoded.reward

            switch decoded.status {
            case "ok":
                phase = .done
            case "expired":
                phase = .error
                errorMessage = "Expired reward."
            case "already_used":
                phase = .error
                errorMessage = "This reward was already used."
            case "not_found":
                phase = .error
                errorMessage = "No matching reward found."
            default:
                phase = .error
                errorMessage = "Unexpected status: \(decoded.status)"
            }
        } catch {
            phase = .error
            errorMessage = error.localizedDescription
        }
    }

    func reset(keepPhaseScanning: Bool = false) {
        scannedCode = nil
        reward = nil
        errorMessage = nil
        phase = keepPhaseScanning ? .scanning : .scanning
    }

    private func requireIdToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "AdminRewardsScan", code: 401, userInfo: [NSLocalizedDescriptionKey: "You must be signed in."])
        }
        return try await user.getIDTokenResult(forcingRefresh: false).token
    }

    private func extractEightDigitCode(from input: String) -> String? {
        // Accept either raw "12345678" or any string containing an 8-digit sequence.
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        if let match = trimmed.range(of: #"\d{8}"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return nil
    }
}

// MARK: - Scanner Controller + Preview

final class QRScannerController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var isAuthorized: Bool = true

    let session = AVCaptureSession()
    private var isConfigured = false
    private var paused = false

    var onStringScanned: ((String) -> Void)?

    func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupIfNeeded()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func pause() { paused = true }
    func resume() { paused = false }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    private func setupIfNeeded() {
        guard !isConfigured else {
            startIfNeeded()
            return
        }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            isAuthorized = false
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            isAuthorized = false
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        session.commitConfiguration()
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !paused else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        onStringScanned?(value)
    }
}

struct RewardQRScannerPreview: UIViewControllerRepresentable {
    let scanner: QRScannerController

    func makeUIViewController(context: Context) -> RewardQRScannerPreviewViewController {
        let controller = RewardQRScannerPreviewViewController()
        controller.scanner = scanner
        return controller
    }

    func updateUIViewController(_ uiViewController: RewardQRScannerPreviewViewController, context: Context) {}
}

final class RewardQRScannerPreviewViewController: UIViewController {
    var scanner: QRScannerController?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupPreviewLayerIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupPreviewLayerIfNeeded() {
        guard previewLayer == nil, let session = scanner?.session else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }
}


