import SwiftUI
import Vision
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Photos

struct ReceiptScanView: View {
    @StateObject private var userVM = UserViewModel()
    @StateObject private var menuVM = MenuViewModel()
    @State private var showCamera = false
    @State private var scannedImage: UIImage?
    @State private var isProcessing = false
    @State private var showCongratulations = false
    @State private var showReceiptUsedScreen = false
    @State private var receiptTotal: Double = 0.0
    @State private var pointsEarned: Int = 0
    @State private var errorMessage = ""
    @State private var showCameraPermissionScreen = false
    @State private var cameraPermissionDenied = false
    @State private var scannedText = ""
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var onPointsEarned: ((Int) -> Void)? = nil
    @State private var showDumplingRain = false
    @State private var shouldSwitchToHome = false
    @State private var lastOrderNumber: String? = nil
    @State private var lastOrderDate: String? = nil
    // Combo interstitial + result
    @State private var isComboReady = false
    @State private var hasStartedComboGeneration = false
    @State private var personalizedCombo: PersonalizedCombo?
    @State private var showComboResult = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var presentedOutcome: ReceiptScanOutcome? = nil
    @State private var comboState: ComboGenerationState = .loading
    @State private var showReferral = false
    // Validation state
    @State private var receiptPassedValidation = false
    @State private var pendingPoints: Int = 0
    @State private var pendingTotal: Double = 0.0
    // Store last captured image for retry functionality
    @State private var lastCapturedImage: UIImage? = nil
    // Server response coordination
    @State private var serverHasResponded = false
    @State private var interstitialTimedOut = false
    @State private var interstitialTimeoutWorkItem: DispatchWorkItem? = nil
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            mainView
        }
        .onAppear {
            userVM.loadUserData()
            menuVM.fetchMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
            // Handle switching to home tab
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { presentedOutcome != nil },
            set: { newValue in if !newValue { presentedOutcome = nil } }
        )) {
            if let outcome = presentedOutcome {
                ReceiptResultView(
                    outcome: outcome,
                    comboState: comboState,
                    personalizedCombo: personalizedCombo,
                    onPrimary: { handlePrimaryAction(for: outcome) },
                    onSecondary: { handleSecondaryAction(for: outcome) },
                    onDismiss: { presentedOutcome = nil },
                    onRetryCombo: { retryComboGeneration() }
                )
                .environmentObject(menuVM)
            }
        }
        .onChange(of: shouldSwitchToHome) { newValue, _ in
            if newValue {
                switchToHomeTab()
                // Reset all relevant state
                showReceiptUsedScreen = false
                showCongratulations = false
                errorMessage = ""
                showDumplingRain = false
                shouldSwitchToHome = false
            }
        }
        .sheet(isPresented: $showCameraPermissionScreen) {
            CameraPrePermissionView(
                isPermissionDenied: cameraPermissionDenied,
                onRequestAccess: { requestCameraAccess() },
                onOpenSettings: { openAppSettings() },
                onDismiss: { showCameraPermissionScreen = false }
            )
        }
        .sheet(isPresented: $showCamera) {
            CameraViewWithOverlay(image: $scannedImage) { image, liveTotalsConfirmed in
                // Don't dismiss camera here — video plays in-place until result is ready
                if let image = image {
                    // Guard: don't process if already processing
                    guard !isProcessing else {
                        DebugLogger.debug("⚠️ Image capture ignored - already processing", category: "ReceiptScan")
                        return
                    }
                    processReceiptImage(image, liveTotalsConfirmed: liveTotalsConfirmed)
                }
            }
        }
        .onChange(of: showCamera) { newValue in
            if !newValue {
                // Clean up when camera sheet is dismissed
                interstitialTimeoutWorkItem?.cancel()
                interstitialTimeoutWorkItem = nil
                // Only clear Combine subs if server already responded (otherwise upload is in flight)
                if serverHasResponded || !isProcessing {
                    cancellables.removeAll()
                }
            }
        }
    }
    
    private var mainView: some View {
        ZStack {
            // Hybrid Energy background to match Home/Chatbot
            LinearGradient(
                gradient: Gradient(colors: [
                    Theme.modernBackground,
                    Theme.modernCardSecondary,
                    Theme.modernBackground
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            // Always-on gold blob background (subtle, slow)
            GoldBlobBackground()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 20)

                // Text-only header (reduced hero prominence)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan & Earn")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                    }
                    .layoutPriority(1)
                    Spacer()
                    // Dumpphone image in header (no glow/shimmer), 50% larger with small-screen cap
                    Image("dumpphone")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: min(90, UIScreen.main.bounds.width * 0.22),
                            height: min(90, UIScreen.main.bounds.width * 0.22)
                        )
                        .layoutPriority(0)
                }
                .padding(.horizontal, 24)

                // Small Refer button near top
                HStack {
                    Spacer()
                    Button(action: { showReferral = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Refer a Friend")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(height: 48)
                        .background(
                            Capsule()
                                .fill(LinearGradient(gradient: Gradient(colors: [Theme.energyBlue, Theme.energyBlue.opacity(0.85)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: Theme.cardShadow, radius: 6, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 24)
                }

                // Glass info card with steps
                VStack(spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        stepIcon("camera.fill", color: Theme.energyBlue)
                        stepText(title: "Scan your receipt", subtitle: "Keep the whole receipt visible")
                        Spacer()
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Image("newhero")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                        stepText(title: "Dumpling Hero AI counts points", subtitle: "Your receipt is processed securely")
                        Spacer()
                    }
                    HStack(alignment: .center, spacing: 12) {
                        stepIcon("gift.fill", color: Theme.primaryGold)
                        stepText(title: "Earn Rewards", subtitle: "5 pts per dollar, instantly")
                        Spacer()
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.modernCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Theme.darkGoldGradient, lineWidth: 2)
                        )
                        .shadow(color: Theme.cardShadow, radius: 14, x: 0, y: 6)
                )
                .padding(.horizontal, 24)

                // Admin-only old receipt testing toggle
                if userVM.isAdmin {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $userVM.oldReceiptTestingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow old receipts for testing")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Text("Admin only. Temporarily relaxes the 48-hour limit for this account. Tampering checks still apply.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.modernSecondary)
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Theme.energyBlue))
                            .onChange(of: userVM.oldReceiptTestingEnabled) { newValue in
                                userVM.updateOldReceiptTestingEnabled(newValue)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $userVM.saveScannedReceiptsToCameraRoll) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Save scanned receipts to camera roll")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Text("Admin debug only. Saves the exact image sent to the server (cropped or full). Remove before production.")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.modernSecondary)
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Theme.energyBlue))
                        }
                    }
                    .padding(.horizontal, 24)

                }

                Spacer()

                // Primary CTA
                VStack(spacing: 14) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.primaryGold))
                    } else {
                        Button(action: { checkCameraPermission() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 19, weight: .bold))
                                Text("Start Scan")
                                    .font(.system(size: 19, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Theme.darkGoldGradient)
                                    .shadow(color: Theme.goldShadow, radius: 12, x: 0, y: 6)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 24)
                    }

                    // Secondary affordances
                    Text("Trouble scanning? Try brighter lighting and keep the receipt flat.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showReferral) {
            ReferralView(initialCode: nil)
                .environmentObject(userVM)
        }
    }
    
    private var congratulationsView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Celebration headline
            VStack(spacing: 10) {
                Text("+\(pointsEarned) pts")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .shadow(color: Theme.goldShadow.opacity(0.35), radius: 10, x: 0, y: 6)
                Text("Added to your balance")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }

            // Glass stats card
            VStack(spacing: 14) {
                detailRow(title: "Receipt Total", value: String(format: "$%.2f", receiptTotal))
                detailRow(title: "Rate", value: "5 pts per dollar")
                detailRow(title: "Points Earned", value: "\(pointsEarned)")
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.modernCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Theme.darkGoldGradient, lineWidth: 2)
                    )
                    .shadow(color: Theme.cardShadow, radius: 14, x: 0, y: 6)
            )
            .padding(.horizontal, 24)

            // CTAs
            HStack(spacing: 12) {
                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("openRewards"), object: nil)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("View Rewards")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Theme.darkGoldGradient)
                            .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                    )
                }

                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("openOrder"), object: nil)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Order Now")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Theme.energyOrange, Theme.energyRed]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .shadow(color: Theme.energyOrange.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
                }
            }
            .padding(.horizontal, 24)

            // Auto-return note
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Theme.primaryGold)
                Text("Returning to home…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.modernSecondary)
            }
            .padding(.top, 4)
            .padding(.bottom, 36)

            Spacer(minLength: 0)
        }
        .onAppear {
            // Auto-dismiss after 2.5 seconds for smoother transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                shouldSwitchToHome = true
                NotificationCenter.default.post(name: .didEarnPoints, object: nil, userInfo: ["points": pointsEarned])
                onPointsEarned?(pointsEarned)
                withAnimation(.easeInOut(duration: 0.6)) {
                    showCongratulations = false
                    errorMessage = ""
                    showDumplingRain = false
                }
            }
        }
    }
    
    private var receiptUsedView: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                Text("Receipt Already Used")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("A receipt cannot be used more than once. +0 points")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                if let order = lastOrderNumber, let date = lastOrderDate {
                    Text("Order #: \(order)\nDate: \(date)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            Button("Return to Home") {
                shouldSwitchToHome = true
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.red))
            .padding(.bottom, 60)
        }
        .transition(.opacity)
    }
    
    private func instructionCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.modernCard)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.darkGoldGradient, lineWidth: 1))
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
        )
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
    
    private func switchToHomeTab() {
        // Since this is a tab-based app, we need to use a different approach
        // We'll post a notification that the main app can listen to
        NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
    }
    
    private func processReceiptImage(_ image: UIImage, liveTotalsConfirmed: Bool = false, onTotalsGateFail: (() -> Void)? = nil) {
        isProcessing = true
        errorMessage = ""
        scannedText = ""
        // Reset validation state for new scan
        receiptPassedValidation = false
        serverHasResponded = false
        interstitialTimedOut = false
        pendingPoints = 0
        pendingTotal = 0.0
        lastOrderNumber = nil
        lastOrderDate = nil
        interstitialTimeoutWorkItem?.cancel()
        interstitialTimeoutWorkItem = nil
        // Store image for potential retry
        lastCapturedImage = image
        let currentPoints = userVM.points

        // 45s failsafe: if the server never responds, dismiss camera and show an error.
        let timeoutItem = DispatchWorkItem {
            guard !self.serverHasResponded else { return }
            self.serverHasResponded = true
            self.interstitialTimedOut = true
            self.isProcessing = false
            self.showCamera = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.presentOutcome(.server)
            }
        }
        interstitialTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 45.0, execute: timeoutItem)

        // Preprocess (crop/perspective-correct) ONLY for receipt scanning to reduce distractions.
        preprocessReceiptImageForUpload(image) { processedImage in
            // Admin debug: save the exact image being sent (cropped or full) to camera roll.
            if self.userVM.saveScannedReceiptsToCameraRoll {
                saveScannedReceiptImageToCameraRoll(processedImage)
            }

            // Upload handler — shared by both the live-confirmed and totals-gate paths.
            let performUpload = {
                uploadReceiptImage(processedImage) { result in
                    DispatchQueue.main.async {
                    self.isProcessing = false
                    self.serverHasResponded = true
                    self.interstitialTimeoutWorkItem?.cancel()
                    self.interstitialTimeoutWorkItem = nil
                    // If 45s timeout already fired, we presented .server; skip present/post to avoid flash.
                    if self.interstitialTimedOut { return }
                    switch result {
                case .success(let json):
                    // Check if the response contains an error
                    if let errorMessage = json["error"] as? String {
                        let errorCode = json["errorCode"] as? String
                        let errorOutcome = mapErrorToOutcome(errorCode: errorCode, message: errorMessage)
                        self.errorMessage = errorMessage
                        // Dismiss camera sheet and present error after dismiss animation
                        self.showCamera = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.presentOutcome(errorOutcome)
                        }
                        return
                    }

                    // Server-authoritative submit-receipt response:
                    // { success: true, receipt: {orderNumber, orderTotal, orderDate, orderTime, ...}, pointsAwarded, ... }
                    if let success = json["success"] as? Bool, success == true,
                       let receipt = json["receipt"] as? [String: Any],
                       let orderNumberRaw = receipt["orderNumber"] as? String,
                       let orderTotal = receipt["orderTotal"] as? Double,
                       let orderDateRaw = receipt["orderDate"] as? String,
                       let pointsAwarded = json["pointsAwarded"] as? Int {

                        let orderNumber = orderNumberRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let orderDate = normalizeReceiptMonthDay(orderDateRaw)

                        self.scannedText = "Order #: \(orderNumber)\nDate: \(orderDate)\nTotal: $\(orderTotal)"
                        self.pendingTotal = orderTotal
                        self.pendingPoints = pointsAwarded
                        self.lastOrderNumber = orderNumber
                        self.lastOrderDate = orderDate

                        // Server already validated + awarded points atomically.
                        self.receiptTotal = self.pendingTotal
                        self.pointsEarned = self.pendingPoints
                        self.receiptPassedValidation = true

                        DebugLogger.debug("✅ Server awarded receipt points: \(self.pointsEarned), Total: \(self.receiptTotal)", category: "ReceiptScan")

                        // Dismiss camera sheet and present success after dismiss animation
                        self.showCamera = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.presentOutcome(.success(points: self.pointsEarned, total: self.receiptTotal))
                        }
                    } else {
                        self.errorMessage = "Unexpected server response. Please try again."
                        // Dismiss camera sheet and present error after dismiss animation
                        self.showCamera = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.presentOutcome(.server)
                        }
                    }
                case .failure(let error):
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                    let errorOutcome: ReceiptScanOutcome
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .dataNotAllowed:
                            errorOutcome = .network
                        default:
                            errorOutcome = .server
                        }
                    } else {
                        errorOutcome = .server
                    }
                    // Dismiss camera sheet and present error after dismiss animation
                    self.showCamera = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.presentOutcome(errorOutcome)
                    }
                }
                    }
                }
            }

            // Server handles totals validation with superior OCR.
            // Client-side gate removed -- it was blocking 90% of legitimate scans
            // due to unreliable on-device OCR on thermal receipt paper.
            performUpload()
        }
    }

    private func startComboGeneration() {
        guard !userVM.firstName.isEmpty else {
            comboState = .failed
            return
        }
        comboState = .loading
        let userName = userVM.firstName
        let dietaryPreferences = DietaryPreferences(
            likesSpicyFood: userVM.likesSpicyFood,
            dislikesSpicyFood: userVM.dislikesSpicyFood,
            hasPeanutAllergy: userVM.hasPeanutAllergy,
            isVegetarian: userVM.isVegetarian,
            hasLactoseIntolerance: userVM.hasLactoseIntolerance,
            doesntEatPork: userVM.doesntEatPork,
            tastePreferences: userVM.tastePreferences
        )
        let service = PersonalizedComboService()
        service.generatePersonalizedCombo(
            userName: userName,
            dietaryPreferences: dietaryPreferences,
            menuItems: menuVM.allMenuItems,
            previousRecommendations: nil
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    DebugLogger.debug("❌ Combo generation (receipt) failed: \(error)", category: "ReceiptScan")
                    self.comboState = .failed
                }
            },
            receiveValue: { combo in
                self.personalizedCombo = combo
                self.isComboReady = true
                self.comboState = .ready
                self.maybeShowComboResult()
            }
        )
        .store(in: &cancellables)
    }
    
    private func retryComboGeneration() {
        hasStartedComboGeneration = false
        isComboReady = false
        personalizedCombo = nil
        comboState = .loading
        hasStartedComboGeneration = true
        startComboGeneration()
    }

    private func maybeShowComboResult() {
        if isComboReady && presentedOutcome == nil {
            showComboResult = true
        }
    }

    private func presentOutcome(_ outcome: ReceiptScanOutcome) {
        triggerHaptic(for: outcome)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            presentedOutcome = outcome
        }
    }

    private func triggerHaptic(for outcome: ReceiptScanOutcome) {
        let generator = UINotificationFeedbackGenerator()
        switch outcome {
        case .success:
            generator.notificationOccurred(.success)
        case .duplicate, .mismatch, .suspicious:
            generator.notificationOccurred(.error)
        default:
            generator.notificationOccurred(.warning)
        }
    }

    private func mapErrorToOutcome(errorCode: String?, message: String) -> ReceiptScanOutcome {
        if let code = errorCode?.uppercased() {
            switch code {
            // Definitive outcomes based solely on errorCode
            case "DUPLICATE_RECEIPT":
                return .duplicate(orderNumber: lastOrderNumber, date: lastOrderDate)
            case "EXPIRED_48H":
                return .tooOld(date: lastOrderDate)
            case "FUTURE_DATE":
                return .tooOld(date: lastOrderDate) // Future date is effectively "can't scan now"
            case "NO_IMAGE":
                return .unreadable
            // Server/auth errors
            case "UNAUTHENTICATED", "USER_NOT_FOUND":
                return .server
            case "RATE_LIMITED":
                return .rateLimited
            case "DAILY_RECEIPT_LIMIT_REACHED":
                return .dailyLimitReached
            case "TOTAL_SECTION_NOT_VISIBLE":
                return .totalsNotVisible
            case "TOTAL_INCONSISTENT":
                return .mismatch
            case let c where c.hasPrefix("SERVER_"):
                return .server
            // For these codes, the message contains more specific info (e.g., "not Dumpling House", "tampered")
            // so we fall through to string-based matching below
            case "AI_VALIDATION_FAILED", "KEY_FIELDS_INVALID":
                break
            // Technical extraction/format failures → unreadable
            case "DATE_FORMAT_INVALID", "TIME_FORMAT_INVALID", "ORDER_NUMBER_INVALID", "TOTAL_INVALID",
                 "MISSING_FIELDS", "AI_JSON_EXTRACT_FAILED", "DOUBLE_PARSE_MISMATCH", "ORDER_NUMBER_SOURCE_INVALID":
                return .unreadable
            default:
                break
            }
        }
        // Fall back to string-based mapping for nuanced outcomes (notFromRestaurant, suspicious, etc.)
        return mapErrorMessageToOutcome(message)
    }

    private func mapErrorMessageToOutcome(_ message: String) -> ReceiptScanOutcome {
        let msg = message.lowercased()
        
        // 0) Totals section missing (fail closed to prevent guessed totals)
        if msg.contains("total section not visible") ||
           msg.contains("make sure all receipt text is visible") ||
           (msg.contains("include subtotal") && msg.contains("tax") && msg.contains("total")) ||
           (msg.contains("subtotal") && msg.contains("tax") && msg.contains("total") && msg.contains("not visible")) {
            return .totalsNotVisible
        }

        // 1) Restaurant mismatch (not from Dumpling House)
        if msg.contains("not from dumpling") ||
           msg.contains("not a dumpling house") ||
           msg.contains("wrong restaurant") ||
           ((msg.contains("dumpling house") || msg.contains("dumpling")) &&
            (msg.contains("invalid") || msg.contains("must be") || msg.contains("not from") || msg.contains("wrong"))) {
            return .notFromRestaurant
        }
        
        // 2) Suspicious / tampering (intentional manipulation)
        if msg.contains("tampered") ||
           msg.contains("photoshopped") ||
           msg.contains("edited") ||
           msg.contains("photo of a photo") ||
           msg.contains("photo of photo") ||
           msg.contains("screen photo") ||
           msg.contains("screenshot") ||
           msg.contains("digitally altered") ||
           msg.contains("brightened to hide") ||
           msg.contains("white-out") ||
           msg.contains("whiteout") ||
           msg.contains("scribbled") ||
           msg.contains("crossed out") ||
           msg.contains("written over") {
            return .suspicious
        }
        
        // 3) Expired / too old
        if msg.contains("too old") || msg.contains("expired") || msg.contains("outside the window") || msg.contains("48 hours") {
            return .tooOld(date: lastOrderDate)
        }
        
        // 4) Duplicate / already submitted
        if msg.contains("already submitted") ||
           msg.contains("already been processed") ||
           msg.contains("duplicate receipt") ||
           msg.contains("duplicate") {
            return .duplicate(orderNumber: lastOrderNumber, date: lastOrderDate)
        }
        
        // 5) Mismatch (validation discrepancy)
        if msg.contains("mismatch") || msg.contains("doesn't add up") || msg.contains("totals") {
            return .mismatch
        }
        
        // 6) Server errors
        if msg.contains("server") || msg.contains("internal") || msg.contains("500") {
            return .server
        }
        
        // 7) Unreadable / poor quality (catch-all for image issues)
        if msg.contains("unreadable") ||
           msg.contains("blurry") ||
           msg.contains("low confidence") ||
           msg.contains("could not extract") ||
           msg.contains("faded") ||
           msg.contains("unclear") ||
           msg.contains("poor image quality") ||
           msg.contains("clearer photo") ||
           msg.contains("no valid order number") ||
           msg.contains("invalid order number") ||
           msg.contains("invalid date") ||
           msg.contains("invalid time") ||
           msg.contains("numbers are covered") ||
           msg.contains("numbers are obstructed") ||
           msg.contains("obscured") ||
           msg.contains("key information") ||
           msg.contains("no image file") {
            return .unreadable
        }
        
        // Default to unreadable for unknown validation errors (not server - those would have "server" in message)
        return .unreadable
    }

    private func handlePrimaryAction(for outcome: ReceiptScanOutcome) {
        switch outcome {
        case .success:
            NotificationCenter.default.post(name: Notification.Name("openRewards"), object: nil)
            presentedOutcome = nil
        case .duplicate:
            NotificationCenter.default.post(name: Notification.Name("openReceiptHistory"), object: nil)
            presentedOutcome = nil
        case .network, .server:
            // Retry upload with last captured image
            if let image = lastCapturedImage {
                presentedOutcome = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processReceiptImage(image)
                }
            } else {
                // No image stored, just dismiss
                presentedOutcome = nil
            }
        case .totalsNotVisible:
            // Rescan: dismiss and reopen camera
            presentedOutcome = nil
            lastCapturedImage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkCameraPermission()
            }
        case .dailyLimitReached, .notFromRestaurant, .unreadable, .tooOld, .mismatch, .suspicious, .rateLimited:
            // Just dismiss (buttons now say "Got It")
            presentedOutcome = nil
        }
    }

    private func handleSecondaryAction(for outcome: ReceiptScanOutcome) {
        switch outcome {
        case .success:
            // Order Now -> open the order website
            presentedOutcome = nil
            NotificationCenter.default.post(name: Notification.Name("openOrder"), object: nil)
        case .network, .server:
            // For network/server errors, "Scan Another" allows retry with new image
            presentedOutcome = nil
            lastCapturedImage = nil // Clear stored image since user wants to scan new one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkCameraPermission()
            }
        default:
            // Scan Another - give a moment for dismiss animation
            presentedOutcome = nil
            lastCapturedImage = nil // Clear stored image
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkCameraPermission()
            }
        }
    }
    
    // Helper to extract MM-DD from a date string (ignoring year)
    private func extractMonthDay(from dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it's already in MM/DD format, convert to MM-DD for consistency
        if trimmed.contains("/") {
            let components = trimmed.components(separatedBy: "/")
            if components.count == 2 {
                return "\(components[0])-\(components[1])"
            }
        }
        
        // Try to match YYYY-MM-DD or MM/DD/YYYY or MM-DD-YYYY
        let patterns = [
            "^(\\d{4})-(\\d{2})-(\\d{2})$", // YYYY-MM-DD
            "^(\\d{2})/(\\d{2})/(\\d{4})$", // MM/DD/YYYY
            "^(\\d{2})-(\\d{2})-(\\d{4})$"  // MM-DD-YYYY
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                if pattern == patterns[0], match.numberOfRanges == 4 {
                    // YYYY-MM-DD
                    let mm = (trimmed as NSString).substring(with: match.range(at: 2))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 3))
                    return "\(mm)-\(dd)"
                } else if pattern == patterns[1], match.numberOfRanges == 4 {
                    // MM/DD/YYYY
                    let mm = (trimmed as NSString).substring(with: match.range(at: 1))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 2))
                    return "\(mm)-\(dd)"
                } else if pattern == patterns[2], match.numberOfRanges == 4 {
                    // MM-DD-YYYY
                    let mm = (trimmed as NSString).substring(with: match.range(at: 1))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 2))
                    return "\(mm)-\(dd)"
                }
            }
        }
        // If no match, return the original string
        return trimmed
    }
    
    // NOTE: Client-side points awarding was removed.
    // Receipt validation + dedupe + points awarding now happen server-side via POST /submit-receipt.
    
    private func checkCameraPermission() {
        errorMessage = ""
        scannedText = ""
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Guard: don't open camera if still processing
            guard !isProcessing else {
                DebugLogger.debug("⚠️ Camera open blocked - still processing", category: "ReceiptScan")
                return
            }
            showCamera = true
        case .notDetermined:
            presentCameraPermissionScreen(isDenied: false)
        case .denied, .restricted:
            presentCameraPermissionScreen(isDenied: true)
        @unknown default:
            presentCameraPermissionScreen(isDenied: true)
        }
    }

    private func presentCameraPermissionScreen(isDenied: Bool) {
        cameraPermissionDenied = isDenied
        showCameraPermissionScreen = true
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.showCameraPermissionScreen = false
                    // Guard: don't open camera if still processing
                    guard !self.isProcessing else {
                        DebugLogger.debug("⚠️ Camera open blocked - still processing", category: "ReceiptScan")
                        return
                    }
                    self.showCamera = true
                } else {
                    self.cameraPermissionDenied = true
                }
            }
        }
    }

    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // NOTE: Client-side duplicate tracking (usedReceipts) was removed.
    // Server-side duplicate prevention is enforced in POST /submit-receipt.

    // Normalize a month/day string for receipt keys and Firestore to MM/DD.
    // Accepts MM/DD, MM-DD, or strings containing a date with year.
    private func normalizeReceiptMonthDay(_ dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        // MM/DD or MM-DD
        let monthDayRegex = try? NSRegularExpression(pattern: "^(\\d{2})[/-](\\d{2})$")
        if let monthDayRegex,
           let match = monthDayRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 3 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 1))
            let dd = (trimmed as NSString).substring(with: match.range(at: 2))
            return "\(mm)/\(dd)"
        }

        // YYYY-MM-DD
        let ymdRegex = try? NSRegularExpression(pattern: "^(\\d{4})-(\\d{2})-(\\d{2})$")
        if let ymdRegex,
           let match = ymdRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 4 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 2))
            let dd = (trimmed as NSString).substring(with: match.range(at: 3))
            return "\(mm)/\(dd)"
        }

        // MM/DD/YYYY
        let mdySlashRegex = try? NSRegularExpression(pattern: "^(\\d{2})/(\\d{2})/(\\d{4})$")
        if let mdySlashRegex,
           let match = mdySlashRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 4 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 1))
            let dd = (trimmed as NSString).substring(with: match.range(at: 2))
            return "\(mm)/\(dd)"
        }

        // MM-DD-YYYY
        let mdyDashRegex = try? NSRegularExpression(pattern: "^(\\d{2})-(\\d{2})-(\\d{4})$")
        if let mdyDashRegex,
           let match = mdyDashRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 4 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 1))
            let dd = (trimmed as NSString).substring(with: match.range(at: 2))
            return "\(mm)/\(dd)"
        }

        // Fallback: if it contains dashes in the first 5 chars, convert just those.
        if trimmed.count >= 5 {
            let prefix = String(trimmed.prefix(5)).replacingOccurrences(of: "-", with: "/")
            if prefix.range(of: #"^\d{2}/\d{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }
        return trimmed
    }
}

// Minimal corner-glow overlay for receipt scanning (Option 1)
struct MinimalReceiptGuideOverlay: View {
    let frameSize: CGSize
    let cornerLength: CGFloat
    let cornerThickness: CGFloat
    let cornerRadius: CGFloat
    let maskOpacity: Double
    let showGlow: Bool
    let instructionTitle: String?
    let instructionSubtitle: String?

    init(
        frameSize: CGSize,
        cornerLength: CGFloat = 26,
        cornerThickness: CGFloat = 3,
        cornerRadius: CGFloat = 16,
        maskOpacity: Double = 0.28,
        showGlow: Bool = true,
        instructionTitle: String? = nil,
        instructionSubtitle: String? = nil
    ) {
        self.frameSize = frameSize
        self.cornerLength = cornerLength
        self.cornerThickness = cornerThickness
        self.cornerRadius = cornerRadius
        self.maskOpacity = maskOpacity
        self.showGlow = showGlow
        self.instructionTitle = instructionTitle
        self.instructionSubtitle = instructionSubtitle
    }

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let rectOrigin = CGPoint(
                x: (container.width - frameSize.width) / 2,
                y: (container.height - frameSize.height) / 2
            )
            let rect = CGRect(origin: rectOrigin, size: frameSize)
            let inset = max(1.0, cornerThickness) // keep a safe inset

            ZStack {
                // Subtle inner stroke for definition
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Corner guides (rounded caps), positioned inside the cutout
                Group {
                    // Top-left
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.minX + cornerRadius + cornerLength / 2,
                                  y: rect.minY + inset)
                        .zIndex(1)
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.minX + inset,
                                  y: rect.minY + cornerRadius + cornerLength / 2)
                        .zIndex(1)

                    // Top-right
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.maxX - cornerRadius - cornerLength / 2,
                                  y: rect.minY + inset)
                        .zIndex(1)
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.maxX - inset,
                                  y: rect.minY + cornerRadius + cornerLength / 2)
                        .zIndex(1)

                    // Bottom-left
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.minX + inset,
                                  y: rect.maxY - cornerRadius - cornerLength / 2)
                        .zIndex(1)
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.minX + cornerRadius + cornerLength / 2,
                                  y: rect.maxY - inset)
                        .zIndex(1)

                    // Bottom-right
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.maxX - inset,
                                  y: rect.maxY - cornerRadius - cornerLength / 2)
                        .zIndex(1)
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.maxX - cornerRadius - cornerLength / 2,
                                  y: rect.maxY - inset)
                        .zIndex(1)
                }

                // Instruction pill inside the cutout near the bottom
                if let instructionTitle = instructionTitle {
                    VStack(spacing: 6) {
                        Text(instructionTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        if let instructionSubtitle = instructionSubtitle, !instructionSubtitle.isEmpty {
                            Text(instructionSubtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .frame(maxWidth: rect.width - 48)
                    .position(x: rect.midX, y: rect.maxY - 44)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerLine(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.95))
            .frame(width: width, height: height)
            .shadow(color: showGlow ? Color.white.opacity(0.18) : Color.clear, radius: showGlow ? 3 : 0, x: 0, y: 0)
    }
}

// MARK: - Splash helpers
private func stepIcon(_ systemName: String, color: Color) -> some View {
    ZStack {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
        Image(systemName: systemName)
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .bold))
    }
}

private func stepText(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
        Text(subtitle)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }
}

// MARK: - Gold blob background (always-on, slow, gold-only)
private struct GoldBlobBackground: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Performance knobs
                let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                let blobCount = lowPower ? 3 : 5
                let baseOpacity: Double = lowPower ? 0.10 : 0.14
                let maxRadius = min(size.width, size.height) * 0.6
                for i in 0..<blobCount {
                    let fi = Double(i)
                    let speed = 0.02 + 0.01 * fi
                    let r = maxRadius * (0.48 + 0.08 * sin(t * speed + fi))
                    let cx = size.width * (0.5 + 0.35 * sin(t * speed * 0.6 + fi * 1.7))
                    let cy = size.height * (0.5 + 0.35 * cos(t * speed * 0.5 + fi * 1.3))
                    let center = CGPoint(x: cx, y: cy)
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    let path = Path(ellipseIn: rect)
                    let gradient = Gradient(colors: [
                        Theme.primaryGold.opacity(baseOpacity * 0.9),
                        Theme.deepGold.opacity(0.0)
                    ])
                    context.fill(path, with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r))
                }
            }
        }
        .opacity(1.0)
    }
}

struct CameraViewWithOverlay: View {
    @Binding var image: UIImage?
    var onImageCaptured: (UIImage?, Bool) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var cameraController: CameraController
    @State private var isCapturing = false
    @State private var cameraReady = false
    @State private var showPreparingOverlay = true
    @State private var overlayAppearedAt: Date = Date()
    @State private var showPostCaptureVideo = false
    
    init(image: Binding<UIImage?>, onImageCaptured: @escaping (UIImage?, Bool) -> Void) {
        self._image = image
        self.onImageCaptured = onImageCaptured
        _cameraController = StateObject(wrappedValue: CameraController())
    }

    // MARK: Top status helpers

    private func topStatusText(for phase: LiveScanPhase) -> String {
        switch phase {
        case .searching:  return "Looking for a receipt…"
        case .tracking:   return "Focusing on receipt…"
        case .locked, .capturing: return "Hold still — capturing!"
        }
    }

    private func topStatusIcon(for phase: LiveScanPhase) -> String {
        switch phase {
        case .searching:  return "doc.text.magnifyingglass"
        case .tracking:   return "viewfinder"
        case .locked, .capturing: return "camera.fill"
        }
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraController: cameraController)
                .ignoresSafeArea()
            
            // Preparing overlay (cream + text only; sparkles are in UnifiedSparkleOverlay)
            if showPreparingOverlay {
                ZStack {
                    Theme.modernBackground.ignoresSafeArea()
                        .opacity(cameraReady ? 0 : 1)
                    
                    VStack {
                        Spacer()
                        if !cameraReady {
                            Text("Preparing...")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.modernSecondary)
                                .transition(.opacity)
                        }
                        Spacer()
                    }
                    .opacity(cameraReady ? 0 : 1)
                }
                .onChange(of: cameraController.isSetup) { isSetup in
                    if isSetup {
                        let elapsed = Date().timeIntervalSince(overlayAppearedAt)
                        let minimumDisplay: TimeInterval = 1.2
                        let remainingDelay = max(0, minimumDisplay - elapsed)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                cameraReady = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                showPreparingOverlay = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    cameraController.isReceiptDetectionEnabled = true
                                }
                            }
                        }
                    }
                }
            }
            
            // Post-capture video overlay (fades in over camera)
            if showPostCaptureVideo {
                LoopingVideoLayer(videoName: "scandump", videoType: "mov")
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            // Error overlay
            if let errorMessage = cameraController.errorMessage {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            Text("Camera Error")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            VStack(spacing: 12) {
                                Button("Try Again") {
                                    cameraController.errorMessage = nil
                                    cameraController.checkPermissionAndSetup()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 16, weight: .semibold))
                                
                                Button("Cancel") {
                                    dismiss()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    )
            }
            
            // UI overlay (only show when camera is ready and not in post-capture video)
            if cameraController.isSetup && cameraController.errorMessage == nil && !showPostCaptureVideo {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Top section with cancel button
                        HStack {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20, weight: .medium))
                                    Text("Cancel")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.4))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.safeAreaInsets.top + 16)

                        // Top contextual status — tells the user what's happening
                        HStack(spacing: 8) {
                            Image(systemName: topStatusIcon(for: cameraController.liveScanPhase))
                                .font(.system(size: 14, weight: .semibold))
                            Text(topStatusText(for: cameraController.liveScanPhase))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.35))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        )
                        .id(cameraController.liveScanPhase)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: cameraController.liveScanPhase)
                        .padding(.top, 12)
                        
                        Spacer()
                        
                        // Configure a scan ROI for live detection (restrict search area to reduce "imaginary boxes").
                        // We keep this generous so holding the receipt up still works, but it avoids most background edges.
                        let roiInsetX: CGFloat = 28
                        let roiInsetY: CGFloat = 110
                        let roiLayerRect = CGRect(
                            x: roiInsetX,
                            y: roiInsetY,
                            width: max(1, geometry.size.width - roiInsetX * 2),
                            height: max(1, geometry.size.height - roiInsetY * 2)
                        )
                        Color.clear
                            .frame(width: 1, height: 1)
                            .onAppear {
                                cameraController.setLiveScanROI(fromLayerRect: roiLayerRect)
                            }
                            .onChange(of: geometry.size) { _ in
                                cameraController.setLiveScanROI(fromLayerRect: roiLayerRect)
                            }

                        // Center guide (only when we haven't detected a receipt yet)
                        if cameraController.detectedReceiptQuad == nil {
                            let topArea: CGFloat = geometry.safeAreaInsets.top + 80 // Cancel button area
                            let bottomArea: CGFloat = 120 // Status pill area
                            let availableHeight = geometry.size.height - topArea - bottomArea
                            let cutoutWidth = min(geometry.size.width * 0.75, 320)
                            let cutoutHeight = min(availableHeight, cutoutWidth * 1.9)

                            VStack(spacing: 16) {
                                Text("Finding receipt…")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.30))
                                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                    )

                                MinimalReceiptGuideOverlay(
                                    frameSize: CGSize(width: cutoutWidth, height: cutoutHeight),
                                    cornerLength: 28,
                                    cornerThickness: 3.5,
                                    cornerRadius: 18,
                                    maskOpacity: 0.20,
                                    showGlow: true,
                                    instructionTitle: nil,
                                    instructionSubtitle: nil
                                )
                                .frame(height: cutoutHeight)
                            }
                        }
                        
                        Spacer()
                        
                        // Bottom status (no manual capture button — auto-capture only)
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                if isCapturing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isCapturing ? "Capturing…" : cameraController.liveScanStatusText)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.35))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                            )

                            Text("Hold steady • Good lighting helps")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.22)))
                        }
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 40)
                    }
                }
            }

            // Glow outline around detected receipt (hide during post-capture video)
            if cameraController.isSetup && cameraController.errorMessage == nil && !showPostCaptureVideo,
               let quad = cameraController.detectedReceiptQuad {
                LiveReceiptGlowOverlay(
                    quad: quad,
                    previewLayer: cameraController.previewLayer,
                    phase: cameraController.liveScanPhase
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: cameraController.detectedReceiptQuad != nil)
            }

            // Unified sparkles (same set: rise → float → organize → scatter on capture)
            if cameraController.errorMessage == nil {
                GeometryReader { geo in
                    UnifiedSparkleOverlay(
                        containerSize: geo.size,
                        quad: showPreparingOverlay ? nil : cameraController.detectedReceiptQuad,
                        previewLayer: cameraController.previewLayer,
                        isPreparing: showPreparingOverlay,
                        phase: cameraController.liveScanPhase,
                        isCaptured: showPostCaptureVideo
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            cameraController.checkPermissionAndSetup()
        }
        .onDisappear {
            // Ensure the camera hardware is released immediately after leaving the sheet
            cameraController.stopSession()
        }
        .onReceive(cameraController.$shouldAutoCapture) { should in
            guard should else { return }
            guard !isCapturing else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isCapturing = true
            }
            cameraController.shouldAutoCapture = false
            cameraController.capturePhoto { capturedImage in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isCapturing = false
                }
                if let capturedImage = capturedImage {
                    image = capturedImage
                    // Capture this value before stopping the session
                    let totalsConfirmed = cameraController.liveTotalsConfirmed
                    // Fade in post-capture video and scatter sparkles
                    withAnimation(.easeInOut(duration: 0.6)) {
                        showPostCaptureVideo = true
                    }
                    // Stop the camera hardware (torch off, session released)
                    cameraController.stopSession()
                    // Notify parent to begin processing (but don't dismiss the sheet)
                    onImageCaptured(capturedImage, totalsConfirmed)
                }
            }
        }
        .onReceive(cameraController.$errorMessage) { errorMessage in
            if let errorMessage = errorMessage {
                DebugLogger.debug("📸 Camera error: \(errorMessage)", category: "ReceiptScan")
            }
        }
    }
}

// MARK: - Live auto-scan overlay

/// Describes the current phase of the live receipt scan.
/// Shared between `CameraController` and overlay views so the UI can react to phase changes.
enum LiveScanPhase: Equatable {
    case searching
    case tracking
    case locked
    case capturing
}

// Must not be `private`/`fileprivate` because it is used by `CameraController`'s @Published properties.
struct DetectedQuad: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let boundingBox: CGRect
    let confidence: Float
    let score: Double
}

/// Draws a multi-layered glow outline around the detected receipt quad.
/// Replaces the old dimming overlay so the camera feed stays fully visible,
/// which is less confusing for users. The glow color shifts based on scan phase:
/// white while tracking, green when locked / capturing.
private struct LiveReceiptGlowOverlay: View {
    let quad: DetectedQuad
    let previewLayer: AVCaptureVideoPreviewLayer
    let phase: LiveScanPhase

    private var glowColor: Color {
        switch phase {
        case .searching, .tracking:
            return Theme.primaryGold
        case .locked, .capturing:
            return .green
        }
    }

    /// True when the glow should pulse (pre-lock phases only).
    private var shouldPulse: Bool {
        phase == .searching || phase == .tracking
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Sine pulse: oscillates 0.20 … 0.40 over ~1.5s; holds steady once locked.
            let pulse = shouldPulse ? 0.30 + 0.10 * sin(t * 4.2) : 0.30

            Canvas { context, size in
                let quadPath = quadPathInLayerCoordinates()

                // Outer glow: wide, heavily blurred, pulsing opacity (amplified)
                context.drawLayer { ctx in
                    ctx.addFilter(.blur(radius: 14))
                    ctx.stroke(
                        quadPath,
                        with: .color(glowColor.opacity(pulse)),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                    )
                }

                // Mid glow: medium width, moderate blur (amplified)
                context.drawLayer { ctx in
                    ctx.addFilter(.blur(radius: 7))
                    ctx.stroke(
                        quadPath,
                        with: .color(glowColor.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                }

                // Inner crisp stroke
                context.stroke(
                    quadPath,
                    with: .color(glowColor.opacity(0.92)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    private func quadPathInLayerCoordinates() -> Path {
        func toLayer(_ p: CGPoint) -> CGPoint {
            // Vision normalized points are bottom-left origin; captureDevicePoint is top-left origin.
            let devicePoint = CGPoint(x: p.x, y: 1.0 - p.y)
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
        }

        let tl = toLayer(quad.topLeft)
        let tr = toLayer(quad.topRight)
        let br = toLayer(quad.bottomRight)
        let bl = toLayer(quad.bottomLeft)

        var path = Path()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.closeSubpath()
        return path
    }
}

// MARK: - Preparing sparkle overlay (rising sparkles during camera setup)

/// A sparkle that rises from the bottom of the screen during the "Preparing..." phase.
private enum PreparingSparkleMotionPhase {
    case launch
    case float
}

private struct RisingSparkle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var driftX: CGFloat           // slight horizontal wobble
    var driftY: CGFloat           // upward velocity (negative)
    var size: CGFloat
    var baseOpacity: Double
    var opacity: Double
    var blur: CGFloat
    var age: Double               // 0…1 normalised lifetime
    var wanderPhase: Double
    var wanderSpeed: Double
    var wanderAmplitude: CGFloat
    var motionPhase: PreparingSparkleMotionPhase
    var launchTicks: Int
    var targetY: CGFloat
}

/// Overlay that spawns gold sparkles rising from the bottom of the screen.
/// Used during the "Preparing..." phase before the camera is ready.
private struct PreparingSparkleOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sparkles: [RisingSparkle] = []
    @State private var tickCount: Int = 0

    private let maxSparkles = 18
    private let sparkleColor = Color(red: 0.85, green: 0.65, blue: 0.25)

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        for sparkle in sparkles {
                            // Bloom halo
                            let bloomSize = sparkle.size * 2.5
                            let bloomRect = CGRect(
                                x: sparkle.x - bloomSize / 2,
                                y: sparkle.y - bloomSize / 2,
                                width: bloomSize,
                                height: bloomSize
                            )
                            context.drawLayer { ctx in
                                ctx.addFilter(.blur(radius: sparkle.blur * 2.0))
                                ctx.fill(
                                    Path(ellipseIn: bloomRect),
                                    with: .color(sparkleColor.opacity(sparkle.opacity * 0.30))
                                )
                            }

                            // Main sparkle dot
                            let mainRect = CGRect(
                                x: sparkle.x - sparkle.size / 2,
                                y: sparkle.y - sparkle.size / 2,
                                width: sparkle.size,
                                height: sparkle.size
                            )
                            context.drawLayer { ctx in
                                ctx.addFilter(.blur(radius: sparkle.blur))
                                ctx.fill(
                                    Path(ellipseIn: mainRect),
                                    with: .color(sparkleColor.opacity(sparkle.opacity))
                                )
                            }
                        }
                    }
                    .onChange(of: timeline.date) { _ in
                        tickRising(containerSize: geo.size)
                    }
                }
            }
        }
    }

    private func tickRising(containerSize: CGSize) {
        tickCount += 1
        let w = max(1, containerSize.width)
        let h = max(1, containerSize.height)
        let centerBandMidY = h * 0.36
        let centerBandHalfHeight = h * 0.16

        // Advance existing sparkles
        sparkles = sparkles.compactMap { s in
            var s = s
            s.wanderPhase += 1.0 / 30.0

            switch s.motionPhase {
            case .launch:
                let wobbleX = sin(s.wanderPhase * s.wanderSpeed) * s.wanderAmplitude
                s.x += s.driftX + wobbleX * 0.25
                s.y += s.driftY
                s.launchTicks += 1
                s.age += 0.009

                // After a short upward launch, settle into gentle floating.
                if s.launchTicks >= 30 || s.y <= s.targetY {
                    s.motionPhase = .float
                    s.driftX = CGFloat.random(in: -0.20...0.20)
                    s.driftY = CGFloat.random(in: -0.12...0.12)
                    s.wanderSpeed = Double.random(in: 1.0...2.0)
                    s.wanderAmplitude = CGFloat.random(in: 0.6...1.6)
                }

            case .float:
                let wobbleX = sin(s.wanderPhase * s.wanderSpeed) * s.wanderAmplitude
                let wobbleY = cos(s.wanderPhase * s.wanderSpeed * 0.85) * s.wanderAmplitude * 0.45
                s.x += s.driftX + wobbleX * 0.20
                s.y += s.driftY + wobbleY * 0.15
                s.age += 0.004

                // Gently nudge toward the center band; no hard clamp so sparkles never form a line.
                let minY = centerBandMidY - centerBandHalfHeight
                let maxY = centerBandMidY + centerBandHalfHeight
                if s.y < minY {
                    s.driftY += 0.02
                } else if s.y > maxY {
                    s.driftY -= 0.02
                }
                s.driftY = min(0.18, max(-0.18, s.driftY))

                // Wrap X only; Y stays unclamped so positions stay naturally spread.
                if s.x < -20 { s.x = w + 10 }
                if s.x > w + 20 { s.x = -10 }
            }

            // Fade in quickly, then hold, then fade out near lifetime end.
            let fadeIn = min(1.0, s.age / 0.08)
            let fadeOutStart = 0.78
            let fadeOut: Double
            if s.age <= fadeOutStart {
                fadeOut = 1.0
            } else {
                fadeOut = max(0.0, 1.0 - ((s.age - fadeOutStart) / (1.0 - fadeOutStart)))
            }
            s.opacity = s.baseOpacity * fadeIn * fadeOut
            return s.age < 1.0 ? s : nil
        }

        // Maintain population — launch wave first, then lightly refill.
        let available = max(0, maxSparkles - sparkles.count)
        let spawnLimit = tickCount < 30 ? min(1, available) : min(2, available)
        var spawned = 0
        while sparkles.count < maxSparkles && spawned < spawnLimit {
            let baseOp = Double.random(in: 0.35...0.75)
            let targetY = CGFloat.random(in: h * 0.28...h * 0.50)
            let sparkle = RisingSparkle(
                x: CGFloat.random(in: 0...w),
                y: h + CGFloat.random(in: 10...40),
                driftX: CGFloat.random(in: -0.35...0.35),
                driftY: CGFloat.random(in: -11.0...(-7.2)),
                size: CGFloat.random(in: 5...13),
                baseOpacity: baseOp,
                opacity: 0,
                blur: CGFloat.random(in: 1.0...3.5),
                age: 0,
                wanderPhase: Double.random(in: 0...(.pi * 2)),
                wanderSpeed: Double.random(in: 1.5...3.0),
                wanderAmplitude: CGFloat.random(in: 0.8...2.2),
                motionPhase: .launch,
                launchTicks: 0,
                targetY: targetY
            )
            sparkles.append(sparkle)
            spawned += 1
        }
    }
}

// MARK: - Unified sparkle overlay (same set: rise → float everywhere → organize around receipt)

private enum UnifiedSparkleMode {
    case rising
    case floating
    case converging
    case edge
    case scattering
}

private struct UnifiedSparkle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var driftX: CGFloat
    var driftY: CGFloat
    var size: CGFloat
    var baseOpacity: Double
    var opacity: Double
    var blur: CGFloat
    var age: Double
    var mode: UnifiedSparkleMode
    var launchTicks: Int
    var riseTargetY: CGFloat
    var wanderPhase: Double
    var wanderSpeedX: Double
    var wanderSpeedY: Double
    var wanderAmplitudeX: CGFloat
    var wanderAmplitudeY: CGFloat
    var edgeDriftX: CGFloat
    var edgeDriftY: CGFloat
}

private struct UnifiedSparkleOverlay: View {
    let containerSize: CGSize
    let quad: DetectedQuad?
    let previewLayer: AVCaptureVideoPreviewLayer
    let isPreparing: Bool
    let phase: LiveScanPhase
    let isCaptured: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sparkles: [UnifiedSparkle] = []
    @State private var wasQuadPresent: Bool = false
    @State private var tickCount: Int = 0
    @State private var didTriggerScatter: Bool = false

    private let maxSparkles = 25
    private let lerpFactor: CGFloat = 0.10
    private let arrivalThreshold: CGFloat = 3.0

    private var effectiveMaxSparkles: Int {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 12 : maxSparkles
    }

    private var sparkleColor: Color {
        switch phase {
        case .searching, .tracking: return Color(red: 0.85, green: 0.65, blue: 0.25)
        case .locked, .capturing: return .green
        }
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    for sparkle in sparkles {
                        let bloomSize = sparkle.size * 2.5
                        let bloomRect = CGRect(x: sparkle.x - bloomSize/2, y: sparkle.y - bloomSize/2, width: bloomSize, height: bloomSize)
                        context.drawLayer { ctx in
                            ctx.addFilter(.blur(radius: sparkle.blur * 2.0))
                            ctx.fill(Path(ellipseIn: bloomRect), with: .color(sparkleColor.opacity(sparkle.opacity * 0.30)))
                        }
                        let mainRect = CGRect(x: sparkle.x - sparkle.size/2, y: sparkle.y - sparkle.size/2, width: sparkle.size, height: sparkle.size)
                        context.drawLayer { ctx in
                            ctx.addFilter(.blur(radius: sparkle.blur))
                            ctx.fill(Path(ellipseIn: mainRect), with: .color(sparkleColor.opacity(sparkle.opacity)))
                        }
                    }
                }
                .onChange(of: timeline.date) { _ in
                    tickUnified()
                }
            }
        }
    }

    private func tickUnified() {
        tickCount += 1
        let w = max(1, containerSize.width)
        let h = max(1, containerSize.height)
        let corners = quadCornersInLayerCoordinates()

        // Trigger scatter once on capture
        if isCaptured && !didTriggerScatter {
            didTriggerScatter = true
            transitionToScatter(w: w, h: h)
        }

        if !isPreparing && !isCaptured {
            let quadPresent = quad != nil
            if quadPresent && !wasQuadPresent, let c = corners {
                transitionToEdge(corners: c)
            } else if !quadPresent && wasQuadPresent {
                transitionToFloat()
            }
            wasQuadPresent = quadPresent
        }

        sparkles = sparkles.compactMap { s in
            var s = s
            s.wanderPhase += 1.0 / 30.0

            switch s.mode {
            case .rising:
                let wobbleX = sin(s.wanderPhase * s.wanderSpeedX) * s.wanderAmplitudeX
                s.x += s.driftX + wobbleX * 0.25
                s.y += s.driftY
                s.launchTicks += 1
                s.age += 0.009
                let fadeIn = min(1.0, s.age / 0.08)
                let fadeOut = max(0, 1.0 - s.age)
                s.opacity = s.baseOpacity * fadeIn * fadeOut
                if s.launchTicks >= 42 || s.y <= s.riseTargetY {
                    s.mode = .floating
                    s.driftX = CGFloat.random(in: -0.55...0.55)
                    s.driftY = CGFloat.random(in: -0.55...0.55)
                    s.wanderSpeedX = Double.random(in: 1.5...3.0)
                    s.wanderSpeedY = Double.random(in: 1.5...3.0)
                    s.wanderAmplitudeX = CGFloat.random(in: 0.8...2.2)
                    s.wanderAmplitudeY = CGFloat.random(in: 0.8...2.2)
                }

            case .floating:
                let wx = sin(s.wanderPhase * s.wanderSpeedX) * s.wanderAmplitudeX
                let wy = cos(s.wanderPhase * s.wanderSpeedY) * s.wanderAmplitudeY
                s.x += s.driftX + wx * 0.5
                s.y += s.driftY + wy * 0.5
                s.age += 0.008
                s.opacity = s.baseOpacity * max(0, 1.0 - s.age)
                if s.x < -20 { s.x = w + 10 }
                if s.x > w + 20 { s.x = -10 }
                if s.y < -20 { s.y = h + 10 }
                if s.y > h + 20 { s.y = -10 }

            case .converging:
                let dx = s.targetX - s.x
                let dy = s.targetY - s.y
                s.x += dx * lerpFactor
                s.y += dy * lerpFactor
                s.age += 0.012
                s.opacity = min(0.90, s.baseOpacity * (0.7 + 0.3 * min(1.0, s.age / 0.3)))
                if hypot(dx, dy) < arrivalThreshold {
                    s.mode = .edge
                    s.age = 0
                }

            case .edge:
                s.x += s.edgeDriftX
                s.y += s.edgeDriftY
                s.age += 0.025
                s.opacity = max(0, 0.90 * (1.0 - s.age))

            case .scattering:
                s.x += s.driftX
                s.y += s.driftY
                s.age += 0.028
                s.opacity = max(0, s.baseOpacity * (1.0 - s.age))
            }
            return s.age < 1.0 ? s : nil
        }

        // Don't spawn new sparkles when scattering — let them all fade out
        guard !isCaptured else { return }

        if isPreparing {
            let limit = tickCount < 30 ? 1 : 2
            for _ in 0..<limit where sparkles.count < effectiveMaxSparkles {
                sparkles.append(spawnRisingSparkle(w: w, h: h))
            }
        } else {
            while sparkles.count < effectiveMaxSparkles {
                if let s = spawnUnifiedSparkle(corners: corners, w: w, h: h) {
                    sparkles.append(s)
                } else { break }
            }
        }
    }

    private func transitionToScatter(w: CGFloat, h: CGFloat) {
        let cx = w / 2
        let cy = h / 2
        sparkles = sparkles.map { s in
            var s = s
            // Compute outward direction from screen center
            let dx = s.x - cx
            let dy = s.y - cy
            let dist = max(1, hypot(dx, dy))
            let nx = dx / dist
            let ny = dy / dist
            let speed = CGFloat.random(in: 3.0...6.0)
            s.driftX = nx * speed
            s.driftY = ny * speed
            s.mode = .scattering
            s.age = 0
            s.baseOpacity = s.opacity // preserve current brightness as starting point
            return s
        }
    }

    private func transitionToEdge(corners: [CGPoint]) {
        sparkles = sparkles.map { s in
            var s = s
            let target = randomPointOnEdge(corners: corners)
            s.targetX = target.x
            s.targetY = target.y
            s.mode = .converging
            let (nx, ny) = outwardNormal(at: target, corners: corners)
            let speed = CGFloat.random(in: 0.5...1.0)
            s.edgeDriftX = nx * speed
            s.edgeDriftY = ny * speed
            return s
        }
    }

    private func transitionToFloat() {
        let w = max(1, containerSize.width)
        let h = max(1, containerSize.height)
        sparkles = sparkles.map { s in
            var s = s
            s.targetX = CGFloat.random(in: 0...w)
            s.targetY = CGFloat.random(in: 0...h)
            s.mode = .floating
            s.driftX = CGFloat.random(in: -0.55...0.55)
            s.driftY = CGFloat.random(in: -0.55...0.55)
            s.age = max(0, s.age - 0.3)
            s.baseOpacity = Double.random(in: 0.3...0.7)
            return s
        }
    }

    private func spawnRisingSparkle(w: CGFloat, h: CGFloat) -> UnifiedSparkle {
        let baseOp = Double.random(in: 0.35...0.75)
        return UnifiedSparkle(
            x: CGFloat.random(in: 0...w),
            y: h + CGFloat.random(in: 10...40),
            targetX: 0, targetY: 0,
            driftX: CGFloat.random(in: -0.35...0.35),
            driftY: CGFloat.random(in: -12.5...(-9.0)),
            size: CGFloat.random(in: 5...13),
            baseOpacity: baseOp, opacity: 0, blur: CGFloat.random(in: 1.0...3.5),
            age: 0, mode: .rising, launchTicks: 0,
            riseTargetY: CGFloat.random(in: h * 0.12...h * 0.38),
            wanderPhase: Double.random(in: 0...(.pi * 2)),
            wanderSpeedX: Double.random(in: 1.5...3.0), wanderSpeedY: Double.random(in: 1.5...3.0),
            wanderAmplitudeX: CGFloat.random(in: 0.8...2.2), wanderAmplitudeY: CGFloat.random(in: 0.5...1.5),
            edgeDriftX: 0, edgeDriftY: 0
        )
    }

    private func spawnUnifiedSparkle(corners: [CGPoint]?, w: CGFloat, h: CGFloat) -> UnifiedSparkle? {
        if let c = corners, c.count == 4 {
            let target = randomPointOnEdge(corners: c)
            let (nx, ny) = outwardNormal(at: target, corners: c)
            let speed = CGFloat.random(in: 0.5...1.0)
            return UnifiedSparkle(
                x: target.x, y: target.y, targetX: target.x, targetY: target.y,
                driftX: 0, driftY: 0,
                size: CGFloat.random(in: 6...14),
                baseOpacity: 0.90, opacity: 0.90, blur: CGFloat.random(in: 1.5...4.0),
                age: 0, mode: .edge, launchTicks: 0, riseTargetY: 0,
                wanderPhase: 0, wanderSpeedX: 0, wanderSpeedY: 0, wanderAmplitudeX: 0, wanderAmplitudeY: 0,
                edgeDriftX: nx * speed, edgeDriftY: ny * speed
            )
        }
        let baseOp = Double.random(in: 0.3...0.7)
        return UnifiedSparkle(
            x: CGFloat.random(in: 0...w), y: CGFloat.random(in: 0...h),
            targetX: CGFloat.random(in: 0...w), targetY: CGFloat.random(in: 0...h),
            driftX: CGFloat.random(in: -0.55...0.55), driftY: CGFloat.random(in: -0.55...0.55),
            size: CGFloat.random(in: 5...12),
            baseOpacity: baseOp, opacity: baseOp, blur: CGFloat.random(in: 1.0...3.0),
            age: Double.random(in: 0...0.5), mode: .floating, launchTicks: 0, riseTargetY: 0,
            wanderPhase: Double.random(in: 0...(.pi * 2)),
            wanderSpeedX: Double.random(in: 1.5...3.0), wanderSpeedY: Double.random(in: 1.5...3.0),
            wanderAmplitudeX: CGFloat.random(in: 0.8...2.2), wanderAmplitudeY: CGFloat.random(in: 0.8...2.2),
            edgeDriftX: 0, edgeDriftY: 0
        )
    }

    private func randomPointOnEdge(corners: [CGPoint]) -> CGPoint {
        let edgeIdx = Int.random(in: 0..<4)
        let a = corners[edgeIdx], b = corners[(edgeIdx + 1) % 4]
        let t = CGFloat.random(in: 0.0...1.0)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func outwardNormal(at point: CGPoint, corners: [CGPoint]) -> (CGFloat, CGFloat) {
        let cx = corners.map(\.x).reduce(0, +) / 4
        let cy = corners.map(\.y).reduce(0, +) / 4
        var bestDist: CGFloat = .greatestFiniteMagnitude
        var bestNx: CGFloat = 0, bestNy: CGFloat = 0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let midX = (a.x + b.x) / 2, midY = (a.y + b.y) / 2
            let dist = hypot(point.x - midX, point.y - midY)
            if dist < bestDist {
                bestDist = dist
                let edgeDx = b.x - a.x, edgeDy = b.y - a.y
                let len = hypot(edgeDx, edgeDy)
                guard len > 0 else { continue }
                var nx = -edgeDy / len, ny = edgeDx / len
                if nx * (cx - point.x) + ny * (cy - point.y) > 0 { nx = -nx; ny = -ny }
                bestNx = nx; bestNy = ny
            }
        }
        return (bestNx, bestNy)
    }

    private func quadCornersInLayerCoordinates() -> [CGPoint]? {
        guard let quad = quad else { return nil }
        func toLayer(_ p: CGPoint) -> CGPoint {
            let devicePoint = CGPoint(x: p.x, y: 1.0 - p.y)
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
        }
        return [toLayer(quad.topLeft), toLayer(quad.topRight), toLayer(quad.bottomRight), toLayer(quad.bottomLeft)]
    }
}

// MARK: - Ambient sparkle system (unified free-float + edge convergence)

/// Sparkle behaviour mode. Transitions: `.floating` → `.converging` → `.edge` (when quad appears)
/// and `.edge`/`.converging` → `.floating` (when quad disappears).
private enum SparkleMode {
    case floating    // drifting freely across the camera frame
    case converging  // lerping toward a target point on the quad edge
    case edge        // arrived on edge, drifting outward
}

private struct AmbientSparkle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var driftX: CGFloat           // base drift velocity (float mode)
    var driftY: CGFloat
    var size: CGFloat             // base diameter
    var baseOpacity: Double       // starting opacity for the current mode
    var opacity: Double           // current rendered opacity
    var blur: CGFloat
    var mode: SparkleMode
    var age: Double               // 0…1 normalised lifetime
    // Sinusoidal wandering (float mode)
    var wanderPhase: Double
    var wanderSpeedX: Double
    var wanderSpeedY: Double
    var wanderAmplitudeX: CGFloat
    var wanderAmplitudeY: CGFloat
    // Outward drift once on quad edge
    var edgeDriftX: CGFloat
    var edgeDriftY: CGFloat
}

/// A single overlay that renders gold sparkles in two modes:
/// 1. **Free-floating** – sparkles drift lazily across the entire camera frame (no receipt detected).
/// 2. **Edge-aligned** – sparkles smoothly converge onto the detected receipt quad edges and emit outward.
/// The transition between modes uses per-tick linear interpolation for a fluid, organic feel.
private struct AmbientSparkleOverlay: View {
    let quad: DetectedQuad?
    let previewLayer: AVCaptureVideoPreviewLayer
    let containerSize: CGSize
    let phase: LiveScanPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sparkles: [AmbientSparkle] = []
    @State private var wasQuadPresent: Bool = false

    private let maxSparkles = 25
    /// Each tick the sparkle moves 10 % of the remaining distance toward its target.
    private let lerpFactor: CGFloat = 0.10
    /// Distance below which a converging sparkle snaps to `.edge` mode.
    private let arrivalThreshold: CGFloat = 3.0

    private var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    private var effectiveMaxSparkles: Int {
        isLowPower ? 12 : maxSparkles
    }
    private var effectiveMaxBlur: CGFloat {
        isLowPower ? 2.5 : 4.0
    }

    /// Sparkle color follows the same phase logic as the glow outline:
    /// gold while searching/tracking, green when locked/capturing.
    private var sparkleColor: Color {
        switch phase {
        case .searching, .tracking:
            return Color(red: 0.85, green: 0.65, blue: 0.25)
        case .locked, .capturing:
            return .green
        }
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    for sparkle in sparkles {
                        // --- Bloom halo (larger, softer, behind main dot) ---
                        let bloomSize = sparkle.size * 2.5
                        let bloomRect = CGRect(
                            x: sparkle.x - bloomSize / 2,
                            y: sparkle.y - bloomSize / 2,
                            width: bloomSize,
                            height: bloomSize
                        )
                        context.drawLayer { ctx in
                            ctx.addFilter(.blur(radius: sparkle.blur * 2.0))
                            ctx.fill(
                                Path(ellipseIn: bloomRect),
                                with: .color(sparkleColor.opacity(sparkle.opacity * 0.30))
                            )
                        }

                        // --- Main sparkle ---
                        let mainRect = CGRect(
                            x: sparkle.x - sparkle.size / 2,
                            y: sparkle.y - sparkle.size / 2,
                            width: sparkle.size,
                            height: sparkle.size
                        )
                        context.drawLayer { ctx in
                            ctx.addFilter(.blur(radius: sparkle.blur))
                            ctx.fill(
                                Path(ellipseIn: mainRect),
                                with: .color(sparkleColor.opacity(sparkle.opacity))
                            )
                        }
                    }
                }
                .onChange(of: timeline.date) { _ in
                    tick()
                }
            }
        }
    }

    // MARK: - Tick (runs every frame, ~30 fps)

    private func tick() {
        let quadPresent = quad != nil
        let corners = quadPresent ? quadCornersInLayerCoordinates() : nil

        // --- Detect phase transition ---
        if quadPresent && !wasQuadPresent, let c = corners {
            transitionToEdge(corners: c)
        } else if !quadPresent && wasQuadPresent {
            transitionToFloat()
        }
        wasQuadPresent = quadPresent

        // --- Advance every sparkle ---
        sparkles = sparkles.compactMap { s in
            var s = s
            switch s.mode {
            case .floating:
                s.wanderPhase += 1.0 / 30.0
                let wx = sin(s.wanderPhase * s.wanderSpeedX) * s.wanderAmplitudeX
                let wy = cos(s.wanderPhase * s.wanderSpeedY) * s.wanderAmplitudeY
                s.x += s.driftX + wx * 0.3
                s.y += s.driftY + wy * 0.3

                s.age += 0.008           // ~125 ticks ≈ ~4 s lifetime
                s.opacity = s.baseOpacity * max(0, 1.0 - s.age)

                // Wrap around screen edges so sparkles never disappear abruptly
                let w = max(1, containerSize.width)
                let h = max(1, containerSize.height)
                if s.x < -20 { s.x = w + 10 }
                if s.x > w + 20 { s.x = -10 }
                if s.y < -20 { s.y = h + 10 }
                if s.y > h + 20 { s.y = -10 }

            case .converging:
                let dx = s.targetX - s.x
                let dy = s.targetY - s.y
                s.x += dx * lerpFactor
                s.y += dy * lerpFactor

                s.age += 0.012
                // Brighten as they approach their target
                s.opacity = min(0.90, s.baseOpacity * (0.7 + 0.3 * min(1.0, s.age / 0.3)))

                if hypot(dx, dy) < arrivalThreshold {
                    s.mode = .edge
                    s.age = 0             // reset for edge lifetime
                }

            case .edge:
                s.x += s.edgeDriftX
                s.y += s.edgeDriftY
                s.age += 0.025           // ~40 ticks ≈ ~1.3 s
                s.opacity = max(0, 0.90 * (1.0 - s.age))
            }
            return s.age < 1.0 ? s : nil
        }

        // --- Maintain sparkle population ---
        while sparkles.count < effectiveMaxSparkles {
            if let s = spawnSparkle(quadCorners: corners) {
                sparkles.append(s)
            } else {
                break
            }
        }
    }

    // MARK: - Phase transitions

    /// Quad just appeared – redirect every sparkle toward a random point on the quad edges.
    private func transitionToEdge(corners: [CGPoint]) {
        sparkles = sparkles.map { s in
            var s = s
            let target = randomPointOnEdge(corners: corners)
            s.targetX = target.x
            s.targetY = target.y
            s.mode = .converging
            let (nx, ny) = outwardNormal(at: target, corners: corners)
            let speed = CGFloat.random(in: 0.5...1.0)
            s.edgeDriftX = nx * speed
            s.edgeDriftY = ny * speed
            return s
        }
    }

    /// Quad disappeared – return every sparkle to free-float wandering.
    private func transitionToFloat() {
        let w = max(1, containerSize.width)
        let h = max(1, containerSize.height)
        sparkles = sparkles.map { s in
            var s = s
            s.targetX = CGFloat.random(in: 0...w)
            s.targetY = CGFloat.random(in: 0...h)
            s.mode = .floating
            s.driftX = CGFloat.random(in: -0.3...0.3)
            s.driftY = CGFloat.random(in: -0.3...0.3)
            s.age = max(0, s.age - 0.3) // pull back age so they don't die immediately
            s.baseOpacity = Double.random(in: 0.3...0.7)
            return s
        }
    }

    // MARK: - Spawning

    private func spawnSparkle(quadCorners: [CGPoint]?) -> AmbientSparkle? {
        if let corners = quadCorners, corners.count == 4 {
            return spawnEdgeSparkle(corners: corners)
        } else {
            return spawnFloatingSparkle()
        }
    }

    private func spawnFloatingSparkle() -> AmbientSparkle {
        let w = max(1, containerSize.width)
        let h = max(1, containerSize.height)
        let baseOp = Double.random(in: 0.3...0.7)
        return AmbientSparkle(
            x: CGFloat.random(in: 0...w),
            y: CGFloat.random(in: 0...h),
            targetX: CGFloat.random(in: 0...w),
            targetY: CGFloat.random(in: 0...h),
            driftX: CGFloat.random(in: -0.3...0.3),
            driftY: CGFloat.random(in: -0.3...0.3),
            size: CGFloat.random(in: 5...12),
            baseOpacity: baseOp,
            opacity: baseOp,
            blur: CGFloat.random(in: 1.0...3.0),
            mode: .floating,
            age: Double.random(in: 0...0.5),           // stagger ages for visual variety
            wanderPhase: Double.random(in: 0...(.pi * 2)),
            wanderSpeedX: Double.random(in: 1.5...3.0),
            wanderSpeedY: Double.random(in: 1.5...3.0),
            wanderAmplitudeX: CGFloat.random(in: 0.5...1.5),
            wanderAmplitudeY: CGFloat.random(in: 0.5...1.5),
            edgeDriftX: 0,
            edgeDriftY: 0
        )
    }

    private func spawnEdgeSparkle(corners: [CGPoint]) -> AmbientSparkle? {
        guard corners.count == 4 else { return nil }
        let target = randomPointOnEdge(corners: corners)
        let (nx, ny) = outwardNormal(at: target, corners: corners)
        let speed = CGFloat.random(in: 0.5...1.0)
        return AmbientSparkle(
            x: target.x,
            y: target.y,
            targetX: target.x,
            targetY: target.y,
            driftX: 0,
            driftY: 0,
            size: CGFloat.random(in: 6...14),
            baseOpacity: 0.90,
            opacity: 0.90,
            blur: CGFloat.random(in: 1.5...effectiveMaxBlur),
            mode: .edge,
            age: 0,
            wanderPhase: 0,
            wanderSpeedX: 0,
            wanderSpeedY: 0,
            wanderAmplitudeX: 0,
            wanderAmplitudeY: 0,
            edgeDriftX: nx * speed,
            edgeDriftY: ny * speed
        )
    }

    // MARK: - Geometry helpers

    /// Pick a random point along one of the four quad edges.
    private func randomPointOnEdge(corners: [CGPoint]) -> CGPoint {
        let edgeIdx = Int.random(in: 0..<4)
        let a = corners[edgeIdx]
        let b = corners[(edgeIdx + 1) % 4]
        let t = CGFloat.random(in: 0.0...1.0)
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Compute the outward-facing unit normal at a point near the quad edges.
    private func outwardNormal(at point: CGPoint, corners: [CGPoint]) -> (CGFloat, CGFloat) {
        let cx = corners.map(\.x).reduce(0, +) / 4
        let cy = corners.map(\.y).reduce(0, +) / 4
        var bestDist: CGFloat = .greatestFiniteMagnitude
        var bestNx: CGFloat = 0
        var bestNy: CGFloat = 0

        for i in 0..<4 {
            let a = corners[i]
            let b = corners[(i + 1) % 4]
            let midX = (a.x + b.x) / 2
            let midY = (a.y + b.y) / 2
            let dist = hypot(point.x - midX, point.y - midY)
            if dist < bestDist {
                bestDist = dist
                let edgeDx = b.x - a.x
                let edgeDy = b.y - a.y
                let len = hypot(edgeDx, edgeDy)
                guard len > 0 else { continue }
                var nx = -edgeDy / len
                var ny =  edgeDx / len
                // Flip if the normal points inward (toward center)
                if nx * (cx - point.x) + ny * (cy - point.y) > 0 {
                    nx = -nx
                    ny = -ny
                }
                bestNx = nx
                bestNy = ny
            }
        }
        return (bestNx, bestNy)
    }

    private func quadCornersInLayerCoordinates() -> [CGPoint]? {
        guard let quad = quad else { return nil }
        func toLayer(_ p: CGPoint) -> CGPoint {
            let devicePoint = CGPoint(x: p.x, y: 1.0 - p.y)
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
        }
        return [toLayer(quad.topLeft), toLayer(quad.topRight),
                toLayer(quad.bottomRight), toLayer(quad.bottomLeft)]
    }
}

// Host view that updates the preview layer in layoutSubviews so the layer always gets valid bounds
private class CameraPreviewHostView: UIView {
    weak var cameraController: CameraController?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let controller = cameraController,
              let preview = controller.previewLayer else { return }
        if preview.superlayer == nil {
            preview.videoGravity = .resizeAspectFill
            layer.addSublayer(preview)
        }
        guard bounds.width > 0, bounds.height > 0 else { return }
        if preview.frame != bounds {
            preview.frame = bounds
        }
        if let connection = preview.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

// Camera preview view
struct CameraPreviewView: UIViewRepresentable {
    let cameraController: CameraController
    
    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewHostView()
        view.backgroundColor = .black
        view.cameraController = cameraController
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let host = uiView as? CameraPreviewHostView else { return }
        host.cameraController = cameraController
        host.setNeedsLayout()
        host.layoutIfNeeded()
    }
}

// MARK: - Looping Video Layer (post-capture interstitial)

private class LoopingVideoHostView: UIView {
    var playerLayer: AVPlayerLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        playerLayer?.frame = bounds
    }
}

private struct LoopingVideoLayer: UIViewRepresentable {
    let videoName: String
    let videoType: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let host = LoopingVideoHostView()
        host.backgroundColor = .black

        // Ambient audio to avoid AirPods auto-connect
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        guard let path = Bundle.main.path(forResource: videoName, ofType: videoType) else { return host }
        let url = URL(fileURLWithPath: path)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        host.layer.addSublayer(layer)
        host.playerLayer = layer

        context.coordinator.player = player
        context.coordinator.playerItem = item

        // Loop on end
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.didReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        player.play()
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let host = uiView as? LoopingVideoHostView else { return }
        host.setNeedsLayout()
    }

    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerItem: AVPlayerItem?

        @objc func didReachEnd() {
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }

        deinit {
            if let item = playerItem {
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            }
            player?.pause()
            player = nil
        }
    }
}

// Camera controller
class CameraController: NSObject, ObservableObject {
    @Published var isSetup = false
    /// Stops the capture session if it is currently running and resets setup flag.
    /// Calling this proactively ensures the camera hardware is released as soon as
    /// the scanning view disappears instead of waiting for deinitialization.
    func stopSession() {
        setTorch(on: false)
        torchLatchedOn = false
        // Reset exposure bias to default
        if let device = cameraDevice, device.isExposureModeSupported(.autoExpose) {
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(0) { _ in }
                device.unlockForConfiguration()
            } catch {
                // Ignore errors when stopping
            }
        }
        currentExposureBias = 0
        isReceiptDetectionEnabled = false
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        // Note: Don't reset isSetup flag here - let it be reset when setupCamera is called again
    }
    @Published var errorMessage: String?
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    var previewLayer: AVCaptureVideoPreviewLayer!
    var completionHandler: ((UIImage?) -> Void)?
    private var cameraDevice: AVCaptureDevice?

    // Live auto-scan state
    @Published var detectedReceiptQuad: DetectedQuad? = nil
    @Published var shouldAutoCapture: Bool = false
    @Published var liveScanStatusText: String = "Finding receipt…"
    var isAutoScanEnabled: Bool = true
    var autoTorchEnabled: Bool = true
    var isReceiptDetectionEnabled: Bool = false

    private let videoQueue = DispatchQueue(label: "camera.video.frames.queue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "camera.vision.queue", qos: .userInitiated)
    private var lastVisionAt: CFTimeInterval = 0
    private var isAnalyzing: Bool = false

    // Live ROI in Vision normalized coordinates (origin bottom-left).
    private var liveScanROI: CGRect? = nil

    // Tracking / smoothing / hysteresis
    private var trackedQuadRaw: DetectedQuad? = nil
    private var smoothedQuad: DetectedQuad? = nil
    private var stabilityScore: Int = 0
    private var hasTriggeredAutoCapture: Bool = false
    private var lastCandidateAt: CFTimeInterval = 0
    private var lastGoodQuadAt: CFTimeInterval = 0
    private let quadHoldGraceSeconds: CFTimeInterval = 0.85
    private let lockDelaySeconds: CFTimeInterval = 1.0
    private var lockedQuad: DetectedQuad? = nil
    private var statusCandidateText: String? = nil
    private var statusCandidateSince: CFTimeInterval = 0
    private let statusHysteresisSeconds: CFTimeInterval = 0.8
    
    // Stuck detection
    private var trackedQuadStartTime: CFTimeInterval = 0
    private var trackedQuadBestStability: Int = 0
    private let stuckDetectionTimeout: CFTimeInterval = 3.5

    // Auto torch (flashlight) during scanning
    private var lastTorchEvalAt: CFTimeInterval = 0
    private var lastTorchChangeAt: CFTimeInterval = 0
    private var torchDesiredOn: Bool = false
    private var torchLatchedOn: Bool = false
    private let torchEvalInterval: CFTimeInterval = 0.35
    private let torchMinToggleInterval: CFTimeInterval = 0.9
    private let lowLightOnThreshold: Double = 0.20  // 0..1 (lower = darker)
    private let lowLightOffThreshold: Double = 0.28 // hysteresis
    
    // Bright/low-contrast handling + preprocessing heuristics
    private var lowContrastStreak: Int = 0
    private var noCandidateStreak: Int = 0
    private let brightLowContrastThreshold: Double = 0.58
    private let lowContrastStdThreshold: Double = 0.09
    private let preprocessStreakThreshold: Int = 2
    private let fallbackStreakThreshold: Int = 3
    
    // Exposure bias tuning for bright, low-contrast scenes
    private var lastExposureBiasUpdateAt: CFTimeInterval = 0
    private var currentExposureBias: Float = 0
    private let exposureBiasUpdateInterval: CFTimeInterval = 0.6
    private let lowContrastExposureBias: Float = -0.45

    // Pre-capture totals OCR hint (throttled, low-res check)
    private var lastFastTotalsCheckAt: CFTimeInterval = 0
    private var lastTotalsCheckAt: CFTimeInterval = 0
    private var totalsHintCandidate: Bool = false
    private var totalsHintPassed: Bool = false
    private var lastFastTotalsHintResult: Bool? = nil
    private let fastTotalsCheckInterval: CFTimeInterval = 0.22 // fast hint (~4.5 fps)
    private let totalsCheckInterval: CFTimeInterval = 0.30 // full hint (~3.3 fps)
    private let ocrQueue = DispatchQueue(label: "camera.ocr.totals.queue", qos: .utility)
    private var lastCaptureBlockedLogAt: CFTimeInterval = 0

    /// Timestamp when auto-capture was first deferred because totals OCR hadn't confirmed yet.
    /// Reset when phase returns to `.searching` or camera is set up fresh.
    private var captureHeldForTotalsAt: CFTimeInterval = 0
    private let maxTotalsWaitSeconds: CFTimeInterval = 2.5

    // Uses file-level LiveScanPhase enum (shared with overlay views).
    private var phase: LiveScanPhase = .searching
    /// Published mirror of `phase` so SwiftUI views can react to scan-phase changes.
    @Published var liveScanPhase: LiveScanPhase = .searching

    /// Updates both the internal `phase` and the `@Published liveScanPhase` (main-thread safe).
    private func setPhase(_ newPhase: LiveScanPhase) {
        self.phase = newPhase
        if Thread.isMainThread {
            self.liveScanPhase = newPhase
        } else {
            DispatchQueue.main.async {
                self.liveScanPhase = newPhase
            }
        }
    }

    /// Whether the live-frame OCR confirmed totals keywords (and optionally amounts) are visible.
    /// Used to bypass the post-capture totals gate when the live scan already confirmed.
    var liveTotalsConfirmed: Bool {
        totalsHintPassed || totalsHintCandidate
    }

    func setLiveScanROI(fromLayerRect layerRect: CGRect) {
        // Convert from preview-layer coordinates -> AVFoundation normalized (top-left origin),
        // then convert to Vision normalized (bottom-left origin).
        let avRect = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        let visionRect = CGRect(
            x: avRect.origin.x,
            y: max(0, 1.0 - avRect.origin.y - avRect.size.height),
            width: avRect.size.width,
            height: avRect.size.height
        )
        // Clamp
        let clamped = visionRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        liveScanROI = clamped.isNull ? nil : clamped
    }
    
    override init() {
        super.init()
        setupPreviewLayer()
    }
    
    func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = UIColor.black.cgColor
    }
    
    func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.errorMessage = "Camera access denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access denied. Please enable in Settings."
            }
        @unknown default:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access not available"
            }
        }
    }
    
    func setupCamera() {
        // Reset setup flag and clear error
        DispatchQueue.main.async {
            self.isSetup = false
            self.errorMessage = nil
        }
        
        // Reset auto-scan state for clean start
        setPhase(.searching)
        stabilityScore = 0
        hasTriggeredAutoCapture = false
        totalsHintCandidate = false
        totalsHintPassed = false
        lastFastTotalsHintResult = nil
        lastFastTotalsCheckAt = 0
        lastTotalsCheckAt = 0
        lastCaptureBlockedLogAt = 0
        captureHeldForTotalsAt = 0
        trackedQuadRaw = nil
        smoothedQuad = nil
        lockedQuad = nil
        statusCandidateText = nil
        statusCandidateSince = 0
        trackedQuadStartTime = 0
        trackedQuadBestStability = 0
        lowContrastStreak = 0
        noCandidateStreak = 0
        currentExposureBias = 0
        lastExposureBiasUpdateAt = 0
        
        // Stop any existing session
        if captureSession.isRunning {
            setTorch(on: false)
            torchLatchedOn = false
            captureSession.stopRunning()
        }
        
        // Remove existing inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async {
                self.errorMessage = "Camera not available"
            }
            return
        }
        self.cameraDevice = camera
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add camera input"
                }
                return
            }
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add photo output"
                }
                return
            }

            // Video output for live auto-scan (frames → Vision)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            } else {
                DebugLogger.debug("⚠️ Cannot add video output; live auto-scan disabled", category: "ReceiptScan")
            }

            // Try to keep output orientation portrait for preview; Vision uses explicit orientation below.
            if let conn = videoOutput.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            
            // Start the session on a background queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                DispatchQueue.main.async {
                    self?.isSetup = true
                    DebugLogger.debug("📸 Camera setup completed successfully", category: "ReceiptScan")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Camera setup error: \(error.localizedDescription)"
            }
            DebugLogger.debug("📸 Camera setup error: \(error)", category: "ReceiptScan")
        }
    }

    private func applyStatusText(_ text: String, force: Bool = false) {
        if force {
            liveScanStatusText = text
            statusCandidateText = nil
            return
        }
        if text == liveScanStatusText {
            statusCandidateText = nil
            return
        }
        let now = CACurrentMediaTime()
        if statusCandidateText != text {
            statusCandidateText = text
            statusCandidateSince = now
            return
        }
        if now - statusCandidateSince >= statusHysteresisSeconds {
            liveScanStatusText = text
            statusCandidateText = nil
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard captureSession.isRunning else {
            DebugLogger.debug("📸 Camera session not running", category: "ReceiptScan")
            completion(nil)
            return
        }
        
        completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        DispatchQueue.main.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    deinit {
        setTorch(on: false)
        torchLatchedOn = false
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func setTorch(on: Bool) {
        guard autoTorchEnabled else { return }
        guard let device = cameraDevice, device.hasTorch else { return }

        let now = CACurrentMediaTime()
        if now - lastTorchChangeAt < torchMinToggleInterval { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if on {
                guard device.isTorchModeSupported(.on) else { return }
                let level = min(0.55, AVCaptureDevice.maxAvailableTorchLevel)
                try device.setTorchModeOn(level: level)
            } else {
                guard device.isTorchModeSupported(.off) else { return }
                device.torchMode = .off
            }

            lastTorchChangeAt = now
        } catch {
            DebugLogger.debug("⚠️ Torch config failed: \(error.localizedDescription)", category: "ReceiptScan")
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DebugLogger.debug("Photo capture error: \(error)", category: "ReceiptScan")
            completionHandler?(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completionHandler?(nil)
            return
        }
        
        completionHandler?(image)
    }
}

// MARK: - Live auto-scan (video frames → Vision)

extension CameraController {
    /// Ultra-fast, low-fidelity hint that totals text is likely present.
    /// Used to unlock the heavier totals check sooner.
    private func checkFastTotalsHintOnLiveFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Bool) -> Void) {
        ocrQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            let scale: CGFloat = 0.60 // prioritize OCR reliability so text gate can unlock capture
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaledImage = ciImage.transformed(by: transform)

            // Run fast OCR on the full frame so either header ("Dumpling House")
            // or totals text can unlock capture.
            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                completion(false)
                return
            }

            let hasTotalsHint = fastTotalsHintFromImage(cgImage, preferredOrientation: orientation)
            completion(hasTotalsHint)
        }
    }

    /// Fast, throttled OCR check on live frame to detect totals section before auto-capture.
    /// Uses downscaled image and bottom region only for speed.
    private func checkTotalsHintOnLiveFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Bool) -> Void) {
        ocrQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            
            // Convert pixel buffer to CGImage (downscaled for speed)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            let scale: CGFloat = 0.5 // Downscale to 50% for speed
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaledImage = ciImage.transformed(by: transform)
            
            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                completion(false)
                return
            }
            
            // Create UIImage with proper orientation
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation(from: orientation))
            
            // Check totals using existing logic (bottom 65% region)
            let hasTotals = receiptHasSubtotalTaxTotalSync(uiImage)
            completion(hasTotals)
        }
    }
    
    /// Convert Vision orientation to UIImage orientation
    private func imageOrientation(from visionOrientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch visionOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Very fast keyword-only OCR hint (no amounts required).
    /// Tries a small orientation fallback set because live buffers can report different
    /// orientation metadata across devices/camera pipelines.
    private func fastTotalsHintFromImage(_ cgImage: CGImage, preferredOrientation: CGImagePropertyOrientation) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.010
        request.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)

        func hasReceiptSignal(for orientation: CGImagePropertyOrientation) -> Bool {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return false
            }

            let strings = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = strings.joined(separator: " ").lowercased()
            let hasTotalsKeyword =
                text.contains("total") ||
                text.contains("subtotal") ||
                text.contains("sub total") ||
                text.contains("tax") ||
                text.contains("amount due")
            // Use a partial root to handle common OCR misses like "dumplng"/"dumplingh".
            let hasRestaurantKeyword = text.contains("dumpl")
            return hasTotalsKeyword || hasRestaurantKeyword
        }

        let orientations: [CGImagePropertyOrientation] = [preferredOrientation, .up, .right, .left]
        for candidate in orientations {
            if hasReceiptSignal(for: candidate) { return true }
        }
        return false
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAutoScanEnabled else { return }
        guard !hasTriggeredAutoCapture else { return }

        // Auto torch evaluation (flashlight) during scanning.
        if autoTorchEnabled {
            let now = CACurrentMediaTime()
            if now - lastTorchEvalAt >= torchEvalInterval {
                lastTorchEvalAt = now
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let stats = estimateLumaStats(pixelBuffer)
                    if stats.brightness >= 0 {
                        // Latch behavior: once the torch turns on due to low light, keep it on for the
                        // rest of the scanning session (prevents flickering as exposure/brightness fluctuates).
                        if torchLatchedOn {
                            setTorch(on: true)
                        } else {
                            if stats.brightness < lowLightOnThreshold {
                                torchLatchedOn = true
                                torchDesiredOn = true
                                setTorch(on: true)
                            } else if stats.brightness > lowLightOffThreshold {
                                torchDesiredOn = false
                                setTorch(on: false)
                            }
                        }
                        updateExposureBiasIfNeeded(brightness: stats.brightness, contrastStd: stats.contrastStd)
                    }
                }
            }
        }

        guard isReceiptDetectionEnabled else { return }

        // Throttle Vision work
        let now = CACurrentMediaTime()
        if now - lastVisionAt < 0.08 { return } // ~12 fps (was 0.14 / ~7 fps)
        lastVisionAt = now

        // Avoid piling up analyses
        if isAnalyzing { return }
        isAnalyzing = true

        visionQueue.async { [weak self] in
            defer { self?.isAnalyzing = false }
            guard let self else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Portrait back camera: .right is typically correct for buffers.
            let orientation = CGImagePropertyOrientation.right

            let lumaStats = self.estimateLumaStats(pixelBuffer)
            let isBrightLowContrast = lumaStats.brightness >= self.brightLowContrastThreshold &&
                lumaStats.contrastStd >= 0 &&
                lumaStats.contrastStd <= self.lowContrastStdThreshold
            if isBrightLowContrast {
                self.lowContrastStreak = min(10, self.lowContrastStreak + 1)
            } else {
                self.lowContrastStreak = max(0, self.lowContrastStreak - 1)
            }

            let shouldPreprocess = self.lowContrastStreak >= self.preprocessStreakThreshold ||
                self.noCandidateStreak >= self.fallbackStreakThreshold

            func makePrimaryRequest() -> VNDetectRectanglesRequest {
                let request = VNDetectRectanglesRequest()
                request.maximumObservations = 8
                request.minimumConfidence = 0.45
                request.minimumAspectRatio = 0.10
                request.maximumAspectRatio = 0.90
                request.minimumSize = 0.08
                request.quadratureTolerance = 35.0 // was 25.0 - increased for tilted receipts
                if let roi = self.liveScanROI {
                    request.regionOfInterest = roi
                }
                return request
            }

            func makeFallbackRequest() -> VNDetectRectanglesRequest {
                let request = VNDetectRectanglesRequest()
                request.maximumObservations = 10
                request.minimumConfidence = 0.32
                request.minimumAspectRatio = 0.08
                request.maximumAspectRatio = 0.92
                request.minimumSize = 0.06
                request.quadratureTolerance = 45.0
                if let roi = self.liveScanROI {
                    request.regionOfInterest = roi
                }
                return request
            }

            func performRequest(_ request: VNDetectRectanglesRequest, using image: CIImage) -> [VNRectangleObservation] {
                let handler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    return request.results ?? []
                } catch {
                    return []
                }
            }

            let baseCIImage = CIImage(cvPixelBuffer: pixelBuffer)
            let primaryImage = shouldPreprocess ? self.preprocessReceiptImage(baseCIImage, stats: lumaStats) : baseCIImage
            let primaryRequest = makePrimaryRequest()
            var observations = performRequest(primaryRequest, using: primaryImage)

            // Try fallback with preprocessing if primary failed and we've detected issues (low contrast or repeated failures)
            if observations.isEmpty && shouldPreprocess {
                // Reuse preprocessed image if we already preprocessed for primary
                let fallbackImage = shouldPreprocess ? primaryImage : self.preprocessReceiptImage(baseCIImage, stats: lumaStats)
                let fallbackRequest = makeFallbackRequest()
                observations = performRequest(fallbackRequest, using: fallbackImage)
            }

            guard !observations.isEmpty else {
                self.noCandidateStreak = min(12, self.noCandidateStreak + 1)
                // Dropout tolerance: keep showing the last good quad briefly instead of blinking out.
                let now = CACurrentMediaTime()
                let withinGrace = (now - self.lastGoodQuadAt) <= self.quadHoldGraceSeconds
                if withinGrace {
                    // Decay stability slowly but keep overlay/track.
                    self.stabilityScore = max(0, self.stabilityScore - 2)
                    DispatchQueue.main.async {
                        if self.hasTriggeredAutoCapture {
                            self.applyStatusText("Capturing…", force: true)
                        } else if self.phase == .tracking || self.phase == .locked {
                            self.applyStatusText("Hold steady…")
                        } else {
                            if isBrightLowContrast {
                                self.applyStatusText("Too close — back up a little", force: true)
                            } else {
                                self.applyStatusText("Finding receipt…", force: true)
                            }
                        }
                    }
                } else {
                    // True loss: reset.
                    self.setPhase(.searching)
                    self.lockedQuad = nil
                    self.totalsHintCandidate = false
                    self.totalsHintPassed = false
                    self.lastFastTotalsHintResult = nil
                    self.captureHeldForTotalsAt = 0
                    self.lastCaptureBlockedLogAt = 0
                    self.lastFastTotalsCheckAt = 0
                    self.lastTotalsCheckAt = 0
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = nil
                        if isBrightLowContrast {
                            self.applyStatusText("Too close — back up a little", force: true)
                        } else {
                            self.applyStatusText("Finding receipt…", force: true)
                        }
                    }
                    self.trackedQuadRaw = nil
                    self.smoothedQuad = nil
                    self.stabilityScore = 0
                    self.trackedQuadStartTime = 0
                    self.trackedQuadBestStability = 0
                }
                return
            }

            func score(_ o: VNRectangleObservation) -> Double {
                let bb = o.boundingBox
                let area = Double(bb.width * bb.height)
                let w = Double(bb.width)
                let h = Double(bb.height)
                let longSide = max(w, h)
                let shortSide = min(w, h)
                let aspect = longSide > 0 ? (shortSide / longSide) : 0.0
                let conf = Double(o.confidence)

                // Prefer long rectangles and decent longSide fill.
                let aspectTarget = 0.33
                let aspectScore = max(0.0, 1.0 - abs(aspect - aspectTarget) / 0.55)

                // Prefer centered.
                let dx = Double(bb.midX - 0.5)
                let dy = Double(bb.midY - 0.5)
                let centerDist = sqrt(dx * dx + dy * dy)
                let centerScore = max(0.0, 1.0 - centerDist / 0.70)

                // Confidence weight increased (was 0.55 + 0.45*conf) to better reject low-contrast edges
                return pow(area, 1.1) * (0.40 + 0.60 * conf) * (0.55 + 0.45 * aspectScore) * (0.65 + 0.35 * centerScore) * (0.6 + 0.4 * longSide)
            }

            // Build candidates and apply stronger receipt-like filtering (reduces "imaginary boxes").
            struct Candidate {
                let quad: DetectedQuad
                let longSide: Double
                let aspect: Double
                let area: Double
            }

            func makeCandidate(_ o: VNRectangleObservation, minConfidence: Float) -> Candidate? {
                let bb = o.boundingBox
                let w = Double(bb.width)
                let h = Double(bb.height)
                let longSide = max(w, h)
                let aspect = longSide > 0 ? (min(w, h) / longSide) : 0.0
                let area = Double(bb.width * bb.height)

                // Reject squares / tiny junk early.
                // Relaxed for tilted receipts (bounding box becomes more square when tilted)
                if aspect > 0.88 { return nil } // was 0.82
                if area < 0.035 { return nil }
                if longSide < 0.30 { return nil } // was 0.35
                
                // Edge contrast validation: reject very low confidence detections
                // (likely false positives on white backgrounds or from hands)
                // This helps filter out "ghost" rectangles that Vision sometimes detects
                if o.confidence < minConfidence { return nil } // was implicit 0.45 from request

                let q = DetectedQuad(
                    topLeft: o.topLeft,
                    topRight: o.topRight,
                    bottomLeft: o.bottomLeft,
                    bottomRight: o.bottomRight,
                    boundingBox: o.boundingBox,
                    confidence: o.confidence,
                    score: score(o)
                )
                return Candidate(quad: q, longSide: longSide, aspect: aspect, area: area)
            }

            let minCandidateConfidence: Float = (observations.count > 0 && shouldPreprocess) ? 0.40 : 0.50
            let candidates = observations.compactMap { makeCandidate($0, minConfidence: minCandidateConfidence) }
                .sorted { $0.quad.score > $1.quad.score }
            guard let top = candidates.first else {
                // No valid candidates after filtering: apply the same dropout tolerance.
                self.noCandidateStreak = min(12, self.noCandidateStreak + 1)
                let now = CACurrentMediaTime()
                let withinGrace = (now - self.lastGoodQuadAt) <= self.quadHoldGraceSeconds
                if withinGrace {
                    self.stabilityScore = max(0, self.stabilityScore - 2)
                    DispatchQueue.main.async {
                        self.applyStatusText("Hold steady…")
                    }
                } else {
                    self.setPhase(.searching)
                    self.lockedQuad = nil
                    self.totalsHintCandidate = false
                    self.totalsHintPassed = false
                    self.lastFastTotalsHintResult = nil
                    self.captureHeldForTotalsAt = 0
                    self.lastCaptureBlockedLogAt = 0
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = nil
                        if isBrightLowContrast {
                            self.applyStatusText("Too close — back up a little", force: true)
                        } else {
                            self.applyStatusText("Finding receipt…", force: true)
                        }
                    }
                    self.trackedQuadRaw = nil
                    self.smoothedQuad = nil
                    self.stabilityScore = 0
                    self.trackedQuadStartTime = 0
                    self.trackedQuadBestStability = 0
                }
                return
            }
            self.noCandidateStreak = 0

            // Hysteresis: stick to the currently tracked quad unless a new candidate is clearly better
            // or is very close geometrically (same receipt, slight jitter).
            func avgCornerDelta(_ a: DetectedQuad, _ b: DetectedQuad) -> CGFloat {
                let d1 = hypot(a.topLeft.x - b.topLeft.x, a.topLeft.y - b.topLeft.y)
                let d2 = hypot(a.topRight.x - b.topRight.x, a.topRight.y - b.topRight.y)
                let d3 = hypot(a.bottomLeft.x - b.bottomLeft.x, a.bottomLeft.y - b.bottomLeft.y)
                let d4 = hypot(a.bottomRight.x - b.bottomRight.x, a.bottomRight.y - b.bottomRight.y)
                return (d1 + d2 + d3 + d4) / 4.0
            }
            
            // Calculate true quad dimensions from corners (rotation-invariant).
            // This handles tilted receipts better than axis-aligned bounding box.
            func trueQuadDimensions(_ quad: DetectedQuad) -> (longSide: CGFloat, aspect: CGFloat) {
                let topEdge = hypot(quad.topRight.x - quad.topLeft.x, quad.topRight.y - quad.topLeft.y)
                let bottomEdge = hypot(quad.bottomRight.x - quad.bottomLeft.x, quad.bottomRight.y - quad.bottomLeft.y)
                let leftEdge = hypot(quad.bottomLeft.x - quad.topLeft.x, quad.bottomLeft.y - quad.topLeft.y)
                let rightEdge = hypot(quad.bottomRight.x - quad.topRight.x, quad.bottomRight.y - quad.topRight.y)
                
                let avgWidth = (topEdge + bottomEdge) / 2
                let avgHeight = (leftEdge + rightEdge) / 2
                let longSide = max(avgWidth, avgHeight)
                let shortSide = min(avgWidth, avgHeight)
                let aspect = longSide > 0 ? shortSide / longSide : 0
                
                return (longSide, aspect)
            }

            let scoreGap: Double = (candidates.count >= 2) ? (candidates[0].quad.score - candidates[1].quad.score) : candidates[0].quad.score
            let ambiguous = candidates.count >= 2 && scoreGap / max(1e-6, candidates[0].quad.score) < 0.15 // was 0.10 - less sensitive to close scores

            var chosenRaw: DetectedQuad = top.quad
            let now = CACurrentMediaTime()
            
            // Check if we're stuck on the current tracked quad
            let isStuck = self.trackedQuadRaw != nil &&
                (now - self.trackedQuadStartTime) > self.stuckDetectionTimeout &&
                self.stabilityScore < (self.trackedQuadBestStability + 3)
            
            if isStuck {
                // Reset tracking to allow fresh detection
                self.trackedQuadRaw = nil
                self.smoothedQuad = nil
                self.trackedQuadStartTime = 0
                self.trackedQuadBestStability = 0
                chosenRaw = top.quad
            } else if let tracked = self.trackedQuadRaw {
                // Find the closest candidate to the tracked quad.
                let closest = candidates.min(by: { avgCornerDelta($0.quad, tracked) < avgCornerDelta($1.quad, tracked) })?.quad
                if let closest {
                    let delta = avgCornerDelta(closest, tracked)
                    let bestScore = candidates[0].quad.score
                    let trackedScore = tracked.score
                    
                    // Get geometry for comparison
                    let (bestLongSide, bestAspect) = trueQuadDimensions(candidates[0].quad)
                    let (trackedLongSide, trackedAspect) = trueQuadDimensions(tracked)
                    let bestArea = candidates[0].area
                    let trackedArea = Double(tracked.boundingBox.width * tracked.boundingBox.height)
                    
                    // Geometry-based switching: prefer larger area and better aspect ratio
                    let hasBetterGeometry = bestArea > trackedArea * 1.15 && 
                                          bestAspect < trackedAspect * 1.1 && 
                                          bestLongSide > trackedLongSide * 1.05
                    
                    // Stability-based switching: if stability isn't improving, be more lenient
                    let stabilityNotImproving = (now - self.trackedQuadStartTime) > 2.0 &&
                                               self.stabilityScore <= self.trackedQuadBestStability
                    let stabilityBasedSwitch = stabilityNotImproving && bestScore > trackedScore * 1.10

                    // Prefer staying on the same physical receipt (geometric proximity).
                    if delta < 0.060 {
                        chosenRaw = closest
                    } else if bestScore > trackedScore * 1.15 && !ambiguous { // Reduced from 1.20
                        // Switch if clearly better and not ambiguous.
                        chosenRaw = candidates[0].quad
                    } else if hasBetterGeometry && !ambiguous {
                        // Switch if geometry is significantly better (larger, better aspect)
                        chosenRaw = candidates[0].quad
                    } else if stabilityBasedSwitch && !ambiguous {
                        // Switch if stability isn't improving and new candidate is better
                        chosenRaw = candidates[0].quad
                    } else {
                        // Keep tracked to prevent jumping.
                        chosenRaw = tracked
                    }
                } else {
                    chosenRaw = tracked
                }
            } else {
                // No tracked quad - prefer best candidate with good geometry
                chosenRaw = top.quad
            }

            // Normalise corner labels by spatial position before any tracking/smoothing.
            // Vision can swap which corner is "topLeft" between frames; without this the EMA
            // interpolates between mismatched corners and produces crossed/triangle shapes.
            chosenRaw = self.normalizeCornerOrder(chosenRaw)

            // Update tracking state when quad changes
            let previousTracked = self.trackedQuadRaw
            self.trackedQuadRaw = chosenRaw
            self.lastCandidateAt = CACurrentMediaTime()
            
            // If we switched to a new quad, reset tracking timers
            if previousTracked == nil || avgCornerDelta(chosenRaw, previousTracked!) > 0.10 {
                self.trackedQuadStartTime = now
                self.trackedQuadBestStability = self.stabilityScore
            }

            // Smooth the quad to remove jitter (EMA with adaptive alpha).
            func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            // Adaptive alpha: snap quickly for large movements, smooth for small jitter
            // was fixed at 0.22
            if let prev = self.smoothedQuad {
                let rawDelta = avgCornerDelta(chosenRaw, prev)
                let baseAlpha: CGFloat = rawDelta > 0.05 ? 0.55 : (rawDelta > 0.02 ? 0.38 : 0.22)
                // When stability is high, heavily dampen the alpha so the overlay resists
                // drifting to slightly-offset detections (e.g. Vision catching a shadow/edge).
                // Genuine movement drops stability quickly, which removes this cap.
                let alpha: CGFloat = self.stabilityScore >= 12 ? min(baseAlpha, 0.10) : baseAlpha
                let tl = lerp(prev.topLeft, chosenRaw.topLeft, alpha)
                let tr = lerp(prev.topRight, chosenRaw.topRight, alpha)
                let bl = lerp(prev.bottomLeft, chosenRaw.bottomLeft, alpha)
                let br = lerp(prev.bottomRight, chosenRaw.bottomRight, alpha)

                let minX = min(tl.x, tr.x, bl.x, br.x)
                let maxX = max(tl.x, tr.x, bl.x, br.x)
                let minY = min(tl.y, tr.y, bl.y, br.y)
                let maxY = max(tl.y, tr.y, bl.y, br.y)
                let bb = CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))

                self.smoothedQuad = DetectedQuad(
                    topLeft: tl,
                    topRight: tr,
                    bottomLeft: bl,
                    bottomRight: br,
                    boundingBox: bb,
                    confidence: chosenRaw.confidence,
                    score: chosenRaw.score
                )
            } else {
                self.smoothedQuad = chosenRaw
            }

            guard let publishQuad = self.smoothedQuad else { return }
            self.lastGoodQuadAt = CACurrentMediaTime()
            if self.phase == .searching {
                self.setPhase(.tracking)
                // Preserve a valid hint when entering tracking so capture isn't blocked.
                // If we don't have one yet, clear hint state and restart timing windows.
                if !self.totalsHintCandidate {
                    self.totalsHintPassed = false
                    self.lastFastTotalsCheckAt = 0
                    self.lastTotalsCheckAt = 0
                    self.lastFastTotalsHintResult = nil
                }
            }

            // Lock behavior: once locked, stop updating the quad (freeze highlight) and commit to capture.
            if self.phase == .locked || self.phase == .capturing {
                if let locked = self.lockedQuad {
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = locked
                        self.applyStatusText("Capturing…", force: true)
                    }
                }
                return
            }

            // Stability on the smoothed quad (more reliable when holding receipt up).
            let previous = self.detectedReceiptQuad
            let delta = (previous != nil) ? avgCornerDelta(previous!, publishQuad) : 1.0
            let motionStable = delta < 0.018 // was 0.013 - relaxed for faster lock

            // Score-based stability (not perfect consecutive frames):
            // - stable + unambiguous: ramp up quickly
            // - ambiguous: still gain but slower
            // - unstable: decay slowly
            let previousStability = self.stabilityScore
            if motionStable && !ambiguous {
                self.stabilityScore = min(30, self.stabilityScore + 5) // faster ramp when steady
            } else if motionStable && ambiguous {
                self.stabilityScore = min(30, self.stabilityScore + 3) // allow gains even when ambiguous
            } else if ambiguous {
                self.stabilityScore = max(0, self.stabilityScore - 1)
            } else {
                self.stabilityScore = max(0, self.stabilityScore - 1)
            }
            
            // Update best stability if we improved
            if self.stabilityScore > previousStability && self.stabilityScore > self.trackedQuadBestStability {
                self.trackedQuadBestStability = self.stabilityScore
            }

            // Fast totals hint first, then full hint (throttled).
            // Start early (stability 6) so OCR has time before the capture gate at 18.
            if self.stabilityScore >= 6 && !self.totalsHintCandidate && !self.hasTriggeredAutoCapture {
                if (now - self.lastFastTotalsCheckAt) >= self.fastTotalsCheckInterval {
                    self.lastFastTotalsCheckAt = now
                    self.checkFastTotalsHintOnLiveFrame(pixelBuffer, orientation: orientation) { [weak self] hasTotalsHint in
                        guard let self else { return }
                        DispatchQueue.main.async {
                            self.lastFastTotalsHintResult = hasTotalsHint
                            self.totalsHintCandidate = hasTotalsHint
                            if !hasTotalsHint {
                                self.totalsHintPassed = false
                            }
                        }
                    }
                }
            }

            let shouldCheckTotals = self.totalsHintCandidate &&
                self.stabilityScore >= 15 &&
                (now - self.lastTotalsCheckAt) >= self.totalsCheckInterval

            if shouldCheckTotals && !self.hasTriggeredAutoCapture {
                self.lastTotalsCheckAt = now
                self.checkTotalsHintOnLiveFrame(pixelBuffer, orientation: orientation) { [weak self] hasTotals in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.totalsHintPassed = hasTotals
                    }
                }
            }
            
            let (trueLongSideForStatus, _) = trueQuadDimensions(publishQuad)
            DispatchQueue.main.async {
                self.detectedReceiptQuad = publishQuad
                if self.hasTriggeredAutoCapture {
                    self.applyStatusText("Capturing…", force: true)
                } else {
                    let bb = publishQuad.boundingBox
                    let quadSmall = max(bb.width, bb.height) < 0.40
                    if isBrightLowContrast && quadSmall {
                        self.applyStatusText("Too close — back up a little")
                    } else if trueLongSideForStatus < 0.45 {
                        self.applyStatusText("Hold phone closer to receipt")
                    } else if self.stabilityScore >= 18 && !self.totalsHintCandidate {
                        self.applyStatusText("Point at a receipt to scan")
                    } else if self.stabilityScore >= 18 && ambiguous && self.totalsHintCandidate {
                        self.applyStatusText("Center just one receipt")
                    } else if self.stabilityScore >= 18 {
                        self.applyStatusText("Hold steady…")
                    } else {
                        self.applyStatusText("Hold steady…")
                    }
                }
            }

            // Trigger auto-capture once stable enough and receipt-like.
            if self.stabilityScore >= 18 && !self.hasTriggeredAutoCapture { // was 24
                // Use true quad geometry (rotation-invariant) for gating tilted receipts.
                let (trueLongSide, trueAspect) = trueQuadDimensions(publishQuad)
                let geometryReady = trueLongSide >= 0.45 && trueAspect <= 0.78
                let textReady = self.totalsHintCandidate
                // If OCR says this is a receipt and stability is very high, allow capture
                // even when Vision still marks the scene as slightly ambiguous.
                let ambiguityReady = !ambiguous || (textReady && self.stabilityScore >= 24)
                // Relaxed thresholds: was longSide >= 0.52 && aspect <= 0.72
                if geometryReady && ambiguityReady && textReady {
                    // Capture when stable + receipt-like geometry + receipt text detected.
                    // totalsHintCandidate ensures we don't snap random non-receipt objects.
                    self.setPhase(.locked)
                    self.lockedQuad = publishQuad
                    self.hasTriggeredAutoCapture = true
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = publishQuad
                        self.applyStatusText("Capturing…", force: true)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.lockDelaySeconds) {
                        // If something external cancelled auto scan, respect it.
                        guard self.isAutoScanEnabled else { return }
                        self.setPhase(.capturing)
                        self.shouldAutoCapture = true
                    }
                } else if geometryReady && !textReady {
                    if (now - self.lastCaptureBlockedLogAt) >= 0.8 {
                        self.lastCaptureBlockedLogAt = now
                        let hint = self.lastFastTotalsHintResult.map { $0 ? "true" : "false" } ?? "nil"
                        DebugLogger.debug(
                            "🧾 Capture blocked: awaiting text hint (stability=\(self.stabilityScore), longSide=\(String(format: "%.2f", trueLongSide)), aspect=\(String(format: "%.2f", trueAspect)), lastFastHint=\(hint))",
                            category: "ReceiptScan"
                        )
                    }
                } else if geometryReady && ambiguous && textReady {
                    if (now - self.lastCaptureBlockedLogAt) >= 0.8 {
                        self.lastCaptureBlockedLogAt = now
                        DebugLogger.debug(
                            "🧾 Capture waiting: ambiguous candidates (stability=\(self.stabilityScore), longSide=\(String(format: "%.2f", trueLongSide)), aspect=\(String(format: "%.2f", trueAspect)))",
                            category: "ReceiptScan"
                        )
                    }
                }
            }
        }
    }

    /// Normalises corner labels by spatial position so the EMA never interpolates
    /// between mismatched corners when Vision swaps its labelling between frames.
    /// Top two corners (highest Y in Vision coords) are sorted by X → topLeft / topRight.
    /// Bottom two corners (lowest Y) are sorted by X → bottomLeft / bottomRight.
    private func normalizeCornerOrder(_ raw: DetectedQuad) -> DetectedQuad {
        var pts = [raw.topLeft, raw.topRight, raw.bottomRight, raw.bottomLeft]
        // Vision coordinates: origin bottom-left, Y increases upward.
        // Sort descending by Y so the two highest-Y points come first (top of receipt).
        pts.sort { $0.y > $1.y }

        // Top pair (indices 0, 1): lower X → topLeft
        let tl = pts[0].x <= pts[1].x ? pts[0] : pts[1]
        let tr = pts[0].x <= pts[1].x ? pts[1] : pts[0]
        // Bottom pair (indices 2, 3): lower X → bottomLeft
        let bl = pts[2].x <= pts[3].x ? pts[2] : pts[3]
        let br = pts[2].x <= pts[3].x ? pts[3] : pts[2]

        return DetectedQuad(
            topLeft: tl, topRight: tr,
            bottomLeft: bl, bottomRight: br,
            boundingBox: raw.boundingBox,
            confidence: raw.confidence,
            score: raw.score
        )
    }

    private struct LumaStats {
        let brightness: Double
        let contrastStd: Double
    }

    /// Returns a rough 0..1 brightness and contrast estimate from a BGRA pixel buffer.
    /// Samples a sparse grid (fast) and uses the green channel as a luminance proxy.
    private func estimateLumaStats(_ pixelBuffer: CVPixelBuffer) -> LumaStats {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return LumaStats(brightness: -1, contrastStd: -1)
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        if width <= 0 || height <= 0 {
            return LumaStats(brightness: -1, contrastStd: -1)
        }

        // Sample ~40x40 grid max.
        let stepX = max(1, width / 40)
        let stepY = max(1, height / 40)

        var sum: Double = 0
        var sumSq: Double = 0
        var count: Double = 0

        for y in stride(from: 0, to: height, by: stepY) {
            let row = base.advanced(by: y * bpr)
            for x in stride(from: 0, to: width, by: stepX) {
                let px = row.advanced(by: x * 4)
                // BGRA: [B, G, R, A] - use G as luma proxy
                let g = Double(px.load(fromByteOffset: 1, as: UInt8.self))
                sum += g
                sumSq += g * g
                count += 1
            }
        }

        guard count > 0 else { return LumaStats(brightness: -1, contrastStd: -1) }
        let mean = sum / count
        let variance = max(0, (sumSq / count) - (mean * mean))
        let std = sqrt(variance)
        return LumaStats(brightness: mean / 255.0, contrastStd: std / 255.0)
    }

    private func preprocessReceiptImage(_ image: CIImage, stats: LumaStats) -> CIImage {
        let contrastBoost: Double
        if stats.contrastStd >= 0 && stats.contrastStd < 0.06 {
            contrastBoost = 1.55
        } else if stats.contrastStd >= 0 && stats.contrastStd < 0.09 {
            contrastBoost = 1.35
        } else {
            contrastBoost = 1.18
        }

        let brightnessAdjust: Double
        if stats.brightness > 0.75 {
            brightnessAdjust = -0.10
        } else if stats.brightness > 0.60 {
            brightnessAdjust = -0.06
        } else {
            brightnessAdjust = -0.02
        }

        let colorAdjusted = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: contrastBoost,
            kCIInputBrightnessKey: brightnessAdjust,
            kCIInputSaturationKey: 0.0
        ])

        return colorAdjusted.applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: 0.4
        ])
    }

    private func updateExposureBiasIfNeeded(brightness: Double, contrastStd: Double) {
        guard let device = cameraDevice else { return }
        let now = CACurrentMediaTime()
        if now - lastExposureBiasUpdateAt < exposureBiasUpdateInterval { return }

        let shouldLowerExposure = brightness >= brightLowContrastThreshold &&
            contrastStd >= 0 &&
            contrastStd <= lowContrastStdThreshold
        let targetBias: Float = shouldLowerExposure ? lowContrastExposureBias : 0.0

        if abs(targetBias - currentExposureBias) < 0.05 { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let clamped = min(device.maxExposureTargetBias, max(device.minExposureTargetBias, targetBias))
            device.setExposureTargetBias(clamped) { [weak self] _ in
                self?.currentExposureBias = clamped
            }
            lastExposureBiasUpdateAt = now
        } catch {
            DebugLogger.debug("⚠️ Exposure bias config failed: \(error.localizedDescription)", category: "ReceiptScan")
        }
    }
}

func uploadReceiptImage(_ image: UIImage, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    let urlString = "\(Config.backendURL)/submit-receipt"
    DebugLogger.debug("📤 Uploading receipt to: \(urlString)", category: "ReceiptScan")
    
    guard let url = URL(string: urlString) else {
        DebugLogger.debug("❌ Invalid URL: \(urlString)", category: "ReceiptScan")
        completion(.failure(NSError(domain: "Invalid URL", code: 0)))
        return
    }
    
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        DebugLogger.debug("❌ Failed to convert image to JPEG data", category: "ReceiptScan")
        completion(.failure(NSError(domain: "Image conversion failed", code: 0)))
        return
    }
    
    guard let currentUser = Auth.auth().currentUser else {
        DebugLogger.debug("❌ No authenticated user found when uploading receipt", category: "ReceiptScan")
        completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
        return
    }
    
    currentUser.getIDToken { token, error in
        if let error = error {
            DebugLogger.debug("❌ Failed to get ID token: \(error.localizedDescription)", category: "ReceiptScan")
            completion(.failure(error))
            return
        }
        
        guard let token = token else {
            DebugLogger.debug("❌ ID token is nil", category: "ReceiptScan")
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unable to get auth token"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        DeviceFingerprint.addToRequest(&request)
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "x-user-timezone")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        func appendString(_ value: String) -> Bool {
            guard let data = value.data(using: .utf8) else { return false }
            body.append(data)
            return true
        }
        
        // Add the image part
        guard appendString("--\(boundary)\r\n"),
              appendString("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n"),
              appendString("Content-Type: image/jpeg\r\n\r\n") else {
            DebugLogger.debug("❌ Failed to encode multipart header", category: "ReceiptScan")
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "Encoding", code: 0)))
            }
            return
        }
        body.append(imageData)
        guard appendString("\r\n"),
              appendString("--\(boundary)--\r\n") else {
            DebugLogger.debug("❌ Failed to encode multipart footer", category: "ReceiptScan")
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "Encoding", code: 0)))
            }
            return
        }
        
        // Set the content length
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        
        DebugLogger.debug("📤 Request body size: \(body.count) bytes", category: "ReceiptScan")
        
        // Use a session with better connectivity behavior
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config)
        session.uploadTask(with: request, from: body) { data, response, error in
            defer { session.invalidateAndCancel() }
            if let error = error {
                DebugLogger.debug("❌ Network error: \(error.localizedDescription)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            var statusCode: Int = -1
            if let httpResponse = response as? HTTPURLResponse {
                statusCode = httpResponse.statusCode
                DebugLogger.debug("📡 HTTP Status: \(statusCode)", category: "ReceiptScan")
            }
            
            guard let data = data else {
                DebugLogger.debug("❌ No response data received", category: "ReceiptScan")
                DispatchQueue.main.async { completion(.failure(NSError(domain: "No data", code: 0))) }
                return
            }
            
            // Print response summary for debugging (truncated to avoid logging sensitive data)
            if let responseString = String(data: data, encoding: .utf8) {
                let truncated = responseString.count > 200 ? "\(responseString.prefix(200))... [truncated]" : responseString
                DebugLogger.debug("📥 Response (\(data.count) bytes): \(truncated)", category: "ReceiptScan")
            }
            
            // If non-2xx, attempt to surface a server error as JSON for better UX mapping
            if !(200...299).contains(statusCode), statusCode != -1 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var enriched = json
                    if enriched["error"] == nil {
                        enriched["error"] = "Server error \(statusCode)"
                    }
                    DebugLogger.debug("⚠️ Non-2xx with JSON body, surfacing as error: \(enriched)", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.success(enriched)) }
                    return
                } else {
                    let message = "Server error \(statusCode)"
                    DebugLogger.debug("⚠️ Non-2xx without JSON body, surfacing generic error: \(message)", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.success(["error": message])) }
                    return
                }
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DebugLogger.debug("✅ Successfully parsed JSON response", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.success(json)) }
                } else {
                    DebugLogger.debug("❌ Failed to parse JSON response", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "Invalid JSON", code: 0))) }
                }
            } catch {
                DebugLogger.debug("❌ JSON parsing error: \(error.localizedDescription)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}

// MARK: - Client-side OCR gate (prevent hallucinated totals)

/// Fast on-device check to ensure the receipt image includes the Subtotal/Tax/Total section.
/// If this fails, we reject locally to avoid the model guessing a total from incomplete evidence.
private func receiptHasSubtotalTaxTotal(_ image: UIImage, completion: @escaping (Bool) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let ok = receiptHasSubtotalTaxTotalSync(image)
        DispatchQueue.main.async { completion(ok) }
    }
}

private func receiptHasSubtotalTaxTotalSync(_ image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else { return false }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    // Expanded: scan bottom 85% of image (up from 65%) to catch more receipt layouts.
    request.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.85)

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return false
    }

    let strings = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    let text = strings.joined(separator: "\n").lowercased()

    // Expanded keyword list for totals section detection
    let hasSubtotal = text.contains("subtotal") || text.contains("sub total")
    let hasTax = text.contains("tax")
    let hasTotal = text.contains("total")
    let hasTip = text.contains("tip") || text.contains("gratuity")
    let hasFee = text.contains("fee")
    let hasDue = text.contains("due") || text.contains("amount")
    
    // Relaxed: require only 1 keyword from the expanded set (down from 2 of 3)
    let hasAnyTotalsKeyword = hasSubtotal || hasTax || hasTotal || hasTip || hasFee || hasDue
    guard hasAnyTotalsKeyword else { return false }

    // Require at least one currency-like amount to reduce false positives.
    let pattern = #"\b\d+\.\d{2}\b"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    if let regex = regex {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    return false
}

// MARK: - Receipt image preprocessing (Option B: detect receipt rectangle + guarded crop selection)

/// Runs Vision rectangle detection and selects the safest cropped candidate for upload.
/// If crop confidence is low (likely header loss), retries with expanded crop, then falls back to full image.
private func preprocessReceiptImageForUpload(_ image: UIImage, completion: @escaping (UIImage) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let normalized = normalizeImageOrientation(image)
        let downscaled = downscaleIfNeeded(normalized, maxDimension: 2000)

        // Height retention: how much of the original image height the crop preserves.
        func heightRetention(_ candidate: UIImage) -> CGFloat {
            guard downscaled.size.height > 0 else { return 1.0 }
            return candidate.size.height / downscaled.size.height
        }

        // --- Primary crop attempt ---
        if let primaryCrop = detectAndCorrectReceipt(
            in: downscaled,
            debugLog: false,
            cropScale: 1.08,
            extraTopPaddingFraction: 0.35,
            extraBottomPaddingFraction: 0.26
        ) {
            let retention = heightRetention(primaryCrop)

            // Good retention (>= 55%): crop almost certainly includes header. Accept.
            if retention >= 0.55 {
                DebugLogger.debug("🧾 Preprocessing: primary crop ACCEPTED (height retention \(String(format: "%.0f", retention * 100))%)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(primaryCrop) }
                return
            }

            // Borderline retention (< 55%): surprisingly tight crop.
            // Use OCR hint as tiebreaker — if header text found, accept primary crop.
            if topRegionLikelyContainsRestaurantName(primaryCrop) {
                DebugLogger.debug("🧾 Preprocessing: primary crop ACCEPTED (tight but OCR found header, retention \(String(format: "%.0f", retention * 100))%)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(primaryCrop) }
                return
            }

            // Primary crop is tight AND OCR missed header — try expanded crop.
            DebugLogger.debug("🧾 Preprocessing: primary crop too tight & no header (retention \(String(format: "%.0f", retention * 100))%), trying expanded crop", category: "ReceiptScan")
            if let expandedCrop = detectAndCorrectReceipt(
                in: downscaled,
                debugLog: false,
                cropScale: 1.12,
                extraTopPaddingFraction: 0.52,
                extraBottomPaddingFraction: 0.32
            ) {
                // Always accept the expanded crop — its generous padding makes header loss very unlikely.
                let expRetention = heightRetention(expandedCrop)
                DebugLogger.debug("🧾 Preprocessing: expanded crop ACCEPTED (retention \(String(format: "%.0f", expRetention * 100))%)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(expandedCrop) }
                return
            }

            // Expanded crop detection failed — fall back to full image.
            DebugLogger.debug("🧾 Preprocessing: expanded crop detection failed, using full image fallback", category: "ReceiptScan")
            DispatchQueue.main.async { completion(downscaled) }
            return
        }

        // No rectangle detected at all — send full image.
        DebugLogger.debug("🧾 Preprocessing: no rectangle detected, using full image fallback", category: "ReceiptScan")
        DispatchQueue.main.async { completion(downscaled) }
    }
}

/// Fast, conservative OCR hint for whether the restaurant name is visible near the top.
/// Returns true when we have enough signal that a crop likely includes the Dumpling House header.
private func topRegionLikelyContainsRestaurantName(_ image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else { return false }

    let cropHeight = max(1, Int(CGFloat(cgImage.height) * 0.42))
    let topRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cropHeight)
    guard let topCG = cgImage.cropping(to: topRect) else { return false }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.015

    let handler = VNImageRequestHandler(cgImage: topCG, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return false
    }

    let text = request.results?
        .compactMap { $0.topCandidates(1).first?.string.lowercased() }
        .joined(separator: " ") ?? ""

    let hasDumplingHouse = text.contains("dumpling house")
    let hasSplitWords = text.contains("dumpling") && text.contains("house")
    return hasDumplingHouse || hasSplitWords
}

/// Saves the given image to the camera roll. Used only when admin toggle "Save scanned receipts to camera roll" is on.
/// Request add-only photo library permission; saves asynchronously so upload is not blocked.
private func saveScannedReceiptImageToCameraRoll(_ image: UIImage) {
    guard let data = image.jpegData(compressionQuality: 0.95) else { return }
    DispatchQueue.global(qos: .utility).async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let requestAuth = {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                guard newStatus == .authorized || newStatus == .limited else {
                    DebugLogger.debug("🧾 Save to camera roll: permission denied", category: "ReceiptScan")
                    return
                }
                performSave(data: data)
            }
        }
        switch status {
        case .authorized, .limited:
            performSave(data: data)
        case .notDetermined:
            requestAuth()
        case .denied, .restricted:
            DebugLogger.debug("🧾 Save to camera roll: permission denied or restricted", category: "ReceiptScan")
        @unknown default:
            requestAuth()
        }
    }
    func performSave(data: Data) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }) { success, error in
            if success {
                DebugLogger.debug("🧾 Save to camera roll: saved image sent to server", category: "ReceiptScan")
            } else {
                DebugLogger.debug("🧾 Save to camera roll failed: \(error?.localizedDescription ?? "unknown")", category: "ReceiptScan")
            }
        }
    }
}

/// Fallback crop when rectangle detection fails: union all recognized text boxes and crop conservatively.
/// The crop is biased to keep the bottom portion (where totals usually live) and expands width generously.
private func heuristicTextCropReceipt(_ image: UIImage, debugLog: Bool) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.02

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        if debugLog {
            DebugLogger.debug("🧾 Heuristic text crop OCR error: \(error)", category: "ReceiptScan")
        }
        return nil
    }

    let boxes = request.results?.map { $0.boundingBox } ?? []
    guard var union = boxes.first else { return nil }
    for b in boxes.dropFirst() {
        union = union.union(b)
    }

    // Vision bounding boxes are normalized with origin at bottom-left.
    // Make a conservative crop that keeps the bottom of the image and includes all detected text.
    let padX: CGFloat = 0.06
    let padTop: CGFloat = 0.08

    // Start from bottom (y=0) up to the top of detected text (+ padding).
    var x0 = max(0.0, union.minX - padX)
    var x1 = min(1.0, union.maxX + padX)
    var h = min(1.0, union.maxY + padTop)

    // Expand width aggressively to avoid clipping receipt edges.
    if (x1 - x0) < 0.92 {
        x0 = 0.0
        x1 = 1.0
    }

    // Ensure we keep enough vertical content to include totals (even if text detection is sparse).
    h = max(h, 0.60)
    h = min(h, 1.0)

    let cropNorm = CGRect(x: x0, y: 0.0, width: max(0.01, x1 - x0), height: max(0.01, h))

    let imgW = CGFloat(cgImage.width)
    let imgH = CGFloat(cgImage.height)

    // Convert Vision-normalized (bottom-left origin) to CGImage pixel rect (top-left origin).
    let cropX = cropNorm.minX * imgW
    let cropW = cropNorm.width * imgW
    let cropH = cropNorm.height * imgH
    let cropYTopLeft = imgH - cropH

    let rect = CGRect(x: cropX, y: cropYTopLeft, width: cropW, height: cropH).integral
    guard rect.width > 10, rect.height > 10 else { return nil }
    guard let croppedCG = cgImage.cropping(to: rect) else { return nil }

    if debugLog {
        DebugLogger.debug("🧾 Heuristic text crop: cropRect=\(rect) from (\(cgImage.width)x\(cgImage.height))", category: "ReceiptScan")
    }
    return UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
}

private func normalizeImageOrientation(_ image: UIImage) -> UIImage {
    guard image.imageOrientation != .up else { return image }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}

private func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let w = image.size.width
    let h = image.size.height
    let maxSide = max(w, h)
    guard maxSide > maxDimension, maxSide > 0 else { return image }

    let scale = maxDimension / maxSide
    let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))
    guard newSize.width > 0, newSize.height > 0 else { return image }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0 // we are explicitly controlling pixel size
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
}

private func detectAndCorrectReceipt(
    in image: UIImage,
    debugLog: Bool,
    cropScale: CGFloat = 1.08,
    extraTopPaddingFraction: CGFloat = 0.35,
    extraBottomPaddingFraction: CGFloat = 0.26
) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }

    // Detect rectangles
    let request = VNDetectRectanglesRequest()
    // Consider more candidates; we will score them ourselves.
    request.maximumObservations = 12
    // Lower slightly to avoid missing faint edges on white receipts/sheets; scoring + guards will reject junk.
    request.minimumConfidence = 0.55
    // Receipts are typically long rectangles; de-emphasize near-squares.
    request.minimumAspectRatio = 0.12
    request.maximumAspectRatio = 0.85
    request.quadratureTolerance = 20.0
    // Allow narrower receipts (long + skinny) to be detected when the user doesn't fill the frame perfectly.
    request.minimumSize = 0.10

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        DebugLogger.debug("🧾 Rectangle detection error: \(error)", category: "ReceiptScan")
        return nil
    }

    guard let observations = request.results, !observations.isEmpty else { return nil }

    // Score candidates for "receipt-like" geometry: big + long-rectangle + roughly centered.
    func candidateScore(_ o: VNRectangleObservation) -> Double {
        let bb = o.boundingBox
        let area = Double(bb.width * bb.height) // normalized
        let w = Double(bb.width)
        let h = Double(bb.height)
        let minSide = min(w, h)
        let maxSide = max(w, h)
        let aspect = maxSide > 0 ? (minSide / maxSide) : 0.0 // 1.0 = square, smaller = longer rectangle

        // Prefer a long rectangle (receipts): peak around ~0.33, penalize near-squares.
        let targetAspect = 0.33
        let aspectRange = 0.45 // broad tolerance (covers many receipt widths)
        let aspectScore = max(0.0, 1.0 - abs(aspect - targetAspect) / aspectRange)

        // Prefer rectangles near the center (user aligns within guide frame).
        let cx = Double(bb.midX)
        let cy = Double(bb.midY)
        let dx = cx - 0.5
        let dy = cy - 0.5
        let centerDist = sqrt(dx * dx + dy * dy) // 0..~0.707
        let centerScore = max(0.0, 1.0 - (centerDist / 0.65))

        // Combine: area dominates, then confidence, with shape/center nudges.
        let conf = Double(o.confidence)
        return pow(area, 1.25) * (0.6 + 0.4 * conf) * (0.55 + 0.45 * aspectScore) * (0.65 + 0.35 * centerScore)
    }

    // Sort candidates by score (descending) and try the top 3.
    let sorted = observations.sorted { candidateScore($0) > candidateScore($1) }
    let topCandidates = Array(sorted.prefix(3))

    let ciImage = CIImage(cgImage: cgImage)
    let extent = ciImage.extent
    let imgWidth = extent.width
    let imgHeight = extent.height

    func denorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * imgWidth, y: p.y * imgHeight)
    }

    for (index, rect) in topCandidates.enumerated() {
        // Guardrail: if this candidate is too small or too square-ish, skip it.
        let bb = rect.boundingBox
        let area = Double(bb.width * bb.height)
        let w = Double(bb.width)
        let h = Double(bb.height)
        let longSide = max(w, h)
        let aspect = longSide > 0 ? min(w, h) / longSide : 0.0

        let looksLikeLongReceipt = (longSide >= 0.70 && aspect <= 0.55)
        let areaTooSmall = area < 0.06
        let tooSquare = aspect > 0.80

        if tooSquare || (areaTooSmall && !looksLikeLongReceipt) {
            if debugLog {
                DebugLogger.debug("🧾 Crop candidate #\(index): geometry rejected (area=\(String(format: "%.3f", area)), aspect=\(String(format: "%.3f", aspect)), longSide=\(String(format: "%.3f", longSide)))", category: "ReceiptScan")
            }
            continue
        }

        var topLeft = denorm(rect.topLeft)
        var topRight = denorm(rect.topRight)
        var bottomLeft = denorm(rect.bottomLeft)
        var bottomRight = denorm(rect.bottomRight)

        (topLeft, topRight, bottomLeft, bottomRight) = inflateQuadWithVerticalPadding(
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight,
            scale: cropScale,
            extraTopPaddingFraction: extraTopPaddingFraction,
            extraBottomPaddingFraction: extraBottomPaddingFraction,
            bounds: extent
        )

        let allX = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x]
        let allY = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y]
        let minX = max(allX.min()!, extent.minX)
        let minY = max(allY.min()!, extent.minY)
        let maxX = min(allX.max()!, extent.maxX)
        let maxY = min(allY.max()!, extent.maxY)
        // Convert from CIImage coords (origin bottom-left) to CGImage coords (origin top-left).
        let flippedY = imgHeight - maxY
        let cropRect = CGRect(x: minX, y: flippedY, width: maxX - minX, height: maxY - minY)

        guard cropRect.width > 0, cropRect.height > 0 else { continue }
        guard let croppedCG = cgImage.cropping(to: cropRect) else { continue }

        DebugLogger.debug("🧾 Crop candidate #\(index): cropRect=(\(String(format: "%.0f", cropRect.origin.x)), \(String(format: "%.0f", cropRect.origin.y)), \(String(format: "%.0f", cropRect.width))x\(String(format: "%.0f", cropRect.height))) in \(cgImage.width)x\(cgImage.height)", category: "ReceiptScan")

        // Post-crop text sanity check: reject crops that contain no receipt-like text.
        let textLineCount = fastTextLineCount(croppedCG)
        if textLineCount < 3 {
            DebugLogger.debug("🧾 Crop candidate #\(index): rejected (only \(textLineCount) text lines, need >= 3)", category: "ReceiptScan")
            continue
        }

        DebugLogger.debug("🧾 Crop candidate #\(index): ACCEPTED (\(textLineCount) text lines, area=\(String(format: "%.3f", area)))", category: "ReceiptScan")
        return UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
    }

    // No candidate passed geometry + text checks.
    return nil
}

/// Fast text-line count on a CGImage. Used as a post-crop sanity check to reject
/// non-text regions (table edges, shadows, etc.) before upload.
private func fastTextLineCount(_ cgImage: CGImage) -> Int {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.01

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return 0
    }
    return request.results?.count ?? 0
}

private func inflateQuad(
    topLeft: CGPoint,
    topRight: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    scale: CGFloat,
    bounds: CGRect
) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    let cx = (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4.0
    let cy = (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4.0
    let center = CGPoint(x: cx, y: cy)

    func scaled(_ p: CGPoint) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let out = CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        return CGPoint(
            x: min(max(out.x, bounds.minX), bounds.maxX),
            y: min(max(out.y, bounds.minY), bounds.maxY)
        )
    }

    return (scaled(topLeft), scaled(topRight), scaled(bottomLeft), scaled(bottomRight))
}

/// Inflates a quad uniformly, then adds extra padding specifically on the "top" edge
/// (useful for long receipts where Vision sometimes detects a slightly-short rectangle and clips headers).
private func inflateQuadWithTopPadding(
    topLeft: CGPoint,
    topRight: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    scale: CGFloat,
    extraTopPaddingFraction: CGFloat,
    bounds: CGRect
) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    var (tl, tr, bl, br) = inflateQuad(
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        scale: scale,
        bounds: bounds
    )

    // Compute direction from bottom edge to top edge.
    let topMid = CGPoint(x: (tl.x + tr.x) / 2.0, y: (tl.y + tr.y) / 2.0)
    let bottomMid = CGPoint(x: (bl.x + br.x) / 2.0, y: (bl.y + br.y) / 2.0)
    let dx = topMid.x - bottomMid.x
    let dy = topMid.y - bottomMid.y
    let len = max(1.0, sqrt(dx * dx + dy * dy))
    let dir = CGPoint(x: dx / len, y: dy / len)

    // Pad the top edge outward by a fraction of the detected receipt height.
    let extra = len * max(0.0, extraTopPaddingFraction)
    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, bounds.minX), bounds.maxX),
            y: min(max(p.y, bounds.minY), bounds.maxY)
        )
    }

    tl = clamp(CGPoint(x: tl.x + dir.x * extra, y: tl.y + dir.y * extra))
    tr = clamp(CGPoint(x: tr.x + dir.x * extra, y: tr.y + dir.y * extra))
    return (tl, tr, bl, br)
}

/// Inflates a quad uniformly, then adds extra padding on both the top and bottom edges.
/// Useful to avoid clipping both the header and the Subtotal/Tax/Total section on long receipts.
private func inflateQuadWithVerticalPadding(
    topLeft: CGPoint,
    topRight: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    scale: CGFloat,
    extraTopPaddingFraction: CGFloat,
    extraBottomPaddingFraction: CGFloat,
    bounds: CGRect
) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    var (tl, tr, bl, br) = inflateQuad(
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        scale: scale,
        bounds: bounds
    )

    let topMid = CGPoint(x: (tl.x + tr.x) / 2.0, y: (tl.y + tr.y) / 2.0)
    let bottomMid = CGPoint(x: (bl.x + br.x) / 2.0, y: (bl.y + br.y) / 2.0)
    let dx = topMid.x - bottomMid.x
    let dy = topMid.y - bottomMid.y
    let len = max(1.0, sqrt(dx * dx + dy * dy))
    let dir = CGPoint(x: dx / len, y: dy / len)

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, bounds.minX), bounds.maxX),
            y: min(max(p.y, bounds.minY), bounds.maxY)
        )
    }

    let extraTop = len * max(0.0, extraTopPaddingFraction)
    let extraBottom = len * max(0.0, extraBottomPaddingFraction)

    // Push top edge outward along dir
    tl = clamp(CGPoint(x: tl.x + dir.x * extraTop, y: tl.y + dir.y * extraTop))
    tr = clamp(CGPoint(x: tr.x + dir.x * extraTop, y: tr.y + dir.y * extraTop))
    // Push bottom edge outward opposite dir
    bl = clamp(CGPoint(x: bl.x - dir.x * extraBottom, y: bl.y - dir.y * extraBottom))
    br = clamp(CGPoint(x: br.x - dir.x * extraBottom, y: br.y - dir.y * extraBottom))

    return (tl, tr, bl, br)
}

// Animated dumpling rain view
struct DumplingRainView: View {
    @State private var animating = false
    let dumplingCount = 16
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<dumplingCount, id: \.self) { i in
                    DumplingEmojiView(index: i, width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct DumplingEmojiView: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    @State private var y: CGFloat = -100
    var body: some View {
        let x = CGFloat.random(in: 0...(width-40))
        let delay = Double.random(in: 0...(index.isMultiple(of: 2) ? 0.5 : 1.0))
        Text("🥟")
            .font(.system(size: 40))
            .position(x: x, y: y)
            .onAppear {
                withAnimation(.easeIn(duration: 2.0).delay(delay)) {
                    y = height + 40
                }
            }
    }
}

// Animated boba rain view
struct BobaRainView: View {
    @State private var animating = false
    let bobaCount = 16
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<bobaCount, id: \.self) { i in
                    BobaEmojiView(index: i, width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct BobaEmojiView: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    @State private var y: CGFloat = -100
    var body: some View {
        let x = CGFloat.random(in: 0...(width-40))
        let delay = Double.random(in: 0...(index.isMultiple(of: 2) ? 0.5 : 1.0))
        Text("🧋")
            .font(.system(size: 40))
            .position(x: x, y: y)
            .onAppear {
                withAnimation(.easeIn(duration: 2.0).delay(delay)) {
                    y = height + 40
                }
            }
    }
}

